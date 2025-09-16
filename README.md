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

-- Create table with vector column (using 384 dimensions - common for sentence transformers)
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(384)
);

-- Insert sample documents with different embeddings
INSERT INTO documents (content, embedding) VALUES 
('Machine learning is transforming industries', array_fill(0.8, ARRAY[384])::vector),
('Artificial intelligence and deep learning', array_fill(0.7, ARRAY[384])::vector),
('Database systems and SQL queries', array_fill(0.2, ARRAY[384])::vector),
('Web development with JavaScript', array_fill(0.1, ARRAY[384])::vector),
('Data science and analytics', array_fill(0.6, ARRAY[384])::vector);

-- Create index for similarity search
CREATE INDEX documents_embedding_idx ON documents 
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Find documents similar to "AI and machine learning" query
SELECT content, (embedding <=> array_fill(0.75, ARRAY[384])::vector) AS distance
FROM documents 
ORDER BY embedding <=> array_fill(0.75, ARRAY[384])::vector 
LIMIT 3;

-- Alternative: using a specific vector
SELECT content, (embedding <-> '[0.8,0.7,0.6]'::vector(3)) AS l2_distance
FROM (SELECT content, embedding[1:3] as embedding FROM documents) t
ORDER BY embedding <-> '[0.8,0.7,0.6]'::vector(3)
LIMIT 3;
```

### Graph Operations (Apache AGE)

```sql
-- Setup Apache AGE
SET search_path = ag_catalog, public;
SELECT create_graph('company_graph');

-- Create a comprehensive company organizational graph
SELECT * FROM cypher('company_graph', $$
    CREATE (alice:Person {name: 'Alice', role: 'Developer', years: 3})
    CREATE (bob:Person {name: 'Bob', role: 'Manager', years: 5})
    CREATE (carol:Person {name: 'Carol', role: 'Designer', years: 2})
    CREATE (dave:Person {name: 'Dave', role: 'DevOps', years: 4})
    CREATE (techcorp:Company {name: 'TechCorp', industry: 'Software'})
    CREATE (frontend:Team {name: 'Frontend', size: 3})
    CREATE (backend:Team {name: 'Backend', size: 4})
    CREATE (alice)-[:WORKS_FOR]->(techcorp)
    CREATE (bob)-[:WORKS_FOR]->(techcorp)
    CREATE (carol)-[:WORKS_FOR]->(techcorp)
    CREATE (dave)-[:WORKS_FOR]->(techcorp)
    CREATE (bob)-[:MANAGES]->(alice)
    CREATE (bob)-[:MANAGES]->(carol)
    CREATE (alice)-[:MEMBER_OF]->(backend)
    CREATE (carol)-[:MEMBER_OF]->(frontend)
    CREATE (dave)-[:SUPPORTS]->(frontend)
    CREATE (dave)-[:SUPPORTS]->(backend)
$$) as (result agtype);

-- Query: Find all employees and their roles
SELECT * FROM cypher('company_graph', $$
    MATCH (p:Person)-[:WORKS_FOR]->(c:Company)
    RETURN p.name, p.role, p.years, c.name
$$) as (person_name agtype, role agtype, experience agtype, company agtype);

-- Query: Find management hierarchy
SELECT * FROM cypher('company_graph', $$
    MATCH (manager:Person)-[:MANAGES]->(employee:Person)
    RETURN manager.name, employee.name, employee.role
$$) as (manager agtype, employee agtype, role agtype);

-- Query: Find team compositions
SELECT * FROM cypher('company_graph', $$
    MATCH (p:Person)-[:MEMBER_OF]->(t:Team)
    RETURN t.name, collect(p.name) as members
$$) as (team agtype, members agtype);

-- Query: Find people with specific experience (path traversal)
SELECT * FROM cypher('company_graph', $$
    MATCH (p:Person)-[:WORKS_FOR]->(c:Company)
    WHERE p.years >= 4
    RETURN p.name, p.role, p.years
    ORDER BY p.years DESC
$$) as (name agtype, role agtype, years agtype);

-- Query: Find cross-team support relationships
SELECT * FROM cypher('company_graph', $$
    MATCH (p:Person)-[:SUPPORTS]->(t:Team)<-[:MEMBER_OF]-(member:Person)
    RETURN p.name as supporter, t.name as team, collect(member.name) as supported_members
$$) as (supporter agtype, team agtype, members agtype);

-- Advanced: Find all paths between two people
SELECT * FROM cypher('company_graph', $$
    MATCH path = (alice:Person {name: 'Alice'})-[*1..3]-(dave:Person {name: 'Dave'})
    RETURN path
$$) as (connection_path agtype);

-- Alternative: Find specific relationship chains
SELECT * FROM cypher('company_graph', $$
    MATCH (alice:Person {name: 'Alice'})-[r1]->(middle)-[r2]->(dave:Person {name: 'Dave'})
    RETURN alice.name, type(r1), middle, type(r2), dave.name
$$) as (start_person agtype, rel1_type agtype, middle_node agtype, rel2_type agtype, end_person agtype);
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