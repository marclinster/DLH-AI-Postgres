/*

Master database setup script. This script will create the following databases:
- simple_fruit_store
- fruit_store
- commerce
- sportscar

It requires Postgres 18, pgvector extension, and plpython3u extension to be installed.

*/

\c postgres
\set error_stop on

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

\i db-setup/commerce/category.sql
\i db-setup/commerce/product.sql
\i db-setup/commerce/customer.sql
\i db-setup/commerce/purchase.sql

\echo 'Successfully set up commerce database.'

\echo 'Setting up sportscar database...'
DROP DATABASE IF EXISTS sportscar WITH (FORCE);
CREATE DATABASE sportscar;
\c sportscar

\i db-setup/sportscar_setup.sql

\echo 'Successfully set up sportscar database.'

\c postgres
\l 