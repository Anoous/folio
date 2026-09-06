-- Migration 013: Auth & stats bug fixes
-- P0-1: Add UNIQUE constraint on email (prevent duplicate accounts)
-- P0-5: Add trigger to update tag counts on article soft-delete
-- P0-6: (stats queries fixed in Go code, not schema)

-- ============================================================
-- 1. Deduplicate existing email rows (keep earliest created)
-- ============================================================
DELETE FROM users u1
USING users u2
WHERE u1.email = u2.email
  AND u1.email IS NOT NULL
  AND u1.created_at > u2.created_at;

-- ============================================================
-- 2. Add UNIQUE constraint on email (NULL is allowed by PG UNIQUE)
-- ============================================================
ALTER TABLE users ADD CONSTRAINT users_email_unique UNIQUE (email);

-- ============================================================
-- 3. Trigger: decrement tag article_count on article soft-delete
-- ============================================================
CREATE OR REPLACE FUNCTION update_tag_counts_on_soft_delete() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        UPDATE tags SET article_count = GREATEST(article_count - 1, 0)
        WHERE id IN (SELECT tag_id FROM article_tags WHERE article_id = NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_article_soft_delete_tag_count ON articles;
CREATE TRIGGER trg_article_soft_delete_tag_count
AFTER UPDATE OF deleted_at ON articles
FOR EACH ROW
EXECUTE FUNCTION update_tag_counts_on_soft_delete();

-- ============================================================
-- 4. Add index on email for faster lookup (already partially covered by UNIQUE)
-- ============================================================
-- UNIQUE constraint creates an implicit index, no extra needed.

-- ============================================================
-- 5. Add timezone column to users for push scheduling (P0-7)
-- ============================================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'Asia/Shanghai';
