#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/extensions.sh
source "${REPO_ROOT}/scripts/lib/extensions.sh"

cd "$REPO_ROOT"

readonly SERVICE_NAME="${1:-postgres}"
readonly TEST_DB="${POSTGRES_DB:-postgres}"
readonly TEST_USER="${POSTGRES_USER:-postgres}"

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo "✓ $1"
    ((TESTS_PASSED++)) || true
}

fail() {
    echo "✗ $1"
    ((TESTS_FAILED++)) || true
}

info() {
    echo "→ $1"
}

check_dependencies() {
    info "Checking test dependencies..."

    if command -v bc >/dev/null 2>&1; then
        pass "bc available for performance assertions"
    else
        fail "bc command not found; install bc to run performance checks"
        exit 1
    fi
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

    local retries=10
    local delay=3

    for ((i=1; i<=retries; i++)); do
        if docker compose exec -T "$SERVICE_NAME" pg_isready -U "$TEST_USER" -d "$TEST_DB" -q; then
            pass "Database accepting connections"
            return 0
        fi

        sleep "$delay"
    done

    fail "Database not accepting connections"
    return 1
}

test_security() {
    info "Testing container security..."
    
    local user_check
    user_check=$(docker compose exec -T "$SERVICE_NAME" whoami 2>/dev/null || echo "failed")
    
    if [[ "$user_check" == "postgres" ]]; then
        pass "Container running as non-root user (postgres)"
    else
        fail "Container not running as expected user (found: $user_check)"
    fi
    
    local security_opts
    local container_id
    container_id=$(docker compose ps -q "$SERVICE_NAME" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        fail "Unable to locate container for security checks"
        return 1
    fi

    security_opts=$(docker inspect "$container_id" --format='{{.HostConfig.SecurityOpt}}' 2>/dev/null || echo "[]")
    
    if [[ "$security_opts" == *"no-new-privileges:true"* ]]; then
        pass "Security option no-new-privileges enabled"
    else
        fail "Security option no-new-privileges not enabled"
    fi
}

test_extensions() {
    info "Testing extension functionality..."

    if extensions_installed; then
        pass "Both pgvector and Apache AGE extensions installed"
    else
        fail "Extensions not properly installed"
        return 1
    fi

    if vector_basic_check; then
        pass "pgvector operations working"
    else
        fail "pgvector operations failed"
    fi

    if age_has_create_graph; then
        pass "Apache AGE operations working"
    else
        fail "Apache AGE operations failed"
    fi
}

test_graph_operations() {
    info "Testing graph operations..."

    if age_graph_cycle; then
        pass "Graph operations working"
    else
        fail "Graph operations failed"
    fi
}

test_performance() {
    info "Testing performance characteristics..."
    
    local start_time end_time duration
    start_time=$(date +%s.%N)
    
    if ! vector_performance_sample; then
        fail "Vector operations performance run failed"
        return 1
    fi
    
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

    check_dependencies

    test_environment
    test_connectivity

    set_psql_cmd docker compose exec -T "$SERVICE_NAME" psql -U "$TEST_USER" -d "$TEST_DB"

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
