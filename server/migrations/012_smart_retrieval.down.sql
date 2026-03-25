-- 012_smart_retrieval.down.sql

DROP TABLE IF EXISTS article_relations;
DROP INDEX IF EXISTS idx_articles_summary_trgm;
ALTER TABLE articles DROP COLUMN IF EXISTS semantic_keywords;
