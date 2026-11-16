# PostgreSQL 18.7 + PL/Python3u + pgvector

A minimal container based on the official `postgres:18.7` image.

Includes:
- **PostgreSQL 18.7** with the `plpython3u` and `vector` (pgvector) extensions installed
  (enable per database with `CREATE EXTENSION plpython3u;` / `CREATE EXTENSION vector;`)
- Default database `postgres`, superuser `postgres` / password `postgres`
- **psql**, preconfigured (`PGUSER`, `PGPASSWORD`, `PGDATABASE`) to log in as `postgres`
- **python3** (with `pip` and `venv`; the same interpreter PL/Python uses)
- **jq**
- **curl**
- **vi** (`vim-tiny`)
- **glow** (Markdown viewer, e.g. `jq -r '.choices[0].message.content' chat-output.md | glow -`)

> The credentials are for local development and training only.

## API keys

Keys such as `MISTRAL_API_KEY` are passed into the container as environment variables
from `container/secrets.env`, which is git-ignored:

```bash
cd container
cp secrets.env.example secrets.env   # then edit secrets.env and add your key
docker compose up -d                 # recreates the container with the new variables
```

The variable is then available to `curl` inside the container and to the Postgres
server itself (e.g. `os.environ['MISTRAL_API_KEY']` in PL/Python).

## Build and run

```bash
cd container
docker compose up -d --build
```

Or without Compose:

```bash
docker build -t dlh-ai-postgres:18.7 .
docker run -d --name pg18 -p 5432:5432 dlh-ai-postgres:18.7
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
docker exec pg18 python3 --version
docker exec pg18 jq --version
docker exec pg18 curl --version
docker exec pg18 vi --version | head -1
docker exec pg18 glow --version
```

## Reset

The init script in `initdb/` runs only when the data volume is first created. To start fresh:

```bash
docker compose down -v
```
