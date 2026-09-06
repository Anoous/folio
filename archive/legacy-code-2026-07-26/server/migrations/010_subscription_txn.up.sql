-- 010_subscription_txn.up.sql — Store Apple original_transaction_id for webhook lookup

ALTER TABLE users ADD COLUMN original_transaction_id TEXT;

CREATE UNIQUE INDEX idx_users_original_txn_id
    ON users (original_transaction_id)
    WHERE original_transaction_id IS NOT NULL;
