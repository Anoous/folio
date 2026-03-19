-- 006_manual_content.up.sql
-- Allow nullable URL for manual content (pasted text, personal thoughts without URL)
-- Convert unique index to partial index (only enforce uniqueness for rows with non-NULL URL)

-- articles.url: NOT NULL → nullable
ALTER TABLE articles ALTER COLUMN url DROP NOT NULL;

-- Unique constraint becomes partial (only for rows with URL)
DROP INDEX idx_articles_user_url;
CREATE UNIQUE INDEX idx_articles_user_url ON articles (user_id, url) WHERE url IS NOT NULL;

-- crawl_tasks.url: NOT NULL → nullable (manual entries have no URL)
ALTER TABLE crawl_tasks ALTER COLUMN url DROP NOT NULL;
