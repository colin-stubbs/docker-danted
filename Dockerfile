FROM debian:forky-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         dante-server \
         iproute2 \
         netcat-openbsd \
         curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY danted.conf /etc/danted.conf
COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck
RUN chmod +x /entrypoint.sh /usr/local/bin/healthcheck

EXPOSE 1080

HEALTHCHECK --interval=30s --timeout=15s --start-period=10s --retries=3 \
  CMD ["/usr/local/bin/healthcheck"]

ENTRYPOINT ["/entrypoint.sh"]
