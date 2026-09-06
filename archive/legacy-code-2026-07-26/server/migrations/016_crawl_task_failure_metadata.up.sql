ALTER TABLE crawl_tasks
    ADD COLUMN error_stage TEXT,
    ADD COLUMN error_code TEXT,
    ADD COLUMN error_provider TEXT,
    ADD COLUMN error_retryable BOOLEAN,
    ADD COLUMN last_duration_ms BIGINT,
    ADD COLUMN last_attempt_at TIMESTAMPTZ;
