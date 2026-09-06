-- 003_sync_epoch.up.sql
ALTER TABLE users ADD COLUMN sync_epoch INTEGER NOT NULL DEFAULT 1;
