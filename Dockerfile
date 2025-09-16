FROM postgres:16-bookworm AS builder

RUN echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/backports.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        git \
        golang-1.22-go \
        flex \
        bison \
        postgresql-server-dev-16 \
        wget \
        curl && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/go-1.22/bin:$PATH"

RUN git clone --depth 1 --branch v0.5.1 https://github.com/pgvector/pgvector.git /tmp/pgvector && \
    cd /tmp/pgvector && \
    make clean && \
    make OPTFLAGS="" && \
    make install && \
    rm -rf /tmp/pgvector

RUN git clone --depth 1 --branch release/PG16/1.5.0 https://github.com/apache/age.git /tmp/age && \
    cd /tmp/age && \
    make PG_CONFIG=/usr/bin/pg_config && \
    make install PG_CONFIG=/usr/bin/pg_config && \
    rm -rf /tmp/age

RUN ls -la /usr/lib/postgresql/16/lib/ | grep -E "(vector|age)" && \
    ls -la /usr/share/postgresql/16/extension/ | grep -E "(vector|age)"

FROM postgres:16-bookworm AS runtime

# Build arguments for metadata
ARG VERSION="dev"
ARG BUILD_DATE
ARG VCS_REF

COPY --from=builder /usr/lib/postgresql/16/lib/vector.so /usr/lib/postgresql/16/lib/
COPY --from=builder /usr/lib/postgresql/16/lib/age.so /usr/lib/postgresql/16/lib/
COPY --from=builder /usr/share/postgresql/16/extension/vector* /usr/share/postgresql/16/extension/
COPY --from=builder /usr/share/postgresql/16/extension/age* /usr/share/postgresql/16/extension/

COPY init.sql /docker-entrypoint-initdb.d/init.sql
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/healthcheck.sh && \
    chown postgres:postgres /docker-entrypoint-initdb.d/init.sql && \
    chown postgres:postgres /usr/local/bin/healthcheck.sh

RUN echo "# Custom PostgreSQL configuration" >> /usr/share/postgresql/postgresql.conf.sample && \
    echo "shared_preload_libraries = 'age'" >> /usr/share/postgresql/postgresql.conf.sample && \
    echo "log_statement = 'mod'" >> /usr/share/postgresql/postgresql.conf.sample && \
    echo "log_min_duration_statement = 1000" >> /usr/share/postgresql/postgresql.conf.sample && \
    echo "max_connections = 100" >> /usr/share/postgresql/postgresql.conf.sample && \
    echo "shared_buffers = 256MB" >> /usr/share/postgresql/postgresql.conf.sample

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

USER postgres

EXPOSE 5432

ENV POSTGRES_DB=postgres \
    POSTGRES_USER=postgres \
    PGDATA=/var/lib/postgresql/data

# OCI labels for ghcr.io metadata
LABEL org.opencontainers.image.title="postgres-combo" \
      org.opencontainers.image.description="PostgreSQL 16 with pgvector (v0.5.1) and Apache AGE (v1.5.0) extensions" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.vendor="postgres-combo" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="postgres:16-bookworm" \
      maintainer="postgres-combo" \
      postgres.version="16" \
      pgvector.version="0.5.1" \
      age.version="1.5.0"