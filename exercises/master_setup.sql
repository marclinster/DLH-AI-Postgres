/*
Master setup script for DLH AI Postgres class.
Set the MISTRAL_API_KEY environment variable - this not the way it should be done in production, 
but for the sake of simplicity in this class we will use environment variables to store the API key. 
Make sure to set the MISTRAL_API_KEY environment variable before running this code.


1) Create the fruit database and set up the fruit_vectors table with sample data.


*/

-- set the MISTRAL_API_KEY as 
ALTER SYSTEM SET api.mistral_api_key = 'hgmeK7rpq4sLTHDhPxjkGaFzNqDZVegy';
SELECT pg_reload_conf();




--- make sure psql stops after the first error
\set ON_ERROR_STOP on
SET client_min_messages TO NOTICE;
\c postgres


\echo 'Creating databases and setting up schemas...'

\echo 'Setting up ecommerce database...'
DROP DATABASE IF EXISTS ecommerce WITH (FORCE);
CREATE DATABASE ecommerce;
\c ecommerce
\i ecommerce/datamodel.sql
\i ecommerce/dataset.sql

\echo 'Setting up simple_fruit_store database...'
DROP DATABASE IF EXISTS simple_fruit_store WITH (FORCE);
CREATE DATABASE simple_fruit_store;
\c simple_fruit_store
\i simple_fruit_store_setup.sql

\echo 'Setting up fruit_store database...'
DROP DATABASE IF EXISTS fruit_store WITH (FORCE);
CREATE DATABASE fruit_store;
\c fruit_store
\i fruit_store_setup.sql
\i fruit_store_chat.sql

\echo 'Setting up sportscars database...'
DROP DATABASE IF EXISTS sportscars WITH (FORCE);
CREATE DATABASE sportscars;
\c sportscars
\i sportscar_setup.sql
