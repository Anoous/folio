-- 005_fix_precision.up.sql
-- DECIMAL(3,2) only allows values 0.00–9.99 which truncates valid
-- confidence (0–1) and read_progress (0–1) values at two decimal places.
-- Switch to DOUBLE PRECISION for full IEEE 754 range.

ALTER TABLE articles
    ALTER COLUMN ai_confidence TYPE DOUBLE PRECISION,
    ALTER COLUMN read_progress TYPE DOUBLE PRECISION;
