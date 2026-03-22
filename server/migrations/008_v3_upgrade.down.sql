-- 002_v3_upgrade.down.sql — Rollback Folio v3 schema upgrade
-- NOTE: The pro_plus → pro data migration (step 1) is irreversible.
--       Users migrated to 'pro' will NOT be restored to 'pro_plus'.

BEGIN;

-- Drop new tables in reverse dependency order

-- 10. article_embeddings
DROP TABLE IF EXISTS article_embeddings;

-- 9. user_milestones
DROP TABLE IF EXISTS user_milestones;

-- 8. rag_messages
DROP TABLE IF EXISTS rag_messages;

-- 7. rag_conversations
DROP TABLE IF EXISTS rag_conversations;

-- 4. echo_reviews (references echo_cards — must drop before echo_cards)
DROP TABLE IF EXISTS echo_reviews;

-- 6. Remove FK from echo_cards to highlights (must drop before highlights)
ALTER TABLE echo_cards DROP CONSTRAINT IF EXISTS fk_echo_cards_highlight;

-- 5. highlights
DROP TABLE IF EXISTS highlights;

-- 3. echo_cards
DROP TABLE IF EXISTS echo_cards;

-- 11. Remove columns added to articles
ALTER TABLE articles
    DROP COLUMN IF EXISTS highlight_count,
    DROP COLUMN IF EXISTS echo_card_count;

-- 2. Remove columns added to users
ALTER TABLE users DROP COLUMN IF EXISTS echo_count_this_week;
ALTER TABLE users DROP COLUMN IF EXISTS echo_week_reset_at;
ALTER TABLE users DROP COLUMN IF EXISTS rag_count_this_month;
ALTER TABLE users DROP COLUMN IF EXISTS rag_month_reset_at;
ALTER TABLE users DROP COLUMN IF EXISTS total_storage_bytes;
ALTER TABLE users DROP COLUMN IF EXISTS article_count;

COMMIT;
