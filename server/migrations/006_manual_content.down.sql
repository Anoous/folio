-- 006_manual_content.down.sql
-- Rollback: Delete URL-less records and restore NOT NULL constraints

-- Clean up URL-less records before restoring constraint
DELETE FROM crawl_tasks WHERE url IS NULL;
DELETE FROM articles WHERE url IS NULL;

-- Restore NOT NULL on crawl_tasks.url
ALTER TABLE crawl_tasks ALTER COLUMN url SET NOT NULL;

-- Restore unique index without partial condition
DROP INDEX idx_articles_user_url;
CREATE UNIQUE INDEX idx_articles_user_url ON articles (user_id, url);

-- Restore NOT NULL on articles.url
ALTER TABLE articles ALTER COLUMN url SET NOT NULL;
