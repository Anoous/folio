-- 005_fix_precision.down.sql
ALTER TABLE articles
    ALTER COLUMN ai_confidence TYPE DECIMAL(3,2),
    ALTER COLUMN read_progress TYPE DECIMAL(3,2);
