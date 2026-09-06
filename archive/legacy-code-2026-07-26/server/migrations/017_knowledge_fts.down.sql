-- 017_knowledge_fts.down.sql

DROP INDEX IF EXISTS idx_articles_knowledge_search_vector;
DROP TRIGGER IF EXISTS tr_articles_knowledge_search_vector ON articles;
DROP FUNCTION IF EXISTS update_article_knowledge_search_vector();
ALTER TABLE articles DROP COLUMN IF EXISTS knowledge_search_vector;
