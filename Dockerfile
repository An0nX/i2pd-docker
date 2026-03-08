# syntax=docker/dockerfile:1

ARG BUILD_IMAGE=dhi.io/alpine-base:3.23-dev
ARG RUNTIME_IMAGE=gcr.io/distroless/static:nonroot

# ═════════════════════════════════════════════════════════════
#  Stage 1 — Сборка статического бинарника
# ═════════════════════════════════════════════════════════════
FROM ${BUILD_IMAGE} AS builder

ARG GIT_BRANCH="openssl"
ARG GIT_TAG=""
ARG REPO_URL="https://github.com/PurpleI2P/i2pd.git"

# Установка зависимостей с кешем
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    --mount=type=cache,target=/etc/apk/cache,sharing=locked \
    apk add \
        boost-dev            \
        boost-static         \
        build-base           \
        ccache               \
        git                  \
        libtool              \
        make                 \
        miniupnpc-dev        \
        openssl-dev          \
        openssl-libs-static  \
        zlib-dev             \
        zlib-static

WORKDIR /src

# Клонирование репозитория
RUN git clone --single-branch --depth=1 \
        -b "${GIT_BRANCH}" "${REPO_URL}" i2pd

WORKDIR /src/i2pd

# Чекаут конкретного тега если указан
RUN if [ -n "${GIT_TAG}" ]; then \
        git fetch --tags --depth=1 && \
        git checkout "tags/${GIT_TAG}"; \
    fi

# Сборка
ENV CCACHE_DIR=/tmp/.ccache

RUN --mount=type=cache,target=/tmp/.ccache,sharing=locked \
    make -j"$(nproc)" \
        USE_UPNP=yes \
        USE_STATIC=yes \
        DEBUG=no \
        LIBDIR=/usr/lib \
        CC="ccache gcc" \
        CXX="ccache g++" \
        CXXFLAGS="-O2 -flto=auto \
                  -ffunction-sections -fdata-sections \
                  -fstrict-aliasing -fvariable-expansion-in-unroller \
                  -fgcse -fgcse-las -fcode-hoisting \
                  -ftree-vectorize -ftree-loop-distribution -ftree-loop-linear \
                  -ftree-slp-vectorize \
                  -finline-small-functions -finline-functions-called-once \
                  -freorder-blocks -freorder-functions \
                  -fomit-frame-pointer \
                  -fmerge-all-constants -fmerge-constants \
                  -fno-asynchronous-unwind-tables -fno-unwind-tables \
                  -fno-ident -fno-common \
                  -march=native -mtune=native" \
        LDFLAGS="-flto=auto \
                 -Wl,--gc-sections -Wl,-O2 -Wl,--sort-common \
                 -s"

# Проверка, что бинарник существует
RUN test -f /src/i2pd/i2pd || (echo "ERROR: Binary not found!" && exit 1)
RUN ldd /src/i2pd/i2pd || true  # Проверка зависимостей
RUN file /src/i2pd/i2pd         # Проверка типа файла

# Копирование в /output
RUN mkdir -p /output/bin && \
    cp /src/i2pd/i2pd /output/bin/ && \
    strip --strip-all /output/bin/i2pd

# Финальная проверка
RUN ls -lah /output/bin/i2pd && file /output/bin/i2pd

# ═════════════════════════════════════════════════════════════
#  Stage 2 — Runtime образ
# ═════════════════════════════════════════════════════════════
FROM ${RUNTIME_IMAGE}

LABEL org.opencontainers.image.title="i2pd" \
      org.opencontainers.image.description="Purple I2P Daemon — full C++ I2P router" \
      org.opencontainers.image.source="https://github.com/PurpleI2P/i2pd" \
      org.opencontainers.image.documentation="https://i2pd.readthedocs.io/en/latest/" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.authors="Mikal Villa <mikal@sigterm.no>"

# Конфигурация
COPY --from=builder --chown=nonroot:nonroot \
     /src/i2pd/contrib/certificates /etc/i2pd/certificates

COPY --from=builder --chown=nonroot:nonroot \
     /src/i2pd/contrib/docker/i2pd-docker.conf /etc/i2pd/i2pd.conf

# Копируем бинарник в корень (distroless требует именно так)
COPY --from=builder --chown=nonroot:nonroot \
     /output/bin/i2pd /i2pd

# Том для данных
VOLUME /home/nonroot/data

EXPOSE 7070 4444 4447 7656 2827 7654 7650

# ENTRYPOINT и CMD
ENTRYPOINT ["/i2pd"]
CMD [ \
    "--datadir=/home/nonroot/data", \
    "--conf=/etc/i2pd/i2pd.conf",  \
    "--certsdir=/etc/i2pd/certificates" \
]
