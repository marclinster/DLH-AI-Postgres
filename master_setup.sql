\c postgres

DROP DATABASE IF EXISTS simple_fruit_store WITH (FORCE);
CREATE DATABASE simple_fruit_store;
\c simple_fruit_store

\i databases/simple_fruit_store_setup.sql


DROP DATABASE IF EXISTS fruit_store WITH (FORCE);
CREATE DATABASE fruit_store;
\c fruit_store

\i databases/fruit_store_setup.sql


DROP DATABASE IF EXISTS ecommerce WITH (FORCE);
CREATE DATABASE ecommerce;
\c ecommerce

\i databases/ecommerce_datamodel.sql
\i databases/ecommerce_dataset.sql

\c postgres