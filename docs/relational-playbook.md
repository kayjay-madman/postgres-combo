# Relational Playbook

Deep-dive recipes for traditional SQL workloads on the postgres-combo image.

## Multi-Tenant Schema Pattern
```sql
-- Provision tenants using dedicated schemas while sharing extensions
CREATE SCHEMA IF NOT EXISTS tenant_blue AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS tenant_green AUTHORIZATION postgres;

SET search_path = tenant_blue, public;

CREATE TABLE tenant_blue.accounts (
    account_id    BIGSERIAL PRIMARY KEY,
    company_name  TEXT NOT NULL,
    plan          TEXT NOT NULL CHECK (plan IN ('starter','growth','enterprise')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE tenant_blue.users (
    user_id     BIGSERIAL PRIMARY KEY,
    account_id  BIGINT NOT NULL REFERENCES tenant_blue.accounts(account_id),
    email       CITEXT NOT NULL UNIQUE,
    role        TEXT NOT NULL CHECK (role IN ('admin','member')),
    metadata    JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX CONCURRENTLY IF NOT EXISTS users_account_idx
    ON tenant_blue.users(account_id) INCLUDE (email);
```

## Managed Row-Level Security
```sql
ALTER TABLE tenant_blue.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON tenant_blue.users
    USING (current_setting('app.tenant_id')::BIGINT = account_id);

-- Session bootstrap
SELECT set_config('app.tenant_id', '42', false);

-- Application query
SELECT user_id, email, role
FROM tenant_blue.users
ORDER BY created_at DESC
LIMIT 20;
```

## Materialized Views with Refresh Scheduling
```sql
CREATE MATERIALIZED VIEW tenant_blue.mrr_snapshots AS
SELECT date_trunc('month', created_at) AS month,
       plan,
       COUNT(*)                       AS new_accounts
FROM tenant_blue.accounts
GROUP BY 1, 2;

REFRESH MATERIALIZED VIEW CONCURRENTLY tenant_blue.mrr_snapshots;

-- Lightweight refresh scheduler using pg_cron (if enabled)
SELECT cron.schedule('refresh-mrr', '5 * * * *',
    $$REFRESH MATERIALIZED VIEW CONCURRENTLY tenant_blue.mrr_snapshots$$);
```

## Logical Replication for Analytics
```sql
CREATE PUBLICATION analytics_pub FOR TABLE tenant_blue.accounts, tenant_blue.users;

-- On the read replica
CREATE SUBSCRIPTION analytics_sub
    CONNECTION 'host=db-primary port=5432 user=replicator password=secret dbname=analytics'
    PUBLICATION analytics_pub
    WITH (copy_data = true, create_slot = true);
```

### Tuning Notes
- Use `ALTER ROLE analytics SET search_path = tenant_blue, public;`
- Layer pgvector/AGE features per tenant by pointing `search_path` at the schema.
- For high write throughput, dedicate WAL sender slots and monitor `pg_stat_replication`.
