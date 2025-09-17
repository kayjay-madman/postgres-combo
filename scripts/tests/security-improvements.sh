#!/bin/bash
# Test suite for all security improvements

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SECURITY_SCRIPT="${PROJECT_ROOT}/scripts/security/scan.sh"

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

test_dockerfile_improvements() {
    info "Testing Dockerfile security improvements..."
    
    # Test HTTPS repository usage
    if grep -q "https://deb.debian.org" "$PROJECT_ROOT/build/Dockerfile"; then
        pass "Dockerfile uses HTTPS for repositories"
    else
        fail "Dockerfile should use HTTPS for repositories"
    fi
    
    # Test WORKDIR usage instead of cd
    if ! grep -q "cd /tmp" "$PROJECT_ROOT/build/Dockerfile"; then
        pass "Dockerfile uses WORKDIR instead of cd commands"
    else
        fail "Dockerfile still uses cd commands"
    fi
    
    # Test integrity verification
    if grep -q "git rev-parse HEAD" "$PROJECT_ROOT/build/Dockerfile"; then
        pass "Dockerfile includes commit hash verification"
    else
        fail "Dockerfile missing commit hash verification"
    fi
    
    # Test security updates
    if grep -q "apt-get upgrade -y" "$PROJECT_ROOT/build/Dockerfile"; then
        pass "Dockerfile includes security updates"
    else
        fail "Dockerfile missing security updates"
    fi
}

test_docker_compose_hardening() {
    info "Testing docker-compose security hardening..."
    
    # Test security_opt
    if grep -q "no-new-privileges:true" "$PROJECT_ROOT/deploy/docker-compose.hardened.yml"; then
        pass "docker-compose includes no-new-privileges"
    else
        fail "docker-compose missing no-new-privileges"
    fi
    
    # Test capability dropping
    if grep -q "cap_drop:" "$PROJECT_ROOT/deploy/docker-compose.hardened.yml"; then
        pass "docker-compose includes capability dropping"
    else
        fail "docker-compose missing capability dropping"
    fi
    
    # Test tmpfs mounts
    if grep -q "tmpfs:" "$PROJECT_ROOT/deploy/docker-compose.hardened.yml"; then
        pass "docker-compose includes tmpfs mounts"
    else
        fail "docker-compose missing tmpfs mounts"
    fi
    
    # Test healthcheck
    if grep -q "healthcheck:" "$PROJECT_ROOT/deploy/docker-compose.yml"; then
        pass "docker-compose includes healthcheck"
    else
        fail "docker-compose missing healthcheck"
    fi
}

test_trivyignore_file() {
    info "Testing .trivyignore configuration..."
    
    if [[ -f "$PROJECT_ROOT/.trivyignore" ]]; then
        pass ".trivyignore file exists"
    else
        fail ".trivyignore file missing"
        return 1
    fi
    
    # Test it contains expected CVEs
    if grep -q "CVE-2023-45853" "$PROJECT_ROOT/.trivyignore"; then
        pass ".trivyignore includes known acceptable risks"
    else
        fail ".trivyignore missing expected CVE entries"
    fi
    
    # Test it has review schedule
    if grep -q "Last reviewed:" "$PROJECT_ROOT/.trivyignore"; then
        pass ".trivyignore includes review schedule"
    else
        fail ".trivyignore missing review schedule"
    fi
}

test_security_scanning_script() {
    info "Testing security scanning script functionality..."
    
    if [[ -x "$SECURITY_SCRIPT" ]]; then
        pass "Security scanning script is executable"
    else
        fail "Security scanning script not executable"
        return 1
    fi
    
    # Test config-only scan
    if "$SECURITY_SCRIPT" --config-only --quiet >/dev/null 2>&1; then
        pass "Security script config scan works"
    else
        fail "Security script config scan failed"
    fi
    
    # Test help option
    if "$SECURITY_SCRIPT" --help >/dev/null 2>&1; then
        pass "Security script help option works"
    else
        fail "Security script help option failed"
    fi
}

test_configuration_validation() {
    info "Testing configuration validation..."
    
    # Test docker-compose config validation
    if docker compose config >/dev/null 2>&1; then
        pass "docker-compose configuration is valid"
    else
        fail "docker-compose configuration is invalid"
    fi
    
    # Test config scan shows no issues
    local config_issues
    config_issues=$("$SECURITY_SCRIPT" --config-only --quiet 2>&1 | grep "Configuration issues found:" | grep -o '[0-9]*' || echo "unknown")
    
    if [[ "$config_issues" == "0" ]]; then
        pass "Configuration scan shows no security issues"
    else
        fail "Configuration scan found $config_issues security issues"
    fi
}

display_summary() {
    echo
    echo "=== Security Improvements Test Summary ==="
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All security improvements working correctly!"
        echo
        echo "Security improvements implemented:"
        echo "• Dockerfile WORKDIR fixes - eliminates AVD-DS-0013"
        echo "• HTTPS for package repositories"
        echo "• Security updates in base image"
        echo "• Commit hash verification for dependencies"
        echo "• docker-compose security hardening"
        echo "• Capability dropping and privilege restrictions"
        echo "• tmpfs mounts for sensitive directories"
        echo "• Comprehensive security scanning scripts"
        echo "• .trivyignore for risk management"
        echo
        echo "Next steps:"
        echo "1. Build new container image with security fixes"
        echo "2. Test container with security hardening"
        echo "3. Deploy to production environment"
        echo "4. Schedule monthly security reviews"
        return 0
    else
        echo "✗ Some security improvements need attention!"
        echo
        echo "Please review failed tests above and fix issues before deploying."
        return 1
    fi
}

main() {
    echo "=== Security Improvements Test Suite ==="
    echo
    
    test_dockerfile_improvements
    test_docker_compose_hardening
    test_trivyignore_file
    test_security_scanning_script
    test_configuration_validation
    
    display_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
