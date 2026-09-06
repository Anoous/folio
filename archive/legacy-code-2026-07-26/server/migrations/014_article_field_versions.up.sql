ALTER TABLE articles
    ADD COLUMN favorite_updated_at TIMESTAMPTZ,
    ADD COLUMN archived_updated_at TIMESTAMPTZ,
    ADD COLUMN progress_updated_at TIMESTAMPTZ;

UPDATE articles
SET
    favorite_updated_at = COALESCE(updated_at, created_at, NOW()),
    archived_updated_at = COALESCE(updated_at, created_at, NOW()),
    progress_updated_at = COALESCE(last_read_at, updated_at, created_at, NOW())
WHERE
    favorite_updated_at IS NULL
    OR archived_updated_at IS NULL
    OR progress_updated_at IS NULL;

ALTER TABLE articles
    ALTER COLUMN favorite_updated_at SET NOT NULL,
    ALTER COLUMN favorite_updated_at SET DEFAULT NOW(),
    ALTER COLUMN archived_updated_at SET NOT NULL,
    ALTER COLUMN archived_updated_at SET DEFAULT NOW(),
    ALTER COLUMN progress_updated_at SET NOT NULL,
    ALTER COLUMN progress_updated_at SET DEFAULT NOW();
