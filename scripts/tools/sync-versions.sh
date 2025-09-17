#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${ROOT_DIR}/build/versions.mk"

if [[ ! -f "$MANIFEST" ]]; then
    echo "versions.mk not found" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$MANIFEST"

update_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return
    fi

    perl -0pi -e "s/pgvector \((?:v)?[0-9]+\.[0-9]+\.[0-9]+\)/pgvector (${PGVECTOR_VERSION})/g" "$file"
    perl -0pi -e "s/Apache AGE \((?:v)?[0-9]+\.[0-9]+\.[0-9]+\)/Apache AGE (v${AGE_VERSION})/g" "$file"
}

update_file "${ROOT_DIR}/README.md"
update_file "${ROOT_DIR}/AGENTS.md"
update_file "${ROOT_DIR}/CLAUDE.md"
