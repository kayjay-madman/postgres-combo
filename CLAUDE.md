# CLAUDE.md

Developer guidance for postgres-combo project.

## Project Overview

Production PostgreSQL 16 container with pgvector (v0.5.1) and Apache AGE (v1.5.0) extensions. Multi-stage build with security hardening and non-root execution.

## Architecture

### Build Process
1. **Builder Stage** - Compiles pgvector and Apache AGE from source
2. **Runtime Stage** - Minimal PostgreSQL with compiled extensions only  
3. **Security** - Non-root execution, restricted privileges

### File Structure
```
postgres-combo/
├── Dockerfile           # Multi-stage build
├── docker-compose.yml   # Service definition
├── .env.example         # Configuration template  
├── init.sql             # Extension initialization
├── healthcheck.sh       # Health validation
└── test.sh              # Test suite
```

## Setup Commands

```bash
cp .env.example .env
vim .env  # Set POSTGRES_PASSWORD
docker compose up -d
docker compose ps
./test.sh
```

## Database Connection

```bash
# From host
psql -h localhost -U postgres -d postgres

# From container
docker compose exec postgres-combo psql -U postgres -d postgres
```

## Environment Variables

### Required
- `POSTGRES_PASSWORD` - Database password

### Optional  
- `POSTGRES_USER` (default: postgres)
- `POSTGRES_DB` (default: postgres)
- `CONTAINER_NAME` (default: postgres-combo)
- `POSTGRES_HOST_PORT` (default: 5432)
- `MEMORY_LIMIT` (default: 1G)
- `CPU_LIMIT` (default: 1.0)

## Extension Usage

### pgvector
```sql
ALTER TABLE items ADD COLUMN embedding vector(1536);
CREATE INDEX ON items USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
SELECT * FROM items ORDER BY embedding <=> '[0.1,0.2,0.3]'::vector LIMIT 10;
```

### Apache AGE
```sql
SET search_path = ag_catalog, public;
SELECT create_graph('knowledge_graph');
SELECT cypher('knowledge_graph', $$
    CREATE (p:Person {name: 'Alice'}) 
    CREATE (c:Company {name: 'TechCorp'})
    CREATE (p)-[:WORKS_FOR]->(c)
$$) as (result agtype);
```

## Container Operations

```bash
docker compose up -d
docker compose logs -f postgres-combo  
docker compose down
docker compose down -v
```

## Development

### Testing
`./test.sh` validates environment, connectivity, security, extensions, and performance.

### Adding Extensions
1. Add compilation to Dockerfile builder stage
2. Copy libraries to runtime stage  
3. Add initialization to init.sql
4. Update test suite

### Initialization
Extensions are enabled via `init.sql` with error handling. AGE preload is configured in Dockerfile.

## Troubleshooting

### Verification Commands
```sql
SELECT * FROM pg_extension WHERE extname IN ('vector', 'age');
SELECT vector_dims('[1,2,3]'::vector);
SET search_path = ag_catalog, public; SELECT age_version();
```

### Common Fixes
- Connection issues: Check `docker compose ps`
- Extension issues: Verify with `SELECT * FROM pg_extension;`
- Performance issues: Run `./test.sh`

## Production Deployment

1. Set strong `POSTGRES_PASSWORD` in `.env`
2. Adjust resource limits based on workload
3. Monitor health checks and logs  
4. Implement backup strategy
5. Consider connection pooling for high traffic