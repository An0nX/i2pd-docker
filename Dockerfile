# syntax=docker/dockerfile:1

#
# Copyright (c) 2017-2022, The PurpleI2P Project
#
# This file is part of Purple i2pd project and licensed under BSD3
#
# See full license text in LICENSE file at top of project tree
#

# ── Глобальные ARG (доступны во всех стейджах) ──────────────
ARG BUILD_IMAGE=dhi.io/alpine-base:3.23-dev
ARG RUNTIME_IMAGE=gcr.io/distroless/static:nonroot

# ═════════════════════════════════════════════════════════════
#  Stage 1 — сборка полностью статического бинарника
# ═════════════════════════════════════════════════════════════
FROM ${BUILD_IMAGE} AS builder

# Аргументы сборки — не попадают в рантайм-образ
ARG GIT_BRANCH="openssl"
ARG GIT_TAG=""
ARG REPO_URL="https://github.com/PurpleI2P/i2pd.git"

# ── APK: кеш-маунт вместо --no-cache ────────────────────────
# При повторной сборке apk не перекачивает индексы и пакеты,
# а берёт их из BuildKit-кеша.
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

# ── Git clone: отдельный слой ────────────────────────────────
# Инвалидируется только при смене GIT_BRANCH / REPO_URL,
# а шаг компиляции ниже может переиспользовать ccache.
WORKDIR /src

RUN git clone --single-branch --depth=1 \
        -b "${GIT_BRANCH}" "${REPO_URL}" i2pd

WORKDIR /src/i2pd

RUN if [ -n "${GIT_TAG}" ]; then \
        git fetch --tags --depth=1 && \
        git checkout "tags/${GIT_TAG}"; \
    fi

# ── Компиляция: ccache + кеш объектных файлов ───────────────
# ccache кеширует результаты компиляции между сборками;
# даже если слой git clone инвалидировался, но исходники
# не изменились — ccache отдаст готовые .o мгновенно.
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
    && strip --strip-all --remove-section=.comment --remove-section=.note i2pd

# ═════════════════════════════════════════════════════════════
#  Stage 2 — минимальный рантайм-образ (без shell, без libc)
# ═════════════════════════════════════════════════════════════
FROM ${RUNTIME_IMAGE}

# OCI-метаданные
LABEL org.opencontainers.image.title="i2pd" \
      org.opencontainers.image.description="Purple I2P Daemon — full C++ I2P router" \
      org.opencontainers.image.source="https://github.com/PurpleI2P/i2pd" \
      org.opencontainers.image.documentation="https://i2pd.readthedocs.io/en/latest/" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.authors="Mikal Villa <mikal@sigterm.no>, Darknet Villain <supervillain@riseup.net>" \
      maintainer="R4SAS <r4sas@i2pmail.org>"

# ── Иммутабельная конфигурация (/etc/i2pd) ──────────────────
COPY --from=builder --chown=nonroot:nonroot \
     /src/i2pd/contrib/certificates /etc/i2pd/certificates

COPY --from=builder --chown=nonroot:nonroot \
     /src/i2pd/contrib/docker/i2pd-docker.conf /etc/i2pd/i2pd.conf

# ── Статический бинарник ─────────────────────────────────────
COPY --from=builder --chown=nonroot:nonroot \
     /src/i2pd/i2pd /usr/local/bin/i2pd

# ── Мутабельные данные ───────────────────────────────────────
VOLUME /home/nonroot/data

EXPOSE 7070 4444 4447 7656 2827 7654 7650

# nonroot (UID 65532) — встроенный пользователь distroless:nonroot
ENTRYPOINT ["/usr/local/bin/i2pd"]
CMD [ \
    "--datadir=/home/nonroot/data", \
    "--conf=/etc/i2pd/i2pd.conf",  \
    "--certsdir=/etc/i2pd/certificates" \
]
