CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;

LOAD 'age';
SET search_path = ag_catalog, "$user", public;
GRANT USAGE ON SCHEMA ag_catalog TO PUBLIC;
