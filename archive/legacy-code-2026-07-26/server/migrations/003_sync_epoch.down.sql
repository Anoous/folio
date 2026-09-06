-- 003_sync_epoch.down.sql
ALTER TABLE users DROP COLUMN IF EXISTS sync_epoch;
