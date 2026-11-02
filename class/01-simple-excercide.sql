/* 

Simple excercide to become comfortable with psql and basic SQL commands.

*/




# Do this in psql
# Connect to psql


\c postgres

CREATE DATABASE testdb;
\c testdb;

CREATE TABLE test (
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT 'Nothing to see here'
);

INSERT INTO test (name) 
    VALUES ('Test 1');

INSERT INTO test (name, description)     
    VALUES
        ('Test 2', 'This is another test description'),
        ('Test 3', 'This is yet another test description');

SELECT * FROM test;

# in psql, you can use \d, \d<table name>, and \d+ <table name> to describe the table structure
