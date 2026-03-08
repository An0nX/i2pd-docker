# 🐳 i2pd-docker

[![Docker Image Size](https://img.shields.io/docker/image-size/whn0thacked/i2pd-docker?style=flat-square&logo=docker&color=blue)](https://hub.docker.com/r/whn0thacked/i2pd-docker)
[![Docker Pulls](https://img.shields.io/docker/pulls/whn0thacked/i2pd-docker?style=flat-square&logo=docker)](https://hub.docker.com/r/whn0thacked/i2pd-docker)
[![Architecture](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-important?style=flat-square)](#)
[![Security: non-root](https://img.shields.io/badge/security-non--root-success?style=flat-square)](#)
[![Base Image](https://img.shields.io/badge/base-distroless%2Fstatic%3Anonroot-blue?style=flat-square)](https://github.com/GoogleContainerTools/distroless)
[![Upstream](https://img.shields.io/badge/upstream-i2pd-008751?style=flat-square)](https://github.com/PurpleI2P/i2pd)

A minimal, secure, and production-oriented Docker image for **i2pd** — a C++ implementation of the **I2P** (Invisible Internet Project) anonymous network layer.

Built as a **fully static** binary and shipped in a **distroless** runtime image, running as **non-root** by default.

---

## ✨ Features

- **🔐 Secure by default:** Distroless runtime + non-root user + read-only filesystem.
- **🏗 Multi-arch:** Supports `amd64` and `arm64`.
- **📦 Static binary:** Built for `gcr.io/distroless/static:nonroot` — no libc, no dynamic linker.
- **🌐 Full-featured:** I2P router with NTCP2/SSU2, SOCKS/HTTP proxy, SAM, BOB, I2CP, I2PControl.
- **🧾 Config-driven:** Mount config files or configure via CLI flags.
- **🔄 Auto-updated:** CI checks for new upstream releases and rebuilds automatically.
- **🧰 Build-time pinning:** Upstream repo/ref are configurable via build args.

---

## ⚠️ Important Notice

I2P is an anonymous network layer. Using I2P may be restricted, monitored, or illegal depending on your jurisdiction. Operating I2P routers, servers, or tunnels carries additional legal and operational considerations.

**You are responsible for compliance with local laws** and for safe deployment (firewalling, access control, logging, monitoring).

i2pd is under **active development**. While functional and production-ready, always check the [upstream repository](https://github.com/PurpleI2P/i2pd) for the latest updates and security advisories.

---

## 🚀 Quick Start

### Docker Compose (recommended)

Create `docker-compose.yml`:

```yaml
services:
  i2pd:
    image: whn0thacked/i2pd-docker:latest
    container_name: i2pd
    restart: unless-stopped

    entrypoint: ["/i2pd"]
    command:
      - "--datadir=/home/nonroot/data"
      - "--conf=/etc/i2pd/i2pd.conf"
      - "--tunconf=/etc/i2pd/tunnels.conf"
      - "--certsdir=/etc/i2pd/certificates"

    volumes:
      - i2pd_data:/home/nonroot/data
      - ./i2pd.conf:/etc/i2pd/i2pd.conf:ro
      # - ./tunnels.conf:/etc/i2pd/tunnels.conf:ro

    ports:
      - "4567:4567/tcp"
      - "4567:4567/udp"
      - "127.0.0.1:7070:7070/tcp"
      - "127.0.0.1:4447:4447/tcp"

    read_only: true
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL

    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "2.0"
        reservations:
          memory: 128M

    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

    healthcheck:
      test: ["CMD", "/i2pd", "--version"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  i2pd_data:
    name: i2pd_data
```

```bash
docker compose up -d
```

Verify:

```bash
curl http://127.0.0.1:7070
# Should return i2pd web console HTML
```

### Docker Run (one-liner)

```bash
docker run -d --name i2pd \
  -p 4567:4567/tcp -p 4567:4567/udp \
  -p 127.0.0.1:7070:7070 \
  -p 127.0.0.1:4447:4447 \
  -v i2pd_data:/home/nonroot/data \
  -v ./i2pd.conf:/etc/i2pd/i2pd.conf:ro \
  --read-only \
  --security-opt no-new-privileges:true --cap-drop ALL \
  --memory 512m --cpus 2.0 \
  --restart unless-stopped \
  whn0thacked/i2pd-docker:latest \
  --datadir=/home/nonroot/data \
  --conf=/etc/i2pd/i2pd.conf
```

---

## ⚙️ Configuration Reference

### CLI Parameters

| Parameter | Description |
|---|---|
| `--datadir PATH` | Directory for persistent data (keys, NetDB, logs). |
| `--conf FILE` | Path to main configuration file (`i2pd.conf`). |
| `--tunconf FILE` | Path to tunnels configuration file (`tunnels.conf`). |
| `--certsdir PATH` | Directory for SSL/TLS certificates. |
| `--log FILE` | Log file path (use `stdout` for container logs). |
| `--daemon` | Run in background (not needed in Docker). |

### Ports

| Port | Protocol | Purpose |
|---:|---|---|
| `4567` | TCP/UDP | I2P transport (NTCP2 / SSU2) — must match `port=` in i2pd.conf |
| `7070` | TCP | Web console (admin panel) — bound to localhost by default |
| `4447` | TCP | SOCKS5 proxy — for anonymized application traffic |
| `4444` | TCP | HTTP proxy — for browser traffic (optional) |
| `7656` | TCP | SAM bridge — for I2P application integration |
| `2827` | TCP | BOB interface — alternative tunnel protocol |
| `7654` | TCP | I2CP interface — for client applications |
| `7650` | TCP | I2PControl (JSON-RPC) — remote control API |

### Volumes

| Container Path | Purpose | Backup |
|---|---|---|
| `/home/nonroot/data` | Persistent state: router keys, NetDB, address book, logs | **Critical** — losing = new router identity |
| `/etc/i2pd/i2pd.conf` | Main configuration file (mount read-only from host) | Optional |
| `/etc/i2pd/tunnels.conf` | Tunnel definitions (mount read-only from host) | Optional |
| `/etc/i2pd/certificates` | SSL/TLS certificates for HTTPS web console | Optional |

### Configuration Files

| File | Description |
|---|---|
| `i2pd.conf` | Main router configuration: ports, limits, network settings, features |
| `tunnels.conf` | Client and server tunnel definitions for I2P services |

---

## 🧠 Container Behavior

- **ENTRYPOINT:** `/usr/local/bin/i2pd`
- **CMD (default):**

```text
--datadir=/home/nonroot/data \
--conf=/etc/i2pd/i2pd.conf \
--tunconf=/etc/i2pd/tunnels.conf
```

The container runs an I2P router with NTCP2/SSU2 transport, web console on `7070`, and SOCKS5 proxy on `4447`.

Override by passing your own arguments:

```bash
docker run ... whn0thacked/i2pd-docker:latest --datadir=/custom/path
docker run ... whn0thacked/i2pd-docker:latest --conf=/etc/i2pd/custom.conf
```

---

## 📝 Advanced Usage

### Custom config file

```bash
docker run -d --name i2pd \
  -p 4567:4567/tcp -p 4567:4567/udp \
  -p 127.0.0.1:7070:7070 \
  -v ./i2pd.conf:/etc/i2pd/i2pd.conf:ro \
  -v i2pd_data:/home/nonroot/data \
  --read-only \
  --security-opt no-new-privileges:true --cap-drop ALL \
  whn0thacked/i2pd-docker:latest \
  --datadir=/home/nonroot/data \
  --conf=/etc/i2pd/i2pd.conf
```

### Enable HTTP Proxy

Uncomment in compose or add to docker run:

```yaml
ports:
  - "127.0.0.1:4444:4444/tcp"
```

```ini
# In i2pd.conf
[http]
enabled=true
port=4444
```

### Enable SAM Bridge (for I2P applications)

```yaml
ports:
  - "127.0.0.1:7656:7656/tcp"
```

```ini
# In i2pd.conf
[sam]
enabled=true
port=7656
```

### Use with applications

```bash
# curl through SOCKS5
curl --socks5-hostname 127.0.0.1:4447 http://example.i2p

# Environment variable (works with many apps)
ALL_PROXY=socks5h://127.0.0.1:4447 curl http://example.i2p

# proxychains
echo "socks5 127.0.0.1 4447" >> /etc/proxychains.conf
proxychains curl http://example.i2p

# Firefox: Settings → Network → Manual Proxy → SOCKS Host: 127.0.0.1:4447
# ✅ Check "Proxy DNS when using SOCKS v5"
```

---

## 🌐 I2P Services

### Running an I2P server (e.g., website)

Edit `tunnels.conf` to add a server tunnel:

```ini
[example-website]
type=webserver
host=127.0.0.1
port=80
inbound.quantity=3
outbound.quantity=3
inbound.length=3
outbound.length=3
accessList=your-base64-destination
```

Restart container:

```bash
docker compose restart i2pd
```

Find your destination in web console (`http://127.0.0.1:7070/?page=i2ptunnels`).

### Key management

Router keys are stored in `/home/nonroot/data/`:

| File | Purpose |
|---|---|
| `router.info` | Router identity (public) |
| `router.key` | Router private key (**critical**) |
| `netDB/` | Network database cache |
| `addressbook/` | Subscription addresses |

**Backup `router.key`** — losing it means losing your router identity.

---

## 🛡️ Security Hardening

This image applies the following hardening measures:

| Measure | Description |
|---|---|
| **Distroless base** | No shell, no package manager, no utilities — minimal attack surface |
| **Non-root** | Runs as UID 65534 (`nonroot`) |
| **Read-only FS** | Root filesystem is read-only; data via named volume |
| **No capabilities** | All Linux capabilities dropped (`cap_drop: ALL`) |
| **No privilege escalation** | `no-new-privileges` prevents setuid/setgid abuse |
| **Resource limits** | CPU and memory limits prevent DoS |
| **Log rotation** | Prevents disk exhaustion |
| **Localhost binding** | Sensitive ports bound to `127.0.0.1` by default in examples |

---

## 🛠 Build

This Dockerfile supports pinning upstream i2pd source:

- `I2PD_REPO` (default: `https://github.com/PurpleI2P/i2pd.git`)
- `I2PD_REF` (default: `master`)

### Multi-arch build

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t whn0thacked/i2pd-docker:latest \
  --push .
```

### Build a specific commit

```bash
docker buildx build \
  --build-arg I2PD_REF=a1b2c3d4e5f6 \
  -t whn0thacked/i2pd-docker:dev \
  --push .
```

### Local test build

```bash
docker buildx build --load -t i2pd:test .
docker run --rm i2pd:test --version
```

> **Note:** First build takes **10–30 minutes** due to C++ compilation. Subsequent builds are faster thanks to BuildKit cache.

---

## 🔗 Useful Links

- **i2pd upstream:** https://github.com/PurpleI2P/i2pd
- **i2pd documentation:** https://i2pd.readthedocs.io/
- **i2pd configuration:** https://i2pd.readthedocs.io/en/latest/user-guide/configuration.html
- **I2P Project:** https://geti2p.net/
- **Distroless images:** https://github.com/GoogleContainerTools/distroless

---

## 📄 License

This Dockerfile, CI pipeline, and associated documentation are licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html).

i2pd itself is licensed under **BSD 3-Clause** by the [I2P Project](https://geti2p.net/).
