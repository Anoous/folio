-- 012_smart_retrieval.up.sql

-- 1. Semantic keywords column for LLM-powered recall
ALTER TABLE articles ADD COLUMN semantic_keywords TEXT[] DEFAULT '{}';
CREATE INDEX idx_articles_semantic_keywords ON articles USING GIN (semantic_keywords);

-- 2. Summary trigram index for ILIKE acceleration
CREATE INDEX idx_articles_summary_trgm ON articles USING GIN (summary gin_trgm_ops);

-- 3. Related articles cache table
CREATE TABLE article_relations (
    source_article_id  UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    related_article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    relevance_reason   TEXT,
    score              SMALLINT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_article_id, related_article_id)
);
CREATE INDEX idx_article_relations_source ON article_relations (source_article_id, score);

-- 4. Drop unused placeholder table from migration 008
DROP TABLE IF EXISTS article_embeddings;
