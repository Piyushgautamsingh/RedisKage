FROM docker.io/bitnami/redis-cluster:7.4-debian-12 AS base

FROM debian:bookworm-slim

ARG VERSION
ARG BUILD_DATE

LABEL maintainer="Piyush Gautam" \
      org.opencontainers.image.name="Redis Cluster Healer" \
      org.opencontainers.image.description="Redis Cluster Healer detects and resolves node failures, manages new pods, and ensures cluster stability." \
      org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.created="$BUILD_DATE" \
      org.opencontainers.image.source="https://github.com/piyushgautamsingh/rediskage" \
      org.opencontainers.image.licenses="MIT"

COPY --from=base /opt/bitnami/scripts/ /opt/bitnami/scripts/
COPY --from=base /opt/bitnami/redis/bin/redis-cli /opt/bitnami/redis/bin/redis-cli

WORKDIR /rediskage

ENV PATH="/opt/bitnami/redis/bin:$PATH" \
    REDIS_PORT_NUMBER=6379 \
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
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd -r rediskage && useradd -r -g rediskage -d /rediskage -s /sbin/nologin rediskage && \
    chown -R rediskage:rediskage /rediskage

COPY ./scripts/ /rediskage/scripts/

RUN chmod +x /rediskage/scripts/*.sh && \
    chown -R rediskage:rediskage /rediskage

USER rediskage

ENTRYPOINT ["/bin/bash", "-c", "/rediskage/scripts/redis-cluster-healer.sh"]
