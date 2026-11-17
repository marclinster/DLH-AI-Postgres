# AI and Postgres: DLH training class

Scripts, sample databases and a ready-to-run container for the DLH training class on AI with PostgreSQL.

The class starts with SQL basics (psql, JSONB, CTEs, stored procedures, triggers) and builds up to AI features inside the database:

- vector similarity search with `pgvector`
- generating embeddings from PL/Python by calling the Mistral API
- a retriever / narrator / coordinator chatbot (RAG) written in SQL and PL/Python
- error handling and retries for rate-limited API calls
- HNSW and IVFFlat vector indexes, and the speed/accuracy trade-off

## Repository layout

| Path | Contents |
| --- | --- |
| [container/](container/) | Dockerfile and Compose file for PostgreSQL 18.7 with `pgvector`, `plpython3u`, `psql`, `python3`, `jq`, `curl`, `vi` and `glow`. See [container/README.md](container/README.md). |
| [master_setup.sql](master_setup.sql) | Creates (or re-creates) all class databases. |
| [db-setup/](db-setup/) | Schema and data scripts called by `master_setup.sql`. |
| [class/](class/) | The exercises, numbered in the order they are used in class. |

## Quick start

### 1. Start the database container

```bash
cd container
cp secrets.env.example secrets.env   # add your Mistral API key to secrets.env
docker compose up -d --build
```

This starts a container called `pg18` on port 5432, with superuser `postgres` / password `postgres`. The credentials are for local training use only.

`secrets.env` is git-ignored. Its `MISTRAL_API_KEY` is passed into the container, where it is available to `curl` and to PL/Python functions (`os.environ['MISTRAL_API_KEY']`). If you add or change the key later, run `docker compose up -d` again to recreate the container.

### 2. Create the class databases

Run the setup script from the repository root, because it includes the `db-setup/` scripts by relative path:

```bash
psql "postgresql://postgres:postgres@localhost:5432/postgres" -f master_setup.sql
```

The script drops and re-creates each database, so you can run it again at any time to reset the class data. It creates:

| Database | Used for |
| --- | --- |
| `simple_fruit_store` | A first look at vectors: fruits with 3-dimensional hand-made feature vectors |
| `fruit_store` | Generating real embeddings with the Mistral API, and the fruit store chatbot |
| `commerce` | Customers, products, categories, addresses and purchases for the SQL exercises |
| `sportscar` | Brands, models, colors and configurations for the sportscar chatbot exercise |
| `vector_index_demo` | 50,000 synthetic 1024-dimensional vectors for the index exercise (no API calls needed) |


### 3. Connect

```bash
# Inside the container (no arguments needed)
docker exec -it pg18 psql

# From the host
psql "postgresql://postgres:postgres@localhost:5432/commerce"
```
## Versions
The master_setup.sql script checks
* The API key works
* mistral-embed is available and returns a 1024 vector. 
* mistral-large-2512 (used for chat comletion) is available

## Exercises

| File | Topic | Database |
| --- | --- | --- |
| `01-simple-excercide.sql` | Getting comfortable with psql and basic SQL | creates `testdb` |
| `02-jsonb.sql` | Querying JSONB (`->`, `->>`, `#>>`, JSON path) | `commerce` |
| `03-cte.sql` | Common table expressions | `commerce` |
| `04-sproc.sql` | Stored procedures and functions in PL/pgSQL and PL/Python | `commerce` |
| `05-trigger.sql` | Row- and statement-level triggers | `commerce` |
| `06-simple_fruit_store.sql` | Vector distance operators (`<->`, `<=>`, `<#>`, `<+>`) | `simple_fruit_store` |
| `07-curl-examples.txt` | Calling the Mistral embeddings API with `curl` | container shell |
| `081`–`084-my_embedding_*.py` | Calling the embeddings API from Python, with and without error handling | container shell |
| `09-plpython-embedding-generation.sql` | Generating embeddings from PL/Python | `fruit_store` |
| `10-scale-up-embedding-generation.sql` | Generating embeddings in batches | `fruit_store` |
| `11-adding-narration.sql` | Retriever and narrator: a simple RAG chatbot | `fruit_store` |
| `12-sportscar_chat_framework.sql` | Exercise template: build the sportscar chatbot yourself | `sportscar` |
| `13_sportscar_chat_complete.sql` | Solution for the sportscar chatbot | `sportscar` |
| `14-sportscar_embedding_w_retry.sql` | Handling API errors and rate limits with retries | `sportscar` |
| `15-vector-index.sql` | HNSW and IVFFlat indexes, `ef_search` and `probes` tuning | `vector_index_demo` |

The Python scripts are also copied into the container's root directory, so you can run them there, for example `docker exec -it pg18 python3 /081-my_embedding_simple.py`.

For the index exercise, turn on timing in psql (`\timing on`) to compare query times with and without an index.

## Requirements

- Docker (Docker Desktop or another engine with Compose)
- `psql` on the host to run `master_setup.sql`, or copy the repository into the container and run it there
- A Mistral API key for the embedding and chatbot exercises (files `07` to `14-sportscar_embedding_w_retry.sql`)

If you use your own PostgreSQL server instead of the container, it needs PostgreSQL 18 with the `vector` and `plpython3u` extensions installed, and `MISTRAL_API_KEY` set in the server's environment.

## Reset

To re-create the class databases, run `master_setup.sql` again. To remove the container and its data volume completely:

```bash
cd container
docker compose down -v
```

## License

[CC0 1.0 Universal](LICENSE)
