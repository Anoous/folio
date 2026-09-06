-- 002_soft_delete.up.sql — 文章软删除支持

-- Add soft delete column
ALTER TABLE articles ADD COLUMN deleted_at TIMESTAMPTZ NULL;

-- Index for efficient filtering of non-deleted and soft-deleted articles
CREATE INDEX idx_articles_deleted_at ON articles(deleted_at) WHERE deleted_at IS NOT NULL;
