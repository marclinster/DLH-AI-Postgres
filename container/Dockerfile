# syntax=docker/dockerfile:1
# PostgreSQL 18.7 + PL/Python3u + pgvector, with psql, python3, jq, curl, vi and glow
FROM postgres:18.7-trixie

# Exact pgvector build for PostgreSQL 18.7 (PGDG, Debian 13 / trixie)
ARG PGVECTOR_VERSION=0.8.7-1.pgdg13+2

# Default database and superuser (postgres/postgres)
ENV POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres \
    POSTGRES_DB=postgres

# Defaults so a plain `psql` logs in as postgres/postgres
ENV PGUSER=postgres \
    PGPASSWORD=postgres \
    PGDATABASE=postgres

################################################################################
# PL/Python3u (pinned to the server version), pgvector (pinned), python3 (+pip, venv),
# jq, curl, vi, glow
# psql ships with the base image.
################################################################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      "postgresql-plpython3-${PG_MAJOR}=${PG_VERSION}" \
      "postgresql-${PG_MAJOR}-pgvector=${PGVECTOR_VERSION}" \
      python3 \
      python3-pip \
      python3-venv \
      jq \
      curl \
      vim-tiny \
      glow \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Init scripts (run once, on first init)
COPY initdb/ /docker-entrypoint-initdb.d/
COPY files/ /

EXPOSE 5432

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD pg_isready -h localhost -p 5432 -U postgres || exit 1

LABEL description="PostgreSQL 18.7 with PL/Python3u, pgvector, psql, python3, jq, curl, vi and glow" \
      postgresql.version="18.7" \
      base.image="postgres:18.7-trixie" \
      pgvector.version="${PGVECTOR_VERSION}"
