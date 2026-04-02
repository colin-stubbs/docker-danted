# docker-danted

[![Build and Push Docker Image](https://github.com/colin-stubbs/docker-danted/actions/workflows/build.yml/badge.svg)](https://github.com/colin-stubbs/docker-danted/actions/workflows/build.yml)

Dante SOCKS5 proxy in a container with automatic dual-stack IPv4/IPv6 support and `same-same` external address rotation.

## Features

- **Dante 1.4.4** — installed from Debian Forky packages (amd64 + arm64)
- **Automatic address detection** — discovers all global-scope IPv4 and IPv6 addresses at startup
- **`same-same` rotation** — outbound source IP matches the IP the client connected to
- **Dual-stack ready** — listens on both `0.0.0.0` and `::` simultaneously
- **Read-only root filesystem** — the container runs with a read-only rootfs for security; the auto-generated config is written to `/tmp/danted.conf` (tmpfs)
- **No file logging** — all output goes to stderr for `docker logs` consumption
- **Environment variable configuration** — all settings tuneable without editing config files
- **Custom config support** — mount your own config and set `DANTE_CONFIG_FILE` to skip auto-detection
- **Multi-architecture** — CI builds for `linux/amd64` and `linux/arm64`
- **Minimal image** — based on `debian:forky-slim`

## Quick Start

### Pull from GHCR

```bash
docker pull ghcr.io/colin-stubbs/docker-danted:latest
```

### Run with Docker CLI

```bash
docker run -d \
  --name danted \
  --read-only \
  --tmpfs /tmp:noexec,nosuid,size=1m \
  --tmpfs /run:nosuid,size=8m \
  -p 1080:1080 \
  ghcr.io/colin-stubbs/docker-danted:latest
```

### Run with Docker Compose

```bash
cp dot-env-example .env
docker compose up -d
```

The included `compose.yml` sets up a dual-stack bridge network with both IPv4 and IPv6 subnets, and runs the container with a read-only root filesystem.

## Configuration

All configuration is handled via environment variables. Copy `dot-env-example` to `.env` and adjust as needed.

| Variable | Default | Description |
|---|---|---|
| `DANTE_PORT` | `1080` | Port to listen on (both IPv4 and IPv6) |
| `DANTE_ROTATION` | `same-same` | External address rotation mode (see below) |
| `DANTE_SOCKSMETHOD` | `none` | SOCKS authentication method |
| `DANTE_CLIENTMETHOD` | `none` | Client authentication method |
| `DANTE_USER_PRIVILEGED` | `root` | Privileged user for danted |
| `DANTE_USER_UNPRIVILEGED` | `nobody` | Unprivileged user danted drops to |
| `DANTE_CONFIG_FILE` | *(unset)* | When set, skip auto-detection and use this config file path |

### Rotation Modes

| Mode | Behaviour |
|---|---|
| `same-same` | Outbound source IP matches the IP the client connected to. Ideal for per-IP rate limit separation. |
| `route` | Use the routing table to select outbound address. Allows cross-protocol (IPv4 client to IPv6 destination). |
| `none` | Always use the first external address. |

## Architecture

### Read-Only Root Filesystem

The container is designed to run with `--read-only`. The entrypoint writes the auto-generated config to `/tmp/danted.conf` (writable via tmpfs). When `DANTE_CONFIG_FILE` is set, no files are written and the specified config is used as-is. Danted stores lockfiles and memory-mapped files in `TMPDIR` (set to `/run/danted` by the entrypoint). The `/run` tmpfs must not have `noexec` because danted needs execute permission on its mmap'd files.

### Auto-Detection Flow

At container startup, `entrypoint.sh`:

1. Discovers all non-loopback, non-link-local **IPv4** addresses via `ip -4 addr show scope global`
2. Discovers all non-loopback, non-link-local **IPv6** addresses via `ip -6 addr show scope global`
3. Generates `/tmp/danted.conf` with each discovered address as an `external:` statement
4. Starts `danted` as PID 1 via `exec` for proper signal handling

All entrypoint informational messages are written to stderr, ensuring they appear in `docker logs` alongside Dante's own output.

### same-same Rotation

With `external.rotation: same-same`, Dante ensures the outbound connection uses the same address the client connected to. This is critical when using multiple outbound IPs to distribute load across independent rate-limit budgets (e.g. CT log servers that rate-limit per source IP).

## Custom Configuration

To use your own Dante config:

1. Create your `danted.conf` file
2. Mount it into the container and set `DANTE_CONFIG_FILE`:

```bash
docker run -d \
  --name danted \
  --read-only \
  --tmpfs /tmp:noexec,nosuid,size=1m \
  --tmpfs /run:nosuid,size=8m \
  -p 1080:1080 \
  -v /path/to/my/danted.conf:/etc/danted.conf:ro \
  -e DANTE_CONFIG_FILE=/etc/danted.conf \
  ghcr.io/colin-stubbs/docker-danted:latest
```

## Multiple IPv6 Addresses (Production)

For production use with multiple outbound IPv6 addresses, assign additional IPs to the container's network interface. With Docker Compose and macvlan/ipvlan drivers, or by adding addresses post-startup:

```bash
docker exec danted ip -6 addr add 2001:db8:1::11/64 dev eth0
docker exec danted ip -6 addr add 2001:db8:1::12/64 dev eth0
```

Then restart the container so the entrypoint re-detects all addresses.

## Building and Testing Locally

### Build

```bash
docker build -t danted:local .
```

### Run

```bash
docker run --rm -d \
  --name dante-test \
  --read-only \
  --tmpfs /tmp:noexec,nosuid,size=1m \
  --tmpfs /run:nosuid,size=8m \
  -p 1080:1080 \
  danted:local
```

### Verify startup and address detection

```bash
docker logs dante-test
```

### Test SOCKS5 connectivity

```bash
curl -x socks5h://127.0.0.1:1080 https://httpbin.org/ip
```

### Verify healthcheck

```bash
docker inspect --format='{{.State.Health.Status}}' dante-test
```

### Test with Docker Compose (dual-stack)

```bash
cp dot-env-example .env
docker compose up -d
docker compose logs
curl -x socks5h://127.0.0.1:1080 https://httpbin.org/ip
docker compose down
```

### Test custom config mount (DANTE_CONFIG_FILE)

```bash
docker run --rm -d \
  --name dante-test-custom \
  --read-only \
  --tmpfs /tmp:noexec,nosuid,size=1m \
  --tmpfs /run:nosuid,size=8m \
  -v $(pwd)/danted.conf:/etc/danted.conf:ro \
  -e DANTE_CONFIG_FILE=/etc/danted.conf \
  -p 1080:1080 \
  danted:local
```

### Run lint and security checks locally

```bash
# Dockerfile linting
docker run --rm -i hadolint/hadolint < Dockerfile

# Shell script linting
shellcheck entrypoint.sh

# Trivy filesystem scan (vuln, misconfig, secret detection)
docker run --rm -v "$(pwd):/src:ro" ghcr.io/aquasecurity/trivy:0.69.3 fs --ignorefile /src/.trivyignore --scanners vuln,misconfig,secret --severity HIGH,CRITICAL /src

# Trivy container image scan (after building)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$(pwd)/.trivyignore:/.trivyignore:ro" ghcr.io/aquasecurity/trivy:0.69.3 image --ignorefile /.trivyignore --severity HIGH,CRITICAL danted:local
```

### Cleanup

```bash
docker stop dante-test dante-test-custom 2>/dev/null; true
```

## CI/CD

The GitHub Actions workflow (`.github/workflows/build.yml`) automatically:

- **Lint** — Hadolint for Dockerfile best practices, ShellCheck for `entrypoint.sh`
- **Trivy filesystem scan** — scans source for vulnerabilities, misconfigurations, and secrets (HIGH/CRITICAL)
- **Build** — multi-architecture images (`linux/amd64`, `linux/arm64`) on push to `main` or semver tags
- **Trivy container scan** — scans the published image for vulnerabilities and uploads results as SARIF to GitHub Security
- Pull requests run lint, trivy-fs, and build (no push)
- Uses GitHub Actions cache for Docker layer caching

## License

See repository for license details.
