#!/bin/bash
set -eo pipefail

readonly POSTGRES_USER="${POSTGRES_USER:-postgres}"
readonly POSTGRES_DB="${POSTGRES_DB:-postgres}"
readonly TIMEOUT=10

check_connectivity() {
    if timeout "$TIMEOUT" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q; then
        return 0
    else
        echo "Database connectivity failed"
        return 1
    fi
}

check_extensions() {
    local ext_count
    ext_count=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
        SELECT COUNT(*) FROM pg_extension WHERE extname IN ('vector', 'age');
    " 2>/dev/null | tr -d ' ')
    
    if [[ "$ext_count" == "2" ]]; then
        return 0
    else
        echo "Extensions not loaded (found: $ext_count/2)"
        return 1
    fi
}

test_vector_operations() {
    local result
    result=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
        SELECT vector_dims('[1,2,3]'::vector);
    " 2>/dev/null | tr -d ' ')
    
    if [[ "$result" == "3" ]]; then
        return 0
    else
        echo "Vector operations failed"
        return 1
    fi
}

test_age_operations() {
    local age_test
    age_test=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "
        SET search_path = ag_catalog, public;
        SELECT proname FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'ag_catalog') AND proname = 'create_graph' LIMIT 1;
    " 2>/dev/null | grep -v '^SET$' | tr -d ' ' | head -1)

    if [[ "$age_test" == "create_graph" ]]; then
        return 0
    else
        echo "AGE operations failed"
        return 1
    fi
}

main() {
    check_connectivity && \
    check_extensions && \
    test_vector_operations && \
    test_age_operations
}

main "$@"