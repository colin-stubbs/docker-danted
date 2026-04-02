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
RUN chmod +x /entrypoint.sh

EXPOSE 1080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD nc -z 127.0.0.1 ${DANTE_PORT:-1080} || exit 1

ENTRYPOINT ["/entrypoint.sh"]
