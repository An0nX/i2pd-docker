# syntax=docker/dockerfile:1

# ── Глобальные ARG (доступны во всех стейджах) ──────────────
ARG BUILD_IMAGE=dhi.io/alpine-base:3.23-dev
ARG RUNTIME_IMAGE=gcr.io/distroless/static:nonroot

# ═════════════════════════════════════════════════════════════
#  Stage 1 — сборка полностью статического бинарника
# ═════════════════════════════════════════════════════════════
FROM ${BUILD_IMAGE} AS builder

ARG GIT_BRANCH="openssl"
ARG GIT_TAG=""
ARG REPO_URL="https://github.com/PurpleI2P/i2pd.git"

# ── APK: кеш-маунт ───────────────────────────────────────────
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

RUN git clone --single-branch --depth=1 \
        -b "${GIT_BRANCH}" "${REPO_URL}" i2pd

WORKDIR /src/i2pd

RUN if [ -n "${GIT_TAG}" ]; then \
        git fetch --tags --depth=1 && \
        git checkout "tags/${GIT_TAG}"; \
    fi

# ── Компиляция + проверка бинарника ──────────────────────────
ENV CCACHE_DIR=/tmp/.ccache

RUN --mount=type=cache,target=/tmp/.ccache,sharing=locked \
    make -j"$(nproc)" \
        USE_UPNP=yes \
        USE_STATIC=yes \
        DEBUG=no \
        LIBDIR=/usr/lib \
        CC="ccache gcc" \
        CXX="ccache g++" \
        CXXFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE -fPIC" \
        LDFLAGS="-Wl,-z,relro -Wl,-z,now -fstack-protector-strong -pie" \
    && make install PREFIX=/output \
    && strip --strip-all /output/bin/i2pd

# ═════════════════════════════════════════════════════════════
#  Stage 2 — минимальный рантайм-образ
# ═════════════════════════════════════════════════════════════
FROM ${RUNTIME_IMAGE}

LABEL org.opencontainers.image.title="i2pd" \
      org.opencontainers.image.description="Purple I2P Daemon — full C++ I2P router" \
      org.opencontainers.image.source="https://github.com/PurpleI2P/i2pd" \
      org.opencontainers.image.documentation="https://i2pd.readthedocs.io/en/latest/" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.authors="Mikal Villa <mikal@sigterm.no>, Darknet Villain <supervillain@riseup.net>" \
      maintainer="R4SAS <r4sas@i2pmail.org>"

# ── Конфигурация ─────────────────────────────────────────────
COPY --from=builder --chown=nonroot:nonroot \
     /src/i2pd/contrib/certificates /etc/i2pd/certificates

COPY --from=builder --chown=nonroot:nonroot \
     /src/i2pd/contrib/docker/i2pd-docker.conf /etc/i2pd/i2pd.conf

# ── Бинарник — копируем в корень для distroless ──────────────
COPY --from=builder --chown=nonroot:nonroot \
     /output/bin/i2pd /i2pd

# ── Мутабельные данные ───────────────────────────────────────
VOLUME /home/nonroot/data

EXPOSE 7070 4444 4447 7656 2827 7654 7650

# nonroot (UID 65532) — встроенный пользователь distroless:nonroot
ENTRYPOINT ["/i2pd"]
CMD [ \
    "--datadir=/home/nonroot/data", \
    "--conf=/etc/i2pd/i2pd.conf",  \
    "--certsdir=/etc/i2pd/certificates" \
]
