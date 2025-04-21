FROM debian:bookworm-slim

ARG VERSION
ARG BUILD_DATE

LABEL maintainer="Piyush Gautam" \
      org.opencontainers.image.name="Rediskage" \
      org.opencontainers.image.description="Rediskage is a reliable backup and restore application designed for Redis clusters." \
      org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.created="$BUILD_DATE" \
      org.opencontainers.image.source="https://github.com/piyushgautamsingh/rediskage" \
      org.opencontainers.image.licenses="Apache-2.0 license"

WORKDIR /rediskage

ENV PATTERN="" \
    SCHEDULE_TIME=60 \
    REDIS_NODES="" \
    REDIS_NODE_LIST="" \
    REDIS_PASSWORD="" \
    CA_CERT="" \
    TLS_CERT="" \
    TLS_KEY="" \
    PATTERN_LIST="" \
    BACKUP_DIR="" \
    S3_ENDPOINT_URL="" \
    S3_BUCKET_NAME="" \
    S3_ACCESS_KEY_ID="" \
    S3_SECRET_ACCESS_KEY=""

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        python3 \
        python3-venv \
        python3-pip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd -r rediskage && useradd -r -g rediskage -d /rediskage -s /sbin/nologin rediskage && \
    chown -R rediskage:rediskage /rediskage

COPY scripts/ /rediskage/scripts/

RUN python3 -m venv /rediskage/venv && \
    /rediskage/venv/bin/pip install --no-cache-dir -r /rediskage/scripts/requirements.txt && \
    chown -R rediskage:rediskage /rediskage

RUN chmod +x /rediskage/scripts/*.py

USER rediskage

ENV PATH="/rediskage/venv/bin:$PATH"

ENTRYPOINT ["python3", "/rediskage/scripts/key_backup.py"]
