#!/bin/bash
# Security scanning script for postgres-combo project

set -euo pipefail

readonly SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly OUTPUT_DIR="${PROJECT_ROOT}/security-reports"
readonly VERSIONS_FILE="${PROJECT_ROOT}/build/versions.mk"

IMAGE_REFERENCE="${IMAGE_REFERENCE:-}"

# Script options
SCAN_CONFIG=true
SCAN_IMAGE=true
SCAN_SECRETS=true
GENERATE_SBOM=false
QUIET=false
HELP=false

usage() {
    cat << EOF
Security Scanning Script for postgres-combo

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --config-only       Only scan configuration files
    --image-only        Only scan container image
    --secrets-only      Only scan for secrets
    --with-sbom         Generate SBOM (Software Bill of Materials)
    --image IMAGE       Override the container image reference to scan
    --quiet             Reduce output verbosity
    --help              Show this help message

EXAMPLES:
    $(basename "$0")                    # Full security scan
    $(basename "$0") --config-only      # Scan only config files
    $(basename "$0") --with-sbom        # Include SBOM generation
    $(basename "$0") --quiet            # Silent mode

REQUIREMENTS:
    - trivy (container security scanner)
    - docker (for image scanning)

OUTPUT:
    Reports are saved to: $OUTPUT_DIR
EOF
}

log() {
    if [[ "$QUIET" != "true" ]]; then
        echo "→ $1"
    fi
}

error() {
    echo "✗ Error: $1" >&2
}

success() {
    if [[ "$QUIET" != "true" ]]; then
        echo "✓ $1"
    fi
}

check_dependencies() {
    local missing_deps=()
    
    if ! command -v trivy >/dev/null 2>&1; then
        missing_deps+=("trivy")
    fi

    if [[ "$SCAN_IMAGE" == "true" ]] && ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo "Install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                "trivy")
                    echo "  brew install trivy"
                    ;;
                "docker")
                    echo "  brew install docker"
                    ;;
                "jq")
                    echo "  brew install jq"
                    ;;
            esac
        done
        return 1
    fi
}

load_default_image_reference() {
    if [[ -n "$IMAGE_REFERENCE" ]]; then
        return
    fi

    local manifest_image=""

    if [[ -f "$VERSIONS_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$VERSIONS_FILE"
        if [[ -n "${IMAGE_NAME:-}" ]]; then
            manifest_image="${IMAGE_NAME}:${IMAGE_TAG:-latest}"
        fi
    fi

    if [[ -z "$manifest_image" ]]; then
        manifest_image="ghcr.io/kayjay-madman/postgres-combo:latest"
    fi

    IMAGE_REFERENCE="$manifest_image"
}

setup_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    echo "$timestamp" > "$OUTPUT_DIR/.last_scan"
}

scan_configuration() {
    log "Scanning configuration files for security issues..."
    
    local config_report="$OUTPUT_DIR/config-scan.json"
    local config_sarif="$OUTPUT_DIR/config-scan.sarif"
    
    # Scan with JSON output for programmatic processing
    if trivy config "$PROJECT_ROOT" \
        --format json \
        --output "$config_report" \
        --severity CRITICAL,HIGH,MEDIUM 2>/dev/null; then
        success "Configuration scan completed"
    else
        error "Configuration scan failed"
        return 1
    fi
    
    # Also generate SARIF for GitHub integration
    if trivy config "$PROJECT_ROOT" \
        --format sarif \
        --output "$config_sarif" \
        --severity CRITICAL,HIGH,MEDIUM 2>/dev/null; then
        success "SARIF report generated for GitHub integration"
    fi
    
    # Display summary if not quiet
    if [[ "$QUIET" != "true" ]]; then
        local issues_count
        issues_count=$(jq -r '.Results[].Misconfigurations | length' "$config_report" 2>/dev/null | awk '{sum += $1} END {print sum+0}')
        echo "Configuration issues found: $issues_count"
    fi
}

scan_container_image() {
    if [[ -z "$IMAGE_REFERENCE" ]]; then
        error "No image reference provided for scanning"
        return 1
    fi

    log "Scanning container image for vulnerabilities (target: $IMAGE_REFERENCE)..."

    local image_report="$OUTPUT_DIR/image-scan.json"
    local image_table="$OUTPUT_DIR/image-scan.txt"

    # Check if image exists locally or pull it
    if ! docker image inspect "$IMAGE_REFERENCE" >/dev/null 2>&1; then
        log "Pulling image $IMAGE_REFERENCE..."
        if ! docker pull "$IMAGE_REFERENCE" >/dev/null 2>&1; then
            error "Failed to pull image $IMAGE_REFERENCE"
            return 1
        fi
    fi

    # Scan with JSON output
    if trivy image "$IMAGE_REFERENCE" \
        --format json \
        --output "$image_report" \
        --severity CRITICAL,HIGH 2>/dev/null; then
        success "Image vulnerability scan completed"
    else
        error "Image vulnerability scan failed"
        return 1
    fi

    # Generate human-readable table
    if trivy image "$IMAGE_REFERENCE" \
        --format table \
        --output "$image_table" \
        --severity CRITICAL,HIGH 2>/dev/null; then
        success "Human-readable vulnerability report generated"
    fi
    
    # Display summary if not quiet
    if [[ "$QUIET" != "true" ]]; then
        local vuln_count
        vuln_count=$(jq -r '.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL" or .Severity == "HIGH") | .VulnerabilityID' "$image_report" 2>/dev/null | wc -l)
        echo "Critical/High vulnerabilities found: $vuln_count"
    fi
}

scan_secrets() {
    log "Scanning for exposed secrets..."
    
    local secrets_report="$OUTPUT_DIR/secrets-scan.json"
    
    if trivy fs "$PROJECT_ROOT" \
        --scanners secret \
        --format json \
        --output "$secrets_report" 2>/dev/null; then
        success "Secret scanning completed"
    else
        error "Secret scanning failed"
        return 1
    fi
    
    # Display summary if not quiet
    if [[ "$QUIET" != "true" ]]; then
        local secrets_count
        secrets_count=$(jq -r '.Results[]?.Secrets[]? | .Title' "$secrets_report" 2>/dev/null | wc -l)
        echo "Secrets found: $secrets_count"
    fi
}

generate_sbom() {
    log "Generating Software Bill of Materials (SBOM)..."
    
    local sbom_file="$OUTPUT_DIR/sbom.spdx.json"
    
    if trivy image "$IMAGE_REFERENCE" \
        --format spdx-json \
        --output "$sbom_file" 2>/dev/null; then
        success "SBOM generated: $(basename "$sbom_file")"
    else
        error "SBOM generation failed"
        return 1
    fi
}

display_summary() {
    if [[ "$QUIET" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "=== Security Scan Summary ==="
    echo "Scan completed at: $(date)"
    echo "Reports location: $OUTPUT_DIR"
    if [[ "$SCAN_IMAGE" == "true" ]]; then
        echo "Image scanned: ${IMAGE_REFERENCE:-N/A}"
    fi
    echo
    
    if [[ -f "$OUTPUT_DIR/config-scan.json" ]]; then
        echo "Configuration scan: ✓"
    fi
    
    if [[ -f "$OUTPUT_DIR/image-scan.json" ]]; then
        echo "Image vulnerability scan: ✓"
    fi
    
    if [[ -f "$OUTPUT_DIR/secrets-scan.json" ]]; then
        echo "Secret scan: ✓"
    fi
    
    if [[ -f "$OUTPUT_DIR/sbom.spdx.json" ]]; then
        echo "SBOM generation: ✓"
    fi
    
    echo
    echo "Next steps:"
    echo "1. Review reports in $OUTPUT_DIR"
    echo "2. Address critical and high-severity issues"
    echo "3. Upload SARIF files to GitHub Security tab"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config-only)
                SCAN_CONFIG=true
                SCAN_IMAGE=false
                SCAN_SECRETS=false
                shift
                ;;
            --image-only)
                SCAN_CONFIG=false
                SCAN_IMAGE=true
                SCAN_SECRETS=false
                shift
                ;;
            --secrets-only)
                SCAN_CONFIG=false
                SCAN_IMAGE=false
                SCAN_SECRETS=true
                shift
                ;;
            --with-sbom)
                GENERATE_SBOM=true
                shift
                ;;
            --image)
                if [[ -z "${2:-}" ]]; then
                    error "--image requires a value"
                    exit 1
                fi
                IMAGE_REFERENCE="$2"
                shift 2
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --help)
                HELP=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    if [[ "$HELP" == "true" ]]; then
        usage
        exit 0
    fi

    load_default_image_reference

    if [[ "$QUIET" != "true" ]]; then
        echo "=== Security Scanning for postgres-combo ==="
        echo
    fi
    
    # Check dependencies
    check_dependencies || exit 1
    
    # Setup output directory
    setup_output_dir
    
    # Run selected scans
    local scan_failed=false
    
    if [[ "$SCAN_CONFIG" == "true" ]]; then
        scan_configuration || scan_failed=true
    fi
    
    if [[ "$SCAN_IMAGE" == "true" ]]; then
        scan_container_image || scan_failed=true
    fi
    
    if [[ "$SCAN_SECRETS" == "true" ]]; then
        scan_secrets || scan_failed=true
    fi
    
    if [[ "$GENERATE_SBOM" == "true" ]]; then
        generate_sbom || scan_failed=true
    fi
    
    # Display summary
    display_summary
    
    if [[ "$scan_failed" == "true" ]]; then
        error "Some security scans failed"
        exit 1
    else
        success "All security scans completed successfully"
        exit 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
