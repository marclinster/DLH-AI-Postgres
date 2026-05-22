/****************************************************************************************************
Sample SQL files for the class 'Creating AI Applications with Postgres'
2026 Copyright: Marc Linster
Last updated April 2026
****************************************************************************************************/

-- simple table creation and data insertion


DROP TABLE IF EXISTS test_table;

CREATE TABLE test_table (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT DEFAULT 'Nothing to see here');

-- inserting examples
INSERT INTO test_table (id, name) VALUES (1, 'Test 1');
INSERT INTO test_table (id, name, description) VALUES (2, 'Test 2', 'This is a test description');
INSERT INTO test_table (id, name, description) VALUES (2, 'Test 2', 'This is a test description');    -- should trigger primary key violation error
INSERT INTO test_table (id, name) VALUES (3, 'Test 3'); -- should work and use default value for description
INSERT INTO test_table (id, name) VALUES (NULL, 'Test 4'); -- should trigger not null violation error
INSERT INTO test_table (id, name) VALUES (4, NULL); -- should trigger not null violation error
INSERT INTO test_table (id, name) VALUES (5, 'Test 5'); -- should work and use default value for description

SELECT * FROM test_table;

-- create an btree index on the name column to speed up queries that filter by name
DROP INDEX IF EXISTS idx_test_table_name;

CREATE INDEX idx_test_table_name ON test_table USING btree(name); 