/*
The effect of an index on an embedding column
This example uses the database vector-index-demo, which is created by db-setup/vector-index.sql. It shows how
- a similarity search without an index reads every row (Seq Scan)
- an HNSW index (Hierarchical Navigable Small World) speeds up the search (Index Scan)
- the trade-off: HNSW is approximate, so it can miss some of the true nearest neighbors
- tuning: hnsw.ef_search trades speed for accuracy

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

/*
We will run the same 20 searches under different index configurations and keep
every answer in one table, labeled with the configuration that produced it.
The procedure save_search runs the top-10 search for each of the 20 query vectors,
measures how long each search takes, and stores the found items under the given label.
Running it again with the same label replaces the earlier answers.

search_ms is the time of one search (one query vector). All 10 items found by that
search carry the same value.

hnsw_m is the "max connections" setting (m) of the HNSW index that was in place
during the search: how many neighbors each vector may link to per graph layer.
It is set when the index is built. NULL means there was no HNSW index.
*/



-- Save the exact top 10 for all 20 query vectors: this is the reference for every index.
-- 20 full scans - this takes a few seconds.
CALL index_demo.save_search('no index');

SELECT * FROM index_demo.search_result WHERE query_id = 1;


--- 2. Add an HNSW index -------------------------------------------------------

/*
HNSW (Hierarchical Navigable Small World) builds a graph of the vectors.
A search starts at the top of the graph and greedily walks towards the query,
so it only needs to look at a few hundred vectors instead of all 50,000.

The operator class must match the distance operator used in queries:
    vector_cosine_ops  ->  <=>  (cosine distance)
    vector_l2_ops      ->  <->  (Euclidean distance)
    vector_ip_ops      ->  <#>  (negative inner product)

Two build settings shape the graph (we spell out the defaults):
    m                max connections: how many neighbors each vector links to per layer
    ef_construction  how many candidates are considered when choosing those neighbors

Building the index needs memory, so we give this session more maintenance_work_mem.
*/

SET maintenance_work_mem = '512MB';

CREATE INDEX item_embedding_hnsw_idx
    ON index_demo.item
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

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
We save the index's answers next to the exact answers, then compare them.
*/

-- the same 20 searches, now answered by the HNSW index (default hnsw.ef_search = 40)
CALL index_demo.save_search('hnsw, ef_search = 40');

/*
Compare every saved configuration with the exact answers ('no index'):
for each item an index returned, look for the same item in the 'no index' answers
of the same query. COUNT(e.id) counts only the items that were found there.
'no index' itself always scores 10 - it is the reference.
avg_search_ms is the average time of one search, so you can weigh accuracy against speed.
*/

SELECT r.config,
       MAX(r.hnsw_m) AS hnsw_m,
       ROUND(COUNT(e.id)::numeric / COUNT(DISTINCT r.query_id), 2) AS avg_found_of_10,
       ROUND(AVG(r.search_ms), 2) AS avg_search_ms
    FROM index_demo.search_result r
    LEFT JOIN index_demo.search_result e
        ON e.config = 'no index' AND e.query_id = r.query_id AND e.id = r.id
    GROUP BY r.config
    ORDER BY MIN(r.saved_at);

-- with the default setting the index finds most, but not always all, of the top 10


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

CALL index_demo.save_search('hnsw, ef_search = 10');

SET hnsw.ef_search = 200;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

CALL index_demo.save_search('hnsw, ef_search = 200');

RESET hnsw.ef_search;

-- ef_search = 10: noticeably worse, roughly 5-7 of 10 (the data is random, so numbers vary per run)
-- ef_search = 200: (almost) perfect, but each query does more work
SELECT r.config,
       MAX(r.hnsw_m) AS hnsw_m,
       ROUND(COUNT(e.id)::numeric / COUNT(DISTINCT r.query_id), 2) AS avg_found_of_10,
       ROUND(AVG(r.search_ms), 2) AS avg_search_ms
    FROM index_demo.search_result r
    LEFT JOIN index_demo.search_result e
        ON e.config = 'no index' AND e.query_id = r.query_id AND e.id = r.id
    GROUP BY r.config
    ORDER BY MIN(r.saved_at);


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
save_search does not care which index is used - it just runs the query.
With ivfflat.probes = 1 (the default) only ONE list is searched - and still the
recall is (almost) perfect. Why?
Our data has 200 natural clusters, but the index has only 50 lists. Each natural
cluster ends up completely inside one list, so the closest list holds all the true neighbors.
*/

CALL index_demo.save_search('ivfflat, lists = 50, probes = 1');

SELECT r.config,
       MAX(r.hnsw_m) AS hnsw_m,
       ROUND(COUNT(e.id)::numeric / COUNT(DISTINCT r.query_id), 2) AS avg_found_of_10,
       ROUND(AVG(r.search_ms), 2) AS avg_search_ms
    FROM index_demo.search_result r
    LEFT JOIN index_demo.search_result e
        ON e.config = 'no index' AND e.query_id = r.query_id AND e.id = r.id
    GROUP BY r.config
    ORDER BY MIN(r.saved_at);


--- 8. Tuning: lists and ivfflat.probes ------------------------------------------

/*
More lists = smaller lists = fewer rows to scan per probe. But now our natural
clusters are split across several lists, and a true neighbor may sit in a list we don't search.

ivfflat.probes (default 1) sets how many lists are searched.
More probes = better recall, but more rows are compared.
probes = lists searches every list: exact results, but no faster than a Seq Scan.

Let's rebuild the index with 500 lists (about 100 rows per list).
The build takes longer than with 50 lists: k-means has to compute 500 centers.

Tip: a single search now takes only a millisecond or two, so one EXPLAIN ANALYZE is too
noisy to compare. avg_search_ms averages 20 searches - compare it across the probes settings.
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

CALL index_demo.save_search('ivfflat, lists = 500, probes = 1');

-- probes = 3: searches 3 of 500 lists - recall is back to almost 10 of 10
SET ivfflat.probes = 3;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

CALL index_demo.save_search('ivfflat, lists = 500, probes = 3');

-- probes = 10: perfect recall, but more work per query
SET ivfflat.probes = 10;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT id FROM index_demo.item
    ORDER BY embedding <=> (SELECT q FROM index_demo.query_vector WHERE query_id = 1)
    LIMIT 10;

CALL index_demo.save_search('ivfflat, lists = 500, probes = 10');

RESET ivfflat.probes;

-- all configurations side by side
SELECT r.config,
       MAX(r.hnsw_m) AS hnsw_m,
       ROUND(COUNT(e.id)::numeric / COUNT(DISTINCT r.query_id), 2) AS avg_found_of_10,
       ROUND(AVG(r.search_ms), 2) AS avg_search_ms
    FROM index_demo.search_result r
    LEFT JOIN index_demo.search_result e
        ON e.config = 'no index' AND e.query_id = r.query_id AND e.id = r.id
    GROUP BY r.config
    ORDER BY MIN(r.saved_at);

-- which exact neighbors did each configuration miss for query 1?
SELECT r.config, e.id AS missed_id
    FROM index_demo.search_result e
    CROSS JOIN (SELECT DISTINCT config FROM index_demo.search_result) r
    WHERE e.config = 'no index' AND e.query_id = 1
      AND NOT EXISTS (SELECT 1 FROM index_demo.search_result x
                      WHERE x.config = r.config AND x.query_id = 1 AND x.id = e.id)
    ORDER BY r.config, e.id;


