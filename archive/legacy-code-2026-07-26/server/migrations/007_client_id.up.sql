-- 007_client_id.up.sql
-- Add client_id for idempotent manual content submission.
-- Client sends its local UUID; server rejects duplicates.

ALTER TABLE articles ADD COLUMN client_id VARCHAR(36);
CREATE UNIQUE INDEX idx_articles_user_client_id ON articles (user_id, client_id) WHERE client_id IS NOT NULL;
