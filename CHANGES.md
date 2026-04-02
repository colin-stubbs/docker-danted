# Changes

* 2026-04-02 - entrypoint: Dante `-N` from online CPU count

- **`entrypoint.sh`**: Detects online CPUs (`nproc`, else `getconf _NPROCESSORS_ONLN`, else `1`); starts `danted` with `-N` set to that count. Optional override **`DANTE_N`**. Documented in README.md and dot-env-example.

* 2026-04-02 - CI: push `latest` to GHCR on default-branch builds

- `.github/workflows/build.yml`: `docker/metadata-action` `type=raw` adds tag `latest` when `github.ref` is the default branch (same image as `main` / branch name)

* 2026-04-02 - DANTE_ASSIGN_IPV4 / DANTE_ASSIGN_IPV6 run `ip addr add` before discovery

- entrypoint.sh: optional comma- or space-separated `addr/prefix` lists applied with `ip addr add` on `DANTE_DEVICE` (or auto-detected interface) before `ip` discovery and danted.conf generation; requires `CAP_NET_ADMIN` when adding new addresses
- Replaced prior merge-only `DANTE_EXTERNAL_*` behaviour; documented in dot-env-example, README.md, danted.conf header, `danted.container`, and compose.yml `cap_add` comment

* 2026-04-02 - Quadlet: dual-stack network and extra IP documentation

- Added `proxy_net.network` Quadlet unit (IPv4 + IPv6 subnets) for use with `danted.container`
- Updated `danted.container` with `Network=`, `IP=`, `IP6=`, `Sysctl=`, and comments for additional IPv4/IPv6 beyond the primary pair
- Documented Podman Quadlet install and multi-address options in README.md

* 2026-04-02 - Initial release

- Dockerfile based on debian:forky-slim with dante-server 1.4.4 from apt (amd64 + arm64)
- entrypoint.sh with automatic IPv4/IPv6 address detection and dynamic danted.conf generation
- Default danted.conf based on upstream Debian package config with container-appropriate defaults
- Default listen port 1080 (standard SOCKS5), configurable via DANTE_PORT
- Read-only root filesystem support: auto-generated config written to /tmp/danted.conf, TMPDIR=/run/danted for danted lockfiles and mmap'd files, /run tmpfs without noexec (required by danted)
- All logging to stderr only (no file logging); rules log errors only by default
- DANTE_CONFIG_FILE env var to skip auto-detection and use a custom mounted config
- Environment variables for all tunables: port, rotation, auth methods, user identities
- compose.yml example with dual-stack bridge network (IPv4 + IPv6)
- GitHub Actions CI pipeline: Hadolint, ShellCheck, Trivy filesystem scan, multi-arch build+push to GHCR, Trivy container image scan with SARIF upload
- Trivy pinned to ghcr.io/aquasecurity/trivy:0.69.3 and trivy-action v0.35.0 (post CVE-2026-336 remediation)
- .hadolint.yaml (DL3008 ignored), .trivyignore (DS-0002 suppressed — danted requires root at startup)
- Comprehensive README.md with features, quick start, configuration reference, architecture, local build/test/lint instructions, and CI documentation
- Added example Podman Quadlet file `danted.container` for systemd-managed container deployment
