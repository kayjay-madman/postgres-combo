# PostgreSQL Combo

Production-ready PostgreSQL 16 container with pgvector and Apache AGE extensions for vector similarity search and graph database capabilities.

## Overview

This container combines PostgreSQL 16 with two key extensions:
- **pgvector** (v0.5.1) - Vector embeddings and similarity search
- **Apache AGE** (v1.5.0) - Graph database with Cypher query support

Built using multi-stage Docker build for minimal production footprint with security hardening.

## Quick Start

### Using Pre-built Image (Recommended)

[![Build Status](https://github.com/kayjay-madman/postgres-combo/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/kayjay-madman/postgres-combo/actions/workflows/docker-publish.yml)

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/kayjay-madman/postgres-combo:latest

# Or use in docker-compose.yml
services:
  postgres-combo:
    image: ghcr.io/kayjay-madman/postgres-combo:latest
    # ... rest of configuration
```

### Building Locally

```bash
cp .env.example .env
# Edit .env to set POSTGRES_PASSWORD
docker compose up -d
./test.sh
```

## Available Images

Pre-built multi-platform images are available on GitHub Container Registry:

- `ghcr.io/kayjay-madman/postgres-combo:latest` - Latest stable build
- `ghcr.io/kayjay-madman/postgres-combo:v1.0.0` - Specific version tags
- `ghcr.io/kayjay-madman/postgres-combo:main-<sha>` - Development builds

Supported platforms: `linux/amd64`, `linux/arm64`

## Installation

### Prerequisites
- Docker and Docker Compose
- Minimum 1GB RAM
- Available port 5432 (configurable)

### Setup

1. Configure environment:
   ```bash
   cp .env.example .env
   vim .env  # Set POSTGRES_PASSWORD
   ```

2. Start services:
   ```bash
   docker compose up -d
   ```

3. Verify installation:
   ```bash
   docker compose ps
   ./test.sh
   ```

## Configuration

### Required Variables
- `POSTGRES_PASSWORD` - Database password (required)
- `POSTGRES_USER` - Username (default: postgres)
- `POSTGRES_DB` - Database name (default: postgres)

### Optional Variables
- `CONTAINER_NAME` - Container identifier
- `POSTGRES_HOST_PORT` - Host port mapping (default: 5432)
- `MEMORY_LIMIT` - Memory constraint (default: 1G)
- `CPU_LIMIT` - CPU constraint (default: 1.0)

## Usage Examples

### Vector Operations (pgvector)

```sql
-- Connect to database
psql -h localhost -U postgres -d postgres

-- Create table with vector column
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536)
);

-- Insert data
INSERT INTO documents (content, embedding) VALUES 
('Sample document', '[0.1, 0.2, 0.3, ...]');

-- Create index for similarity search
CREATE INDEX documents_embedding_idx ON documents 
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Find similar documents
SELECT content, (embedding <=> '[0.1, 0.2, 0.3, ...]'::vector) AS distance
FROM documents 
ORDER BY embedding <=> '[0.1, 0.2, 0.3, ...]'::vector 
LIMIT 5;
```

### Graph Operations (Apache AGE)

```sql
-- Setup
SET search_path = ag_catalog, public;
SELECT create_graph('company_graph');

-- Create nodes and relationships
SELECT cypher('company_graph', $$
    CREATE (alice:Person {name: 'Alice', role: 'Developer'})
    CREATE (company:Company {name: 'TechCorp'})
    CREATE (alice)-[:WORKS_FOR]->(company)
$$) as (result agtype);

-- Query graph
SELECT * FROM cypher('company_graph', $$
    MATCH (p:Person)-[:WORKS_FOR]->(c:Company)
    RETURN p.name, c.name
$$) as (person agtype, company agtype);
```

## Testing

Run comprehensive test suite:
```bash
./test.sh
```

Tests validate:
- Environment configuration
- Database connectivity
- Container security
- Extension functionality
- Performance characteristics

## Container Management

```bash
# Start
docker compose up -d

# View logs
docker compose logs -f postgres-combo

# Stop
docker compose down

# Remove data
docker compose down -v

# Health check
docker compose exec postgres-combo /usr/local/bin/healthcheck.sh
```

## Development

### File Structure
```
postgres-combo/
├── .github/
│   └── workflows/       # CI/CD pipelines
├── Dockerfile           # Multi-stage build
├── docker-compose.yml   # Service configuration
├── .env.example         # Configuration template
├── init.sql             # Extension initialization
├── healthcheck.sh       # Health validation
└── test.sh              # Test suite
```

### CI/CD Pipeline

Automated building and publishing to ghcr.io:

- **Pull Requests**: Build and test without publishing
- **Main Branch**: Build, test, and publish as `latest`
- **Version Tags** (`v*`): Build, test, and publish with semantic versioning

#### Publishing Process

1. **Multi-platform Build**: `linux/amd64` and `linux/arm64`
2. **Security Scanning**: Trivy vulnerability analysis
3. **SBOM Generation**: Software Bill of Materials
4. **Automated Tagging**: Semantic versioning and SHA-based tags

#### Manual Release

```bash
# Create and push version tag
git tag v1.0.1
git push origin v1.0.1

# GitHub Actions will automatically:
# - Build multi-platform images
# - Run security scans
# - Publish to ghcr.io
# - Generate SBOM artifacts
```

### Adding Extensions
1. Add compilation to Dockerfile builder stage
2. Copy libraries to runtime stage
3. Add initialization to init.sql
4. Update test suite

## Troubleshooting

### Common Issues

**Connection refused**
```bash
docker compose ps
docker compose logs postgres-combo
```

**Extensions missing**
```sql
SELECT * FROM pg_extension WHERE extname IN ('vector', 'age');
```

**Performance issues**
```bash
./test.sh
docker stats postgres-combo
```

### Verification

```sql
-- Test pgvector
SELECT vector_dims('[1,2,3]'::vector);

-- Test AGE
SET search_path = ag_catalog, public;
SELECT age_version();
```

## Production Notes

- Set strong `POSTGRES_PASSWORD`
- Adjust resource limits for workload
- Monitor health checks and logs
- Implement backup strategy
- Consider connection pooling for high traffic