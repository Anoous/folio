ALTER TABLE articles
    DROP COLUMN IF EXISTS progress_updated_at,
    DROP COLUMN IF EXISTS archived_updated_at,
    DROP COLUMN IF EXISTS favorite_updated_at;
