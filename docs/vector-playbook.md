# Vector Playbook

Advanced pgvector usage patterns bundled with postgres-combo.

## Hybrid Search Pipeline
```sql
-- Document table combining metadata, dense vectors, and sparse keywords
CREATE TABLE documents (
    doc_id         BIGSERIAL PRIMARY KEY,
    title          TEXT NOT NULL,
    body           TEXT NOT NULL,
    embedding      VECTOR(1536) NOT NULL,
    keywords       TSVECTOR GENERATED ALWAYS AS (to_tsvector('english', body)) STORED,
    metadata       JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- IVF-Flat index tuned for cosine similarity
CREATE INDEX documents_embedding_idx
    ON documents USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 200);

-- Sparse search index for BM25 reranking
CREATE INDEX documents_keywords_idx ON documents USING GIN (keywords);
```

### Query: Semantic + Keyword Fusion
```sql
WITH semantic AS (
    SELECT doc_id,
           1 - (embedding <=> '[0.12, ... , 0.08]'::vector) AS semantic_score
    FROM documents
    ORDER BY embedding <=> '[0.12, ... , 0.08]'::vector
    LIMIT 200
),
lexical AS (
    SELECT doc_id,
           ts_rank_cd(keywords, to_tsquery('english', 'supply & chain')) AS lexical_score
    FROM documents
    WHERE keywords @@ to_tsquery('english', 'supply & chain')
)
SELECT d.doc_id,
       d.title,
       semantic_score * 0.7 + COALESCE(lexical_score, 0) * 0.3 AS blended_score,
       d.metadata
FROM documents d
LEFT JOIN semantic USING (doc_id)
LEFT JOIN lexical USING (doc_id)
ORDER BY blended_score DESC
LIMIT 20;
```

## Batch Upserts with Similarity Guardrails
```sql
-- Reject near-duplicate vectors to keep the index lean
CREATE OR REPLACE FUNCTION guardrail_insert_documents(
    _title TEXT,
    _body TEXT,
    _embedding VECTOR(1536)
) RETURNS BIGINT AS $$
DECLARE
    _existing BIGINT;
BEGIN
    SELECT doc_id INTO _existing
    FROM documents
    WHERE embedding <#> _embedding < 0.04
    ORDER BY embedding <#> _embedding
    LIMIT 1;

    IF FOUND THEN
        RETURN _existing; -- Skip insert, reuse canonical doc
    END IF;

    INSERT INTO documents(title, body, embedding)
    VALUES (_title, _body, _embedding)
    RETURNING doc_id INTO _existing;

    RETURN _existing;
END;
$$ LANGUAGE plpgsql;
```

## Real-Time Similarity Notifications
```sql
CREATE TABLE vector_alerts (
    alert_id    BIGSERIAL PRIMARY KEY,
    doc_id      BIGINT NOT NULL REFERENCES documents(doc_id),
    threshold   REAL NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION notify_similar_insert() RETURNS TRIGGER AS $$
DECLARE
    _match BIGINT;
BEGIN
    SELECT doc_id INTO _match
    FROM documents
    WHERE doc_id <> NEW.doc_id
      AND embedding <=> NEW.embedding < NEW.metadata->>'alert_threshold'
    ORDER BY embedding <=> NEW.embedding
    LIMIT 1;

    IF FOUND THEN
        INSERT INTO vector_alerts(doc_id, threshold)
        VALUES (NEW.doc_id, (NEW.metadata->>'alert_threshold')::REAL);
        PERFORM pg_notify('vector_alert', json_build_object(
            'doc_id', NEW.doc_id,
            'match_id', _match,
            'threshold', NEW.metadata->>'alert_threshold'
        )::TEXT);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER documents_vector_alert
    AFTER INSERT ON documents
    FOR EACH ROW EXECUTE FUNCTION notify_similar_insert();
```

### Operational Tips
- Periodically `REINDEX` the IVF index or rebuild with different `lists` for evolving datasets.
- Store the original embedding arrays externally (object store) and hydrate as needed to keep table lean.
- Use `pg_stat_io` to monitor index hit ratios after each batch ingest.
