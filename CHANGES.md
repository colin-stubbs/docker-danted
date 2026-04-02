# Changes

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
