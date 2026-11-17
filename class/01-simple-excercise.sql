/***************************************************************************************************

Part of the DLH Training Class for AI and Postgres, and is meant for educational purposes to 
demonstrate how to become comfortable with psql and basic SQL commands.

Simple exercise to become comfortable with psql and basic SQL commands.

Copyright 2026: Marc Linster
Last Update: 2026-11-15

***************************************************************************************************/





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
