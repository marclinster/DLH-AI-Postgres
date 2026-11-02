# PostgreSQL 18.6 + PL/Python3u

A minimal container based on the official `postgres:18.6` image.

Includes:
- **PostgreSQL 18.6** with the `plpython3u` extension (enabled in `postgres` and `template1`)
- Default database `postgres`, superuser `postgres` / password `postgres`
- **psql**, preconfigured (`PGUSER`, `PGPASSWORD`, `PGDATABASE`) to log in as `postgres`
- **jq**
- **curl**

> The credentials are for local development and training only.

## Build and run

```bash
cd container
docker compose up -d --build
```

Or without Compose:

```bash
docker build -t dlh-ai-postgres:18.6 .
docker run -d --name pg18 -p 5432:5432 dlh-ai-postgres:18.6
```

Port 5432 is also used by the container in `docker/`, so run only one of them at a time, or change the host port.

## Connect

```bash
# Inside the container: no arguments needed
docker exec -it pg18 psql

# From the host
psql "postgresql://postgres:postgres@localhost:5432/postgres"
```

## Check that it works

```bash
docker exec pg18 psql -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'plpython3u';"
docker exec pg18 psql -c "DO \$\$ plpy.notice('hello from python') \$\$ LANGUAGE plpython3u;"
docker exec pg18 jq --version
docker exec pg18 curl --version
```

## Reset

The init script in `initdb/` runs only when the data volume is first created. To start fresh:

```bash
docker compose down -v
```
