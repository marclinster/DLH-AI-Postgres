/*

This example builds its own table in a separate schema index_demo in the database
vector_index_demo with 50,000 synthetic 1024-dimensional vectors (the same size as mistral-embed), 
so no LLM calls are needed.

This is part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to
demonstrate how to work with vector indexes in Postgres and how to use the HNSW and IVVFlat 
indexes for fast approximate nearest neighbor search.

Last Update: 2026-11-17
*/


CREATE EXTENSION IF NOT EXISTS vector;

DROP SCHEMA IF EXISTS index_demo CASCADE;
CREATE SCHEMA index_demo;

CREATE TABLE index_demo.item (
    id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cluster_id  INTEGER,
    embedding   vector(1024)
);

/*
Real embeddings are not random noise: similar texts form clusters.
We imitate that with 200 random "topic centers" and generate each item as
center + noise.
*/

CREATE TABLE index_demo.center AS
    SELECT c AS cluster_id,
           ARRAY(SELECT random_normal() FROM generate_series(1, 1024) WHERE c > 0)::real[] AS v
    FROM generate_series(1, 200) AS c;   -- "WHERE c > 0" forces a new random array per row

INSERT INTO index_demo.item (cluster_id, embedding)
    SELECT c.cluster_id,
           ARRAY(SELECT c.v[d] + 2 * random_normal() FROM generate_series(1, 1024) AS d)::vector
    FROM generate_series(1, 50000) AS n
    JOIN index_demo.center c ON c.cluster_id = 1 + (n % 200);

-- update the planner statistics
ANALYZE index_demo.item;

-- how big is the table? (each 1024-dim vector is ~4 KB)
SELECT pg_size_pretty(pg_total_relation_size('index_demo.item')) AS table_size;

-- 20 query vectors: each close to one of the clusters, but not identical to any stored row
CREATE TABLE index_demo.query_vector AS
    SELECT q.query_id,
           ARRAY(SELECT c.v[d] + 2 * random_normal() FROM generate_series(1, 1024) AS d)::vector AS q
    FROM generate_series(1, 20) AS q(query_id)
    JOIN index_demo.center c ON c.cluster_id = q.query_id * 7;


CREATE TABLE index_demo.search_result (
    config     TEXT,
    query_id   INTEGER,
    id         INTEGER,
    search_ms  NUMERIC(10,3),
    hnsw_m     INTEGER,
    saved_at   TIMESTAMPTZ DEFAULT clock_timestamp(),
    PRIMARY KEY (config, query_id, id)
);

CREATE PROCEDURE index_demo.save_search(p_config TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    qv       RECORD;
    t_start  TIMESTAMPTZ;
    found    INTEGER[];
    elapsed  NUMERIC;
    v_m      INTEGER;
BEGIN
    DELETE FROM index_demo.search_result WHERE config = p_config;

    -- find the HNSW index on item and read its m from the index options (default 16)
    SELECT COALESCE((SELECT split_part(opt, '=', 2)::INTEGER
                     FROM unnest(c.reloptions) AS opt
                     WHERE opt LIKE 'm=%'),
                    16)
        INTO v_m
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        JOIN pg_am am   ON am.oid = c.relam
        WHERE i.indrelid = 'index_demo.item'::regclass
          AND am.amname = 'hnsw';

    FOR qv IN SELECT query_id, q FROM index_demo.query_vector ORDER BY query_id LOOP
        -- clock_timestamp() is the real time now (now() would stay fixed for the whole call)
        t_start := clock_timestamp();

        found := ARRAY(SELECT id FROM index_demo.item
                       ORDER BY embedding <=> qv.q
                       LIMIT 10);

        elapsed := EXTRACT(EPOCH FROM clock_timestamp() - t_start) * 1000;

        INSERT INTO index_demo.search_result (config, query_id, id, search_ms, hnsw_m)
            SELECT p_config, qv.query_id, f.id, elapsed, v_m
            FROM unnest(found) AS f(id);
    END LOOP;
END;
$$;