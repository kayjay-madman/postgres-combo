#!/usr/bin/env bash

# Shared helpers for extension checks used by health checks and host-side tests.
# Callers must invoke set_psql_cmd with the command array used to run psql.

# Internal: holds the command array for executing psql.
declare -a _PSQL_CMD=()

set_psql_cmd() {
    if [[ $# -eq 0 ]]; then
        echo "set_psql_cmd: requires at least one argument" >&2
        return 1
    fi
    _PSQL_CMD=("$@")
}

_psql_check_initialized() {
    if [[ ${#_PSQL_CMD[@]} -eq 0 ]]; then
        echo "psql command not configured. Call set_psql_cmd first." >&2
        return 1
    fi
}

psql_scalar() {
    _psql_check_initialized || return 1
    local query="$1"
    local output
    output=$( (set -o pipefail; "${_PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -X -A -t -c "$query" 2>/dev/null | tr -d '[:space:]') ) || return 1

    if [[ -z "$output" ]]; then
        return 1
    fi

    printf '%s' "$output"
}

extensions_installed() {
    local expected=${1:-2}
    local count
    count=$(psql_scalar "SELECT COUNT(*) FROM pg_extension WHERE extname IN ('vector', 'age');") || return 1
    [[ "$count" == "$expected" ]]
}

vector_basic_check() {
    local dims
    dims=$(psql_scalar "SELECT vector_dims('[1,2,3]'::vector);") || return 1
    [[ "$dims" == "3" ]]
}

age_has_create_graph() {
    local count
    count=$(psql_scalar "SELECT COUNT(*) FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'ag_catalog') AND proname = 'create_graph';") || return 1
    [[ "$count" == "1" ]]
}

age_graph_cycle() {
    _psql_check_initialized || return 1
    "${_PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -X -q -c "SELECT ag_catalog.create_graph('test_graph');" >/dev/null 2>&1 && \
        "${_PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -X -q -c "SELECT ag_catalog.drop_graph('test_graph', true);" >/dev/null 2>&1
}

vector_performance_sample() {
    _psql_check_initialized || return 1
    "${_PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -X -q -c "CREATE TEMP TABLE perf_test (id SERIAL, embedding vector(3)); INSERT INTO perf_test (embedding) SELECT ('[' || random() || ',' || random() || ',' || random() || ']')::vector FROM generate_series(1, 1000); DROP TABLE perf_test;"
}
