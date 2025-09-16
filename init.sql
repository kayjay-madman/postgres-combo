DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
        CREATE EXTENSION vector;
        RAISE NOTICE 'pgvector extension enabled';
    ELSE
        RAISE NOTICE 'pgvector extension already exists';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'age') THEN
        CREATE EXTENSION age;
        RAISE NOTICE 'Apache AGE extension enabled';
    ELSE
        RAISE NOTICE 'Apache AGE extension already exists';
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Error enabling extensions: %', SQLERRM;
END
$$;

LOAD 'age';
SET search_path = ag_catalog, "$user", public;
GRANT USAGE ON SCHEMA ag_catalog TO PUBLIC;

SELECT 
    extname as "Extension",
    extversion as "Version",
    n.nspname as "Schema"
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE extname IN ('vector', 'age')
ORDER BY extname;