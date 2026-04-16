ALTER TABLE crawl_tasks
    DROP COLUMN IF EXISTS last_attempt_at,
    DROP COLUMN IF EXISTS last_duration_ms,
    DROP COLUMN IF EXISTS error_retryable,
    DROP COLUMN IF EXISTS error_provider,
    DROP COLUMN IF EXISTS error_code,
    DROP COLUMN IF EXISTS error_stage;
