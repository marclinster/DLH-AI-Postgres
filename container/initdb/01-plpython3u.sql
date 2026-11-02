-- Runs once, when the data directory is first initialized.
-- Install in template1 so every new database gets plpython3u too.
\connect template1
CREATE EXTENSION IF NOT EXISTS plpython3u;

\connect postgres
CREATE EXTENSION IF NOT EXISTS plpython3u;
