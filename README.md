# PostgreSQL Combo

PostgreSQL 16 bundled with pgvector and Apache AGE for applications that need vector search, graph analytics, and relational workloads in a single container.

## Stack Highlights
- **pgvector** (v0.8.1) for vector similarity search and hybrid retrieval
- **Apache AGE** (v1.6.0) for property graphs and Cypher support
- Hardened runtime: non-root execution, healthcheck script, optional security overlay
- Versions are pinned in `build/versions.mk` for reproducible builds and releases

## Quick Start (Local Build)
```bash
cp .env.example .env   # edit POSTGRES_PASSWORD
make up                # start with base config
make test              # run smoke tests (brings stack up/down)
```

Prefer production defaults? Use `make up-secure` to apply the hardened compose overlay. If you are driving Docker Compose yourself, make sure to combine the files so the hardened settings extend the base definition:

```bash
docker compose \
  -f deploy/docker-compose.yml \
  -f deploy/docker-compose.hardened.yml \
  up -d

# or export once and reuse on subsequent commands
COMPOSE_FILE=deploy/docker-compose.yml:deploy/docker-compose.hardened.yml docker compose up -d
```

Monitor logs with `make logs` and tear everything down with `make down` (or `make clean` to remove volumes).

## Using the GHCR Image
Images are published to GitHub Container Registry under `ghcr.io/kayjay-madman/postgres-combo`.

```bash
# Pull the latest build
docker pull ghcr.io/kayjay-madman/postgres-combo:latest

# Run an ephemeral instance
docker run --rm \
  -e POSTGRES_PASSWORD=supersecret \
  -p 5432:5432 \
  ghcr.io/kayjay-madman/postgres-combo:latest

# Or launch with docker compose straight from the registry
cat <<'YAML' > compose.yaml
services:
  postgres-combo:
    image: ghcr.io/kayjay-madman/postgres-combo:latest
    environment:
      POSTGRES_PASSWORD: supersecret
    ports:
      - 5432:5432
    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck.sh"]
      interval: 30s
      timeout: 10s
      retries: 3
YAML

docker compose up -d
```

### Tag Reference
- `:latest` tracks the main branch
- `:vX.Y.Z` denotes immutable releases (recommended for production)
- `:main-<git-sha>` provides commit-specific images for validation

Override the image for any `make` target with `IMAGE_TAG`, e.g. `make up IMAGE_TAG=v1.0.0`.

## Repository Layout
- `build/` – Dockerfile and version manifest used for image creation
- `config/` – database bootstrap SQL and the container healthcheck
- `deploy/` – compose descriptors (base + hardened overlay)
- `docs/` – advanced relational, vector, and graph playbooks
- `scripts/` – shared libraries, tooling, and automation helpers
- `tasks/Makefile` – task runner included by the top-level `Makefile`
- `tests/` – host-side smoke tests (`tests/test.sh`)

## Building Images Locally
```bash
make build                       # use pins from build/versions.mk
make build IMAGE_TAG=my-feature   # override the target tag
```
The build pipeline consumes `build/versions.mk` to wire version metadata and image labels.

## Configuration
`.env` drives runtime settings. Key variables:
- `POSTGRES_PASSWORD` (required)
- `POSTGRES_USER`, `POSTGRES_DB`, `POSTGRES_HOST_PORT`
- `CONTAINER_NAME`, `IMAGE_NAME`, `IMAGE_TAG`

Running `make verify-env` (invoked automatically by other targets) ensures `.env` exists.

### Connection Cheatsheet
```bash
# From the host
psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-postgres}

# From inside the container
docker compose exec postgres-combo psql -U postgres -d postgres
```

## Extension Recipes
Vector search:
```sql
CREATE TABLE items (id SERIAL PRIMARY KEY, embedding vector(1536));
CREATE INDEX ON items USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
SELECT * FROM items ORDER BY embedding <=> '[0.1,0.2,0.3]'::vector LIMIT 10;
```

Property graphs:
```sql
SET search_path = ag_catalog, public;
SELECT create_graph('knowledge_graph');
SELECT cypher('knowledge_graph', $$
    CREATE (p:Person {name: 'Alice'})-[:WORKS_FOR]->(:Company {name: 'TechCorp'})
$$) AS result;
```

For deeper recipes see:
- `docs/relational-playbook.md` – multi-tenant schemas, RLS, replication
- `docs/vector-playbook.md` – hybrid retrieval, alerting triggers, guardrails
- `docs/graph-playbook.md` – AGE ingestion pipelines, analytics, vector-aware traversals

## Maintenance Tasks
- `make sync-versions` keeps README and maintainer docs aligned with `build/versions.mk`
- `make scan` runs the consolidated Trivy security scan (`scripts/security/scan.sh`)
- GitHub Actions reuse `make build` / `make test` for CI parity

## Troubleshooting
- `docker compose ps` validates service health
- `make logs` tails PostgreSQL output
- `make test` reruns the end-to-end suite (`tests/test.sh`)
- `docker compose exec postgres-combo /usr/local/bin/healthcheck.sh` performs an inline probe
