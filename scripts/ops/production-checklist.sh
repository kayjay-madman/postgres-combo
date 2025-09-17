#!/bin/bash
# Production readiness checklist for postgres-combo

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly DOCKERFILE_PATH="${PROJECT_ROOT}/build/Dockerfile"
readonly COMPOSE_BASE="${PROJECT_ROOT}/deploy/docker-compose.yml"
readonly COMPOSE_HARDENED="${PROJECT_ROOT}/deploy/docker-compose.hardened.yml"
readonly HEALTHCHECK_SCRIPT="${PROJECT_ROOT}/config/healthcheck.sh"
readonly SECURITY_SCAN_SCRIPT="${PROJECT_ROOT}/scripts/security/scan.sh"

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

pass() {
    echo "✓ $1"
    ((CHECKS_PASSED++)) || true
}

fail() {
    echo "✗ $1"
    ((CHECKS_FAILED++)) || true
}

warn() {
    echo "⚠ $1"
    ((CHECKS_WARNING++)) || true
}

info() {
    echo "→ $1"
}

check_environment_configuration() {
    info "Checking environment configuration..."
    
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        pass "Environment file (.env) exists"
        
        # Check for required variables
        if grep -q "^POSTGRES_PASSWORD=" "$PROJECT_ROOT/.env" && \
           ! grep -q "^POSTGRES_PASSWORD=your_secure_password_here" "$PROJECT_ROOT/.env"; then
            pass "Custom PostgreSQL password is set"
        else
            fail "PostgreSQL password not configured or using default example"
        fi
        
        # Check password strength
        local password
        password=$(grep "^POSTGRES_PASSWORD=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- || echo "")
        if [[ ${#password} -ge 16 ]]; then
            pass "PostgreSQL password meets minimum length (16+ chars)"
        else
            warn "PostgreSQL password should be at least 16 characters long"
        fi
    else
        fail "Environment file (.env) missing - copy from .env.example"
    fi
}

check_security_hardening() {
    info "Checking security hardening..."
    
    # Check docker-compose security settings
    if grep -q "no-new-privileges:true" "$COMPOSE_HARDENED"; then
        pass "Container privilege escalation disabled"
    else
        fail "Container security hardening missing"
    fi

    if grep -q "cap_drop:" "$COMPOSE_HARDENED"; then
        pass "Container capabilities properly restricted"
    else
        fail "Container capabilities not restricted"
    fi

    # Check Dockerfile security
    if grep -q "https://deb.debian.org" "$DOCKERFILE_PATH"; then
        pass "HTTPS repositories configured in Dockerfile"
    else
        warn "Dockerfile should use HTTPS for package repositories"
    fi

    if grep -q "USER postgres" "$DOCKERFILE_PATH"; then
        pass "Container runs as non-root user"
    else
        fail "Container should run as non-root user"
    fi
}

check_networking() {
    info "Checking networking configuration..."
    
    # Check if PostgreSQL is exposed on default port
    if grep -q "5432:5432" "$COMPOSE_BASE"; then
        warn "PostgreSQL exposed on default port 5432 - consider changing for production"
    else
        pass "PostgreSQL port configured securely"
    fi

    # Check for bind to localhost
    if grep -q "127.0.0.1" "$COMPOSE_BASE"; then
        pass "PostgreSQL bound to localhost only"
    else
        warn "Consider binding PostgreSQL to specific interface instead of 0.0.0.0"
    fi
}

check_resource_limits() {
    info "Checking resource configuration..."
    
    # Check shared memory
    if grep -q "shm_size:" "$COMPOSE_HARDENED"; then
        pass "Shared memory configured for optimal PostgreSQL performance"
    else
        warn "Consider configuring shm_size for better PostgreSQL performance"
    fi
    
    # Check restart policy
    if grep -q "restart: unless-stopped" "$COMPOSE_BASE"; then
        pass "Container restart policy configured"
    else
        warn "Consider adding restart policy for production resilience"
    fi
}

check_health_monitoring() {
    info "Checking health monitoring..."
    
    if grep -q "healthcheck:" "$COMPOSE_BASE"; then
        pass "Container health checks configured"
    else
        fail "Health checks not configured"
    fi

    if [[ -f "$HEALTHCHECK_SCRIPT" ]]; then
        pass "Health check script exists"

        if [[ -x "$HEALTHCHECK_SCRIPT" ]]; then
            pass "Health check script is executable"
        else
            fail "Health check script is not executable"
        fi
    else
        fail "Health check script missing"
    fi
}

check_backup_strategy() {
    info "Checking backup configuration..."
    
    if grep -q "volumes:" "$COMPOSE_BASE"; then
        pass "Data persistence configured with volumes"
    else
        fail "Data volumes not configured - data will be lost on container restart"
    fi
    
    warn "Backup strategy not detected - implement regular PostgreSQL backups"
    info "Consider: pg_dump, WAL-E, or pgBackRest for production backups"
}

check_logging() {
    info "Checking logging configuration..."
    
    warn "Centralized logging not detected"
    info "Consider: Configure log aggregation (ELK stack, Grafana, etc.)"
    info "PostgreSQL log settings can be tuned in postgresql.conf"
}

check_ssl_configuration() {
    info "Checking SSL/TLS configuration..."
    
    warn "SSL configuration not detected"
    info "For production: Configure PostgreSQL SSL certificates"
    info "Add SSL volume mounts and enable ssl = on in postgresql.conf"
}

check_monitoring() {
    info "Checking monitoring setup..."
    
    warn "Monitoring stack not detected"
    info "Consider: Prometheus + Grafana, pg_stat_statements, pgAdmin"
    info "Add monitoring for connections, query performance, and resource usage"
}

run_security_scan() {
    info "Running security scan..."
    
    if [[ -f "$SECURITY_SCAN_SCRIPT" && -x "$SECURITY_SCAN_SCRIPT" ]]; then
        if "$SECURITY_SCAN_SCRIPT" --config-only --quiet >/dev/null 2>&1; then
            pass "Security scan passed"
        else
            fail "Security scan detected issues - run scripts/security-scan.sh for details"
        fi
    else
        warn "Security scanning script not available"
    fi
}

display_summary() {
    echo
    echo "=== Production Readiness Summary ==="
    echo "Checks passed: $CHECKS_PASSED"
    echo "Checks failed: $CHECKS_FAILED"
    echo "Warnings: $CHECKS_WARNING"
    echo
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        if [[ $CHECKS_WARNING -eq 0 ]]; then
            echo "✓ Excellent! All production readiness checks passed!"
        else
            echo "✓ Good! Core requirements met, but consider addressing warnings for optimal production deployment."
        fi
        echo
        echo "Final production deployment steps:"
        echo "1. Review and configure monitoring/alerting"
        echo "2. Set up automated backups"
        echo "3. Configure SSL certificates if needed"
        echo "4. Test disaster recovery procedures"
        echo "5. Document operational procedures"
        return 0
    else
        echo "✗ Production readiness issues detected!"
        echo
        echo "Please address failed checks before deploying to production."
        echo "Critical issues can lead to security vulnerabilities or data loss."
        return 1
    fi
}

main() {
    echo "=== PostgreSQL Combo Production Readiness Checklist ==="
    echo
    
    check_environment_configuration
    check_security_hardening
    check_networking
    check_resource_limits
    check_health_monitoring
    check_backup_strategy
    check_logging
    check_ssl_configuration
    check_monitoring
    run_security_scan
    
    display_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
