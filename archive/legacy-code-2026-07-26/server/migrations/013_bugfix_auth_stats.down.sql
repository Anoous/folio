-- Rollback migration 013
ALTER TABLE users DROP COLUMN IF EXISTS timezone;
DROP TRIGGER IF EXISTS trg_article_soft_delete_tag_count ON articles;
DROP FUNCTION IF EXISTS update_tag_counts_on_soft_delete();
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_unique;
