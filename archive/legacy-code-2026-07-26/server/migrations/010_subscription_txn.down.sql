-- 010_subscription_txn.down.sql

DROP INDEX IF EXISTS idx_users_original_txn_id;
ALTER TABLE users DROP COLUMN IF EXISTS original_transaction_id;
