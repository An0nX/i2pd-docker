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
        LDFLAGS="-static -static-libstdc++ -static-libgcc \
                 -flto=auto \
                 -Wl,--gc-sections -Wl,-O2 -Wl,--sort-common \
                 -s"

# ═════════════════════════════════════════════════════════════
#  Автоматический поиск и подготовка файлов (Staging)
# ═════════════════════════════════════════════════════════════
# Создаем структуру папок, какой она должна быть в Distroless
RUN mkdir -p /staging/etc/i2pd

RUN set -e; \
    # 1. Ищем исполняемый бинарник i2pd
    BIN_PATH=$(find /src -type f -name "i2pd" -executable | head -n 1); \
    if [ -z "$BIN_PATH" ]; then echo "ERROR: Binary not found!" && exit 1; fi; \
    echo "=> Found binary at: $BIN_PATH"; \
    cp "$BIN_PATH" /staging/i2pd; \
    strip --strip-all /staging/i2pd; \
    \
    # 2. Ищем папку certificates
    # grep "contrib" гарантирует, что мы возьмем папку с исходными сертами, а не случайную
    CERTS_PATH=$(find /src -type d -name "certificates" | grep "contrib" | head -n 1); \
    if [ -z "$CERTS_PATH" ]; then echo "ERROR: Certificates dir not found!" && exit 1; fi; \
    echo "=> Found certificates at: $CERTS_PATH"; \
    cp -r "$CERTS_PATH" /staging/etc/i2pd/certificates; \
    \
    # 3. Ищем docker-конфиг
    CONF_PATH=$(find /src -type f -name "i2pd-docker.conf" | head -n 1); \
    if [ -z "$CONF_PATH" ]; then echo "ERROR: Config not found!" && exit 1; fi; \
    echo "=> Found config at: $CONF_PATH"; \
    cp "$CONF_PATH" /staging/etc/i2pd/i2pd.conf

# Проверка, что всё на месте
RUN ls -lah /staging/i2pd && file /staging/i2pd


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

# Забираем всё собранное дерево файлов одной командой.
# /staging/i2pd ляжет в /i2pd
# /staging/etc/i2pd/* ляжет в /etc/i2pd/*
COPY --from=builder --chown=nonroot:nonroot /staging /

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
