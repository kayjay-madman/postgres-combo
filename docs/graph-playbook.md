# Graph Playbook

Apache AGE scenarios tailored for postgres-combo deployments.

## Knowledge Graph with Incremental Ingestion
```sql
SET search_path = ag_catalog, public;
SELECT create_graph('supply_chain');

SELECT * FROM cypher('supply_chain', $$
    CREATE CONSTRAINT unique_company IF NOT EXISTS
    FOR (c:Company) REQUIRE c.id IS UNIQUE
$$) AS (result agtype);

-- Stream ingestion procedure
CREATE OR REPLACE FUNCTION load_shipment(_payload JSONB) RETURNS VOID AS $$
BEGIN
    PERFORM * FROM cypher('supply_chain', $$
        MERGE (o:Company {id: $origin.id})
          ON CREATE SET o.name = $origin.name
        MERGE (d:Company {id: $destination.id})
          ON CREATE SET d.name = $destination.name
        MERGE (s:Shipment {id: $shipment.id})
          ON CREATE SET s.created_at = datetime($shipment.created_at)
        MERGE (o)-[:SHIPPED]->(s)-[:DELIVERED]->(d)
    $$) AS (result agtype)
    USING _payload;
END;
$$ LANGUAGE plpgsql;
```

## Temporal Pattern Detection
```sql
SELECT * FROM cypher('supply_chain', $$
    MATCH (o:Company)-[:SHIPPED]->(s:Shipment)-[:DELIVERED]->(d:Company)
    WHERE s.created_at >= datetime({year:2025, month:1, day:1})
      AND s.created_at <  datetime({year:2025, month:1, day:31})
    WITH o, d, count(s) AS shipments
    WHERE shipments > 100
    RETURN o.name AS origin, d.name AS destination, shipments
    ORDER BY shipments DESC
    LIMIT 20
$$) AS (origin agtype, destination agtype, shipments agtype);
```

## Graph + Vector Fusion
```sql
-- Attach embeddings to graph nodes for hybrid traversals
SELECT * FROM cypher('supply_chain', $$
    MATCH (c:Company {id: $company_id})
    SET c.embedding = vector[$e1, $e2, ... , $e1536]
    RETURN c
$$) AS (company agtype)
USING  {company_id: 'acme-global', e1:0.12, e2:0.04};

-- Vector-aware traversal: find similar suppliers two hops away
WITH params AS (
    SELECT '[0.08, ... , 0.17]'::vector AS query_embedding
)
SELECT * FROM cypher('supply_chain', $$
    MATCH (c:Company {id: $company_id})-[:DELIVERED]->(:Shipment)<-[:SHIPPED]-(supplier:Company)
    RETURN supplier.id AS supplier_id,
           supplier.embedding <=> $query_embedding AS distance
    ORDER BY distance
    LIMIT 10
$$) AS (supplier_id agtype, distance agtype)
CROSS JOIN params
USING  {company_id: 'retail-co'};
```

## Graph Analytics Snapshot
```sql
-- Export centrality metrics to relational tables for dashboarding
SELECT * FROM cypher('supply_chain', $$
    CALL ag_catalog.pageRank(
      'supply_chain',
      {writeProperty: 'page_rank', beta: 0.2, weightProperty: 'volume'}
    )
$$) AS (node agtype);

INSERT INTO analytics.company_centrality (company_id, score)
SELECT (properties->>'id')::TEXT,
       (properties->>'page_rank')::NUMERIC
FROM ag_catalog.cypher_result('supply_chain');
```

### Operational Tips
- Store graph snapshots with `SELECT * FROM ag_catalog.create_graph_snapshot('supply_chain', 'snapshot_2025_01');`
- Combine AGE constraints with relational FK checks to enforce data quality before ingestion.
- Remember to vacuum AGE catalog tables periodically (`VACUUM FULL ag_catalog.*`).
