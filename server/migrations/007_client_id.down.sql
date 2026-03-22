DROP INDEX IF EXISTS idx_articles_user_client_id;
ALTER TABLE articles DROP COLUMN IF EXISTS client_id;
