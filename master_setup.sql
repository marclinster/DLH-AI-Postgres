/*

Master database setup script. This script will create the following databases:
- simple_fruit_store
- fruit_store
- commerce
- sportscar
- vector_index_demo

It requires Postgres 18, pgvector extension, and plpython3u extension to be installed.

*/

\c postgres
\set ON_ERROR_STOP on

\echo 'Setting up databases...'

\echo 'Setting up simple_fruit_store database...'
DROP DATABASE IF EXISTS simple_fruit_store WITH (FORCE);
CREATE DATABASE simple_fruit_store;
\c simple_fruit_store

\i db-setup/simple_fruit_store_setup.sql

\echo 'Successfully set up simple_fruit_store database.'

\echo 'Setting up fruit_store database...'
DROP DATABASE IF EXISTS fruit_store WITH (FORCE);
CREATE DATABASE fruit_store;
\c fruit_store

\i db-setup/fruit_store_setup.sql

\echo 'Successfully set up fruit_store database.'

\echo 'Setting up commerce database...'
DROP DATABASE IF EXISTS commerce WITH (FORCE);
CREATE DATABASE commerce;
\c commerce

CREATE EXTENSION IF NOT EXISTS plpython3u;
CREATE EXTENSION IF NOT EXISTS vector;

\i db-setup/commerce/category.sql
\i db-setup/commerce/product.sql
\i db-setup/commerce/address.sql
\i db-setup/commerce/address-data.sql
\i db-setup/commerce/customer.sql
\i db-setup/commerce/purchase.sql
\i db-setup/commerce/views.sql


\echo 'Successfully set up commerce database.'

\echo 'Setting up sportscar database...'
DROP DATABASE IF EXISTS sportscar WITH (FORCE);
CREATE DATABASE sportscar;
\c sportscar

\i db-setup/sportscar_setup.sql

\echo 'Successfully set up sportscar database.'

\echo 'Setting up vector_index_demo database...'
DROP DATABASE IF EXISTS vector_index_demo WITH (FORCE);

CREATE DATABASE vector_index_demo;
\c vector_index_demo

\i db-setup/vector-index.sql

\echo 'Successfully set up vector_index_demo database.'


\c postgres
\l

/*
Verify the Mistral API setup:
- MISTRAL_API_KEY is set in the Postgres server's environment and is accepted by Mistral
- mistral-embed works with https://api.mistral.ai/v1/embeddings (and returns 1024 dimensions)
- mistral-large-2512 works with https://api.mistral.ai/v1/chat/completions

The check runs as a PL/Python DO block on the server, the same way the class functions call Mistral,
so it tests the key the database actually sees. It runs in the sportscar database, which has plpython3u.
All checks are run and reported; if any of them fails, the script ends with an error.
*/

\echo 'Checking Mistral API key and models...'
\c sportscar

DO $$
import os, json, ssl, urllib.request, urllib.error, plpy

api_key = os.environ.get('MISTRAL_API_KEY')
if not api_key:
    plpy.error("MISTRAL_API_KEY is not set in the Postgres server environment. "
               "Add it to container/secrets.env and run 'docker compose up -d' again.")

ctx = ssl.create_default_context()

def call_mistral(url, payload):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            return json.load(resp), None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        if e.code == 401:
            return None, f"HTTP 401: the API key was rejected. Body: {body[:300]}"
        return None, f"HTTP {e.code}. Body: {body[:300]}"
    except Exception as e:
        return None, f"Network error: {getattr(e, 'reason', e)}"

failures = []

# 1. Embeddings with mistral-embed (this also proves the API key works)
data, err = call_mistral("https://api.mistral.ai/v1/embeddings",
                         {"model": "mistral-embed", "input": "setup check"})
if err:
    failures.append(f"mistral-embed (/v1/embeddings): {err}")
else:
    dims = len(data["data"][0]["embedding"])
    if dims != 1024:
        failures.append(f"mistral-embed returned {dims} dimensions, expected 1024")
    else:
        plpy.notice("OK: API key accepted; mistral-embed returned a 1024-dimensional embedding")

# 2. Chat completion with mistral-large-2512
data, err = call_mistral("https://api.mistral.ai/v1/chat/completions",
                         {"model": "mistral-large-2512",
                          "messages": [{"role": "user", "content": "Reply with the word OK."}],
                          "max_tokens": 5})
if err:
    failures.append(f"mistral-large-2512 (/v1/chat/completions): {err}")
else:
    content = data["choices"][0]["message"]["content"]
    plpy.notice(f"OK: mistral-large-2512 answered ({data.get('model')}): {str(content)[:50]}")

if failures:
    plpy.error("Mistral API check failed:\n  - " + "\n  - ".join(failures))
$$ LANGUAGE plpython3u;

\echo 'Mistral API check passed.'
\c postgres 