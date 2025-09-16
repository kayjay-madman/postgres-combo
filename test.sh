#!/bin/bash
set -euo pipefail

readonly CONTAINER_NAME="${1:-postgres-combo}"
readonly TEST_DB="${POSTGRES_DB:-postgres}"
readonly TEST_USER="${POSTGRES_USER:-postgres}"

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "✓ $1"
    ((TESTS_PASSED++))
}

fail() {
    echo "✗ $1"
    ((TESTS_FAILED++))
}

info() {
    echo "→ $1"
}

test_environment() {
    info "Testing environment configuration..."
    
    if [[ -f ".env" ]]; then
        pass "Environment file exists"
    else
        fail "Environment file missing (copy .env.example to .env)"
        return 1
    fi
    
    if docker compose config >/dev/null 2>&1; then
        pass "Docker compose configuration valid"
    else
        fail "Docker compose configuration invalid"
        return 1
    fi
}

test_connectivity() {
    info "Testing database connectivity..."
    
    if docker compose exec "$CONTAINER_NAME" pg_isready -U "$TEST_USER" -d "$TEST_DB" -q; then
        pass "Database accepting connections"
    else
        fail "Database not accepting connections"
        return 1
    fi
}

test_security() {
    info "Testing container security..."
    
    local user_check
    user_check=$(docker compose exec "$CONTAINER_NAME" whoami 2>/dev/null || echo "failed")
    
    if [[ "$user_check" == "postgres" ]]; then
        pass "Container running as non-root user (postgres)"
    else
        fail "Container not running as expected user (found: $user_check)"
    fi
    
    local security_opts
    security_opts=$(docker inspect "$CONTAINER_NAME" --format='{{.HostConfig.SecurityOpt}}' 2>/dev/null || echo "[]")
    
    if [[ "$security_opts" == *"no-new-privileges:true"* ]]; then
        pass "Security option no-new-privileges enabled"
    else
        fail "Security option no-new-privileges not enabled"
    fi
}

test_extensions() {
    info "Testing extension functionality..."
    
    local ext_count
    ext_count=$(docker compose exec "$CONTAINER_NAME" psql -U "$TEST_USER" -d "$TEST_DB" -t -c "SELECT COUNT(*) FROM pg_extension WHERE extname IN ('vector', 'age');" 2>/dev/null | tr -d ' ')
    
    if [[ "$ext_count" == "2" ]]; then
        pass "Both pgvector and Apache AGE extensions installed"
    else
        fail "Extensions not properly installed (found: $ext_count/2)"
        return 1
    fi
    
    local vector_test
    vector_test=$(docker compose exec "$CONTAINER_NAME" psql -U "$TEST_USER" -d "$TEST_DB" -t -c "SELECT vector_dims('[1,2,3]'::vector);" 2>/dev/null | tr -d ' ')
    
    if [[ "$vector_test" == "3" ]]; then
        pass "pgvector operations working"
    else
        fail "pgvector operations failed"
    fi
    
    local age_test
    age_test=$(docker compose exec "$CONTAINER_NAME" psql -U "$TEST_USER" -d "$TEST_DB" -t -c "SET search_path = ag_catalog, public; SELECT proname FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'ag_catalog') AND proname = 'create_graph' LIMIT 1;" 2>/dev/null | grep -v '^SET$' | tr -d ' ' | head -1)

    if [[ "$age_test" == "create_graph" ]]; then
        pass "Apache AGE operations working"
    else
        fail "Apache AGE operations failed"
    fi
}

test_graph_operations() {
    info "Testing graph operations..."
    
    if docker compose exec "$CONTAINER_NAME" psql -U "$TEST_USER" -d "$TEST_DB" -c "SET search_path = ag_catalog, public; SELECT create_graph('test_graph'); SELECT drop_graph('test_graph', true);" >/dev/null 2>&1; then
        pass "Graph operations working"
    else
        fail "Graph operations failed"
    fi
}

test_performance() {
    info "Testing performance characteristics..."
    
    local start_time end_time duration
    start_time=$(date +%s.%N)
    
    docker compose exec "$CONTAINER_NAME" psql -U "$TEST_USER" -d "$TEST_DB" -c "CREATE TEMPORARY TABLE perf_test (id SERIAL, embedding vector(3)); INSERT INTO perf_test (embedding) SELECT ('[' || random() || ',' || random() || ',' || random() || ']')::vector FROM generate_series(1, 1000); DROP TABLE perf_test;" >/dev/null 2>&1
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l)
    
    if (( $(echo "$duration < 5.0" | bc -l) )); then
        pass "Vector operations performance acceptable (${duration}s)"
    else
        fail "Vector operations performance poor (${duration}s > 5.0s)"
    fi
}

main() {
    echo "=== PostgreSQL Combo Test Suite ==="
    echo
    
    test_environment
    test_connectivity
    test_security
    test_extensions
    test_graph_operations
    test_performance
    
    echo
    echo "=== Test Results ==="
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All tests passed!"
        exit 0
    else
        echo "✗ Some tests failed!"
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi