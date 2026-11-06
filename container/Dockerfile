# syntax=docker/dockerfile:1
# PostgreSQL 18.6 + PL/Python3u + pgvector, with psql, jq, curl and vi
FROM postgres:18.6

# Default database and superuser (postgres/postgres)
ENV POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres \
    POSTGRES_DB=postgres

# Defaults so a plain `psql` logs in as postgres/postgres
ENV PGUSER=postgres \
    PGPASSWORD=postgres \
    PGDATABASE=postgres

################################################################################
# PL/Python3u (pinned to the server version), pgvector, jq, curl, vi
# psql ships with the base image.
################################################################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      "postgresql-plpython3-${PG_MAJOR}=${PG_VERSION}" \
      "postgresql-${PG_MAJOR}-pgvector" \
      jq \
      curl \
      vim-tiny \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Init scripts (run once, on first init)
COPY initdb/ /docker-entrypoint-initdb.d/
COPY files/ /

EXPOSE 5432

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD pg_isready -h localhost -p 5432 -U postgres || exit 1

LABEL description="PostgreSQL 18.6 with PL/Python3u, pgvector, psql, jq, curl and vi" \
      postgresql.version="18.6" \
      base.image="postgres:18.6"
