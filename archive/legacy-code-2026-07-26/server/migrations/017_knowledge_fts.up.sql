-- 017_knowledge_fts.up.sql
--
-- Sparse retrieval guardrail for Ask/Search/Spark/Learn.
-- This keeps exact-term and body-only evidence fast without requiring vector
-- embeddings to carry all recall responsibility.

ALTER TABLE articles
ADD COLUMN knowledge_search_vector tsvector;

CREATE OR REPLACE FUNCTION update_article_knowledge_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.knowledge_search_vector :=
        setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(array_to_string(NEW.semantic_keywords, ' '), '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(NEW.summary, '')), 'B') ||
        setweight(to_tsvector('simple', coalesce(NEW.key_points::text, '')), 'B') ||
        setweight(to_tsvector('simple', coalesce(NEW.markdown_content, '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

UPDATE articles
SET knowledge_search_vector =
    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(array_to_string(semantic_keywords, ' '), '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(summary, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(key_points::text, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(markdown_content, '')), 'C');

CREATE TRIGGER tr_articles_knowledge_search_vector
BEFORE INSERT OR UPDATE OF title, summary, key_points, semantic_keywords, markdown_content
ON articles
FOR EACH ROW
EXECUTE FUNCTION update_article_knowledge_search_vector();

CREATE INDEX idx_articles_knowledge_search_vector
ON articles USING GIN (knowledge_search_vector);
