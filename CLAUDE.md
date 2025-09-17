# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PostgreSQL Combo is a containerized PostgreSQL 16 distribution bundling pgvector (v0.8.1) and Apache AGE (v1.6.0) extensions for vector search, graph analytics, and relational workloads. Images are published to GitHub Container Registry under `ghcr.io/kayjay-madman/postgres-combo`.

## Essential Commands

### Setup and Development
- `cp .env.example .env` - Create environment file (edit POSTGRES_PASSWORD)
- `make build` - Build Docker image with pinned extension versions  
- `make up` - Start services with base configuration
- `make up-secure` - Start with hardened security settings (recommended for testing)
- `make down` - Stop services
- `make clean` - Stop services and remove volumes

### Testing and Validation
- `make test` - Complete test suite (connectivity, extensions, security, performance)
- `make scan` - Run Trivy security scan
- `make logs` - Follow PostgreSQL container logs

### Database Connection
- From host: `psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres}`
- From container: `docker compose exec postgres-combo psql -U postgres -d postgres`

### Maintenance
- `make sync-versions` - Update documentation from build/versions.mk
- `make print-versions` - Show current extension versions

## Architecture

### Key Directories
- `build/` - Dockerfile and version manifest (versions.mk contains all pinned versions)
- `config/` - Database bootstrap SQL and healthcheck script
- `deploy/` - Docker Compose files (base + hardened overlay for production)
- `scripts/lib/` - Shared shell functions for extensions testing
- `scripts/tools/` - Development utilities (version sync, etc.)
- `scripts/security/` - Security scanning tools
- `tests/` - Comprehensive test suite

### Version Management
All extension versions are pinned in `build/versions.mk` with exact commit hashes for reproducible builds. The build system exports these variables for use in Docker build args and documentation.

### Security Model
- Non-root container execution (postgres user)
- Hardened compose overlay in `deploy/docker-compose.hardened.yml`
- Security scanning with Trivy
- Comprehensive healthcheck script

## Development Workflow

### When Completing Tasks
1. Run `make test` - Full test suite including security and performance checks
2. Run `make scan` - Security vulnerability scan
3. If versions changed, run `make sync-versions` to update docs
4. Verify build with `make build`

### Testing Strategy
The test suite (`tests/test.sh`) validates:
- Environment configuration
- Database connectivity  
- Container security (non-root user, security options)
- Extension functionality (pgvector and Apache AGE operations)
- Graph operations and performance benchmarks

### Compose File Management
Use `COMPOSE_FILE` environment variable for overlay composition:
- Base: `deploy/docker-compose.yml`
- Secure: `deploy/docker-compose.yml:deploy/docker-compose.hardened.yml`

## Code Conventions

### Shell Scripts
- Use `#!/bin/bash` and `set -euo pipefail`
- Functions use snake_case naming
- Constants declared with `readonly`
- Comprehensive error handling with meaningful messages

### Make Configuration
- Version variables exported from `build/versions.mk`
- Parameterized targets with sensible defaults
- `.PHONY` declarations for all non-file targets

### Extension Development
- pgvector: Vector operations, similarity search, hybrid retrieval
- Apache AGE: Property graphs, Cypher queries, graph analytics
- See `docs/` playbooks for usage patterns and best practices