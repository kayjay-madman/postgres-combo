#!/bin/bash
set -euo pipefail

readonly POSTGRES_USER="${POSTGRES_USER:-postgres}"
readonly POSTGRES_DB="${POSTGRES_DB:-postgres}"
readonly TIMEOUT=10

LIB_FALLBACK="/usr/local/bin/extensions-lib.sh"
REPO_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/extensions.sh"

if [[ -f "$REPO_LIB" ]]; then
    # Running from source checkout
    # shellcheck source=/dev/null
    source "$REPO_LIB"
else
    # Running inside container where library is installed beside this script
    # shellcheck source=/dev/null
    source "$LIB_FALLBACK"
fi

check_connectivity() {
    if timeout "$TIMEOUT" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q; then
        return 0
    fi

    echo "Database connectivity failed"
    return 1
}

main() {
    set_psql_cmd psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

    check_connectivity || return 1

    extensions_installed || {
        echo "Extensions not loaded"
        return 1
    }

    vector_basic_check || {
        echo "Vector operations failed"
        return 1
    }

    age_has_create_graph || {
        echo "AGE operations failed"
        return 1
    }
}

main "$@"
