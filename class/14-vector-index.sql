/*
The effect of an index on an embedding column

This example builds its own table in a separate schema index_demo in the database
vector_index_demo with 50,000 synthetic 1024-dimensional vectors (the same size as mistral-embed), 
so no LLM calls are needed.

What you will see:
1. Without an index: a similarity search reads and compares every row (Seq Scan)
2. With an HNSW index: the search touches only a small part of the data (Index Scan)
3. The trade-off: HNSW is an *approximate* index - it can miss some of the true nearest neighbors
4. Tuning: hnsw.ef_search trades speed for accuracy
5. The index is only used if the distance operator matches the index's operator class
6. The alternative: an IVFFlat index, tuned with ivfflat.probes, compared to HNSW

Run this in psql with timing turned on:
\timing on

Reference numbers (8 cores, 8 GB): data load ~1 min, HNSW build ~25 s, IVFFlat build ~2-12 s,
search without index ~200-350 ms, with either index ~1-2 ms
*/

--- Setup -------------------------------------------------------------------
DROP DATABASE IF EXISTS vector_index_demo WITH (FORCE);

CREATE DATABASE vector_index_demo;
\c vector_index_demo

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


--- 1. Search WITHOUT an index ---------------------------------------------------

/*
Find the 10 most similar items using cosine distance (<=>), as in our fruit store.
Look for "Seq Scan" in the plan: Postgres computes the distance for all 50,000 rows,
then sorts them to find the top 10.
*/

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, cluster_id, embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1) AS distance
    FROM index_demo.item
    ORDER BY distance
    LIMIT 10;

-- Save the exact top 10 for all 20 query vectors, so we can check the index's answers later.
-- 20 full scans - this takes a few seconds.
CREATE TABLE index_demo.exact_result AS
    SELECT qv.query_id, top10.id
    FROM index_demo.query_vector qv
    CROSS JOIN LATERAL (
        SELECT id FROM index_demo.item
        ORDER BY embedding <=> qv.q
        LIMIT 10) top10;


--- 2. Add an HNSW index -------------------------------------------------------

/*
HNSW (Hierarchical Navigable Small World) builds a graph of the vectors.
A search starts at the top of the graph and greedily walks towards the query,
so it only needs to look at a few hundred vectors instead of all 50,000.

The operator class must match the distance operator used in queries:
    vector_cosine_ops  ->  <=>  (cosine distance)
    vector_l2_ops      ->  <->  (Euclidean distance)
    vector_ip_ops      ->  <#>  (negative inner product)

Building the index needs memory, so we give this session more maintenance_work_mem.
*/

SET maintenance_work_mem = '512MB';

CREATE INDEX item_embedding_hnsw_idx
    ON index_demo.item
    USING hnsw (embedding vector_cosine_ops);

-- the index stores the vectors plus the graph - it is bigger than the table!
SELECT pg_size_pretty(pg_relation_size('index_demo.item_embedding_hnsw_idx')) AS index_size;


--- 3. Search WITH the index ----------------------------------------------------

/*
The same query. Now the plan shows "Index Scan using item_embedding_hnsw_idx",
and both the execution time and the number of buffers drop sharply.
*/

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, cluster_id, embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1) AS distance
    FROM index_demo.item
    ORDER BY distance
    LIMIT 10;


--- 4. The trade-off: approximate results ---------------------------------------

/*
HNSW is an approximate nearest neighbor (ANN) index. It is fast because it does
not look at every row - which means it can miss some of the true top 10.

"Recall" = how many of the exact top 10 the index found, averaged over our 20 queries.
This view compares the index's answers to the saved exact answers.
*/

CREATE VIEW index_demo.recall AS
    SELECT ROUND(AVG(found), 2) AS avg_found_of_10
    FROM (
        SELECT qv.query_id, COUNT(er.id) AS found
        FROM index_demo.query_vector qv
        CROSS JOIN LATERAL (
            SELECT id FROM index_demo.item
            ORDER BY embedding <=> qv.q
            LIMIT 10) top10
        LEFT JOIN index_demo.exact_result er
            ON er.query_id = qv.query_id AND er.id = top10.id
        GROUP BY qv.query_id) per_query;

-- with the default setting (hnsw.ef_search = 40) the index finds most, but not always all, of the top 10
SELECT * FROM index_demo.recall;


--- 5. Tuning: hnsw.ef_search ----------------------------------------------------

/*
hnsw.ef_search (default 40) sets how many candidates the search keeps while walking
the graph. Higher = more accurate, but slower.
Compare the execution time and the recall for each setting.
*/

SET hnsw.ef_search = 10;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

SELECT * FROM index_demo.recall;    -- noticeably worse: roughly 5-7 of 10 (the data is random, so numbers vary per run)

SET hnsw.ef_search = 200;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

SELECT * FROM index_demo.recall;    -- (almost) perfect, but each query does more work

RESET hnsw.ef_search;


--- 6. The operator has to match the index -------------------------------------

/*
Our index was built for cosine distance (vector_cosine_ops).
A query using Euclidean distance (<->) cannot use it, and falls back to a Seq Scan.
*/

EXPLAIN (COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <-> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;


--- 7. The alternative: an IVFFlat index ----------------------------------------

/*
pgvector offers a second index type: IVFFlat (Inverted File with Flat storage).
Instead of a graph, it uses k-means clustering to split the vectors into "lists"
(buckets). Each vector is stored in the list of its closest cluster center.
A search compares the query to the list centers, picks the closest list(s),
and only scans the vectors in those lists.

Differences to HNSW:
- the lists are computed from the data at build time, so build the index
  AFTER the table is loaded (an IVFFlat index built on an empty table is useless)
- rule of thumb for the number of lists: rows / 1000 for up to 1M rows -> 50,000 / 1000 = 50

We drop the HNSW index first, so the planner cannot choose it and we compare
one index type at a time.
Watch the build time: about 10x faster than HNSW (~2 s vs ~25 s).
*/

DROP INDEX index_demo.item_embedding_hnsw_idx;

CREATE INDEX item_embedding_ivfflat_idx
    ON index_demo.item
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 50);

-- about the same size as the HNSW index: with 1024 dimensions, both are mostly copies of the vectors
SELECT pg_size_pretty(pg_relation_size('index_demo.item_embedding_ivfflat_idx')) AS index_size;

/*
The same query. The plan now shows "Index Scan using item_embedding_ivfflat_idx".
*/

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, cluster_id, embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1) AS distance
    FROM index_demo.item
    ORDER BY distance
    LIMIT 10;

/*
The recall view does not care which index is used - it just runs the query.
With ivfflat.probes = 1 (the default) only ONE list is searched - and still the
recall is (almost) perfect. Why?
Our data has 200 natural clusters, but the index has only 50 lists. Each natural
cluster ends up completely inside one list, so the closest list holds all the true neighbors.
*/

SELECT * FROM index_demo.recall;


--- 8. Tuning: lists and ivfflat.probes ------------------------------------------

/*
More lists = smaller lists = fewer rows to scan per probe. But now our natural
clusters are split across several lists, and a true neighbor may sit in a list we don't search.

ivfflat.probes (default 1) sets how many lists are searched.
More probes = better recall, but more rows are compared.
probes = lists searches every list: exact results, but no faster than a Seq Scan.

Let's rebuild the index with 500 lists (about 100 rows per list).
The build takes longer than with 50 lists: k-means has to compute 500 centers.

Tip: a single search now takes only a millisecond or two, too little to compare reliably.
The recall query runs 20 searches - compare its time (\timing) across the probes settings.
*/

DROP INDEX index_demo.item_embedding_ivfflat_idx;

CREATE INDEX item_embedding_ivfflat_idx
    ON index_demo.item
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 500);

-- probes = 1: very fast, but now many neighbors are missed (roughly 6-7 of 10)
SET ivfflat.probes = 1;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

SELECT * FROM index_demo.recall;

-- probes = 3: searches 3 of 500 lists - recall is back to almost 10 of 10
SET ivfflat.probes = 3;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

SELECT * FROM index_demo.recall;

-- probes = 10: perfect recall, but more work per query
SET ivfflat.probes = 10;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

SELECT * FROM index_demo.recall;

RESET ivfflat.probes;

/*
HNSW vs. IVFFlat - summary

                      HNSW                               IVFFlat
Structure             graph of neighbors                 k-means buckets ("lists")
Build time            slow (~25 s here)                  fast (~2 s with 50 lists, ~12 s with 500)
Index size            ~ table size or more               ~ table size or more
Build on empty table  fine - graph grows with inserts    poor - lists come from existing data
Tuning knobs          hnsw.ef_search (default 40)        lists (at build), ivfflat.probes (default 1)
After many changes    keeps working                      lists drift from the data - REINDEX

HNSW is the usual default: good recall with little tuning, and it copes with a growing table.
IVFFlat is attractive when build time matters and the data is mostly static -
but the right lists/probes setting depends on the data, so measure recall.
*/
