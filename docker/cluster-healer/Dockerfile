FROM docker.io/bitnami/redis-cluster:7.4-debian-12 as base

FROM debian:bookworm-slim

LABEL maintainer="Piyush Gautam"

COPY --from=base /opt/bitnami/scripts/ /opt/bitnami/scripts/
COPY --from=base /opt/bitnami/redis/bin/redis-cli /opt/bitnami/redis/bin/redis-cli

WORKDIR /rediskage

ENV REDIS_PORT_NUMBER=6379 \
    END_POD_NUMBER=5 \
    REDIS_CLI_TIMEOUT=30 \
    REDIS_CLI_RETRIES=3 \
    REDIS_PASSWORD="" \
    REDIS_TLS_ENABLED="yes" \
    REDIS_CA_CERT="" \
    REDIS_CLIENT_CERT="" \
    REDIS_CLIENT_KEY="" \
    REDIS_RECOVERY_SCRIPT_INTERVAL=60 \
    REDIS_HOST_ADDRS="redis-cluster" \
    REDIS_HEADLESS_SVC_ADDRS="redis-cluster-headless"

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        coreutils \
        curl \
        jq \
        toilet \
        figlet \
        ca-certificates && \
    mkdir -p /usr/local/share/figlet && \
    curl -o /usr/local/share/figlet/doh.flf https://raw.githubusercontent.com/xero/figlet-fonts/master/doh.flf && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd -r rediskage && useradd -r -g rediskage -d /rediskage -s /sbin/nologin rediskage && \
    chown -R rediskage:rediskage /rediskage

COPY ./scripts/ /rediskage/scripts/

RUN chmod +x /rediskage/scripts/*.sh && \
    chown -R rediskage:rediskage /rediskage

USER rediskage

# ENTRYPOINT ["/bin/bash", "-c", "/rediskage/scripts/redis-cluster-healer.sh"]
ENTRYPOINT ["python3", "/rediskage/scripts/key-backup.py"]