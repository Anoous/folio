-- 002_v3_upgrade.up.sql — Folio v3 schema upgrade

BEGIN;

-- ============================================
-- 1. Migrate pro_plus users to pro
-- ============================================
UPDATE users SET subscription = 'pro' WHERE subscription = 'pro_plus';

-- ============================================
-- 2. New columns on users
-- ============================================
ALTER TABLE users ADD COLUMN echo_count_this_week   INTEGER     NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN echo_week_reset_at     TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN rag_count_this_month   INTEGER     NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN rag_month_reset_at     TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN total_storage_bytes    BIGINT      NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN article_count          INTEGER     NOT NULL DEFAULT 0;

-- ============================================
-- 3. echo_cards — Echo recall cards
-- ============================================
CREATE TABLE echo_cards (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
    article_id          UUID        NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    card_type           VARCHAR(20) NOT NULL DEFAULT 'insight'
                            CHECK (card_type IN ('insight', 'highlight', 'related')),
    question            TEXT        NOT NULL,
    answer              TEXT        NOT NULL,
    source_context      TEXT,
    next_review_at      TIMESTAMPTZ NOT NULL,
    interval_days       INTEGER     NOT NULL DEFAULT 1,
    ease_factor         DECIMAL(4,2) NOT NULL DEFAULT 2.50,
    review_count        INTEGER     NOT NULL DEFAULT 0,
    correct_count       INTEGER     NOT NULL DEFAULT 0,
    related_article_id  UUID        REFERENCES articles(id) ON DELETE SET NULL,
    highlight_id        UUID,   -- FK added after highlights table; see step 6
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_echo_cards_user_review
    ON echo_cards (user_id, next_review_at)
    WHERE next_review_at <= NOW();

CREATE INDEX idx_echo_cards_article
    ON echo_cards (article_id);

CREATE INDEX idx_echo_cards_user_type
    ON echo_cards (user_id, card_type);

CREATE TRIGGER tr_echo_cards_updated_at
    BEFORE UPDATE ON echo_cards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- 4. echo_reviews — Echo answer records
-- ============================================
CREATE TABLE echo_reviews (
    id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id          UUID        NOT NULL REFERENCES echo_cards(id) ON DELETE CASCADE,
    user_id          UUID        NOT NULL REFERENCES users(id)      ON DELETE CASCADE,
    result           VARCHAR(20) NOT NULL
                         CHECK (result IN ('remembered', 'forgot')),
    response_time_ms INTEGER,
    reviewed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_echo_reviews_card    ON echo_reviews (card_id);
CREATE INDEX idx_echo_reviews_user_at ON echo_reviews (user_id, reviewed_at DESC);

-- ============================================
-- 5. highlights — Text highlights
-- ============================================
CREATE TABLE highlights (
    id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id   UUID        NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    user_id      UUID        NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
    text         TEXT        NOT NULL,
    start_offset INTEGER     NOT NULL,
    end_offset   INTEGER     NOT NULL,
    color        VARCHAR(20) NOT NULL DEFAULT 'accent',
    note         TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_highlights_article_user ON highlights (article_id, user_id);
CREATE INDEX idx_highlights_user_at      ON highlights (user_id, created_at DESC);

-- ============================================
-- 6. Back-fill FK from echo_cards to highlights
-- ============================================
ALTER TABLE echo_cards
    ADD CONSTRAINT fk_echo_cards_highlight
        FOREIGN KEY (highlight_id) REFERENCES highlights(id) ON DELETE SET NULL;

-- ============================================
-- 7. rag_conversations — RAG chat sessions
-- ============================================
CREATE TABLE rag_conversations (
    id         UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title      VARCHAR(200),
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rag_conversations_user_at ON rag_conversations (user_id, updated_at DESC);

CREATE TRIGGER tr_rag_conversations_updated_at
    BEFORE UPDATE ON rag_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================
-- 8. rag_messages — RAG chat messages
-- ============================================
CREATE TABLE rag_messages (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     UUID        NOT NULL REFERENCES rag_conversations(id) ON DELETE CASCADE,
    role                VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant')),
    content             TEXT        NOT NULL,
    source_article_ids  JSONB       DEFAULT '[]',
    source_count        INTEGER     NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rag_messages_conversation ON rag_messages (conversation_id, created_at);

-- ============================================
-- 9. user_milestones — Cold start milestones
-- ============================================
CREATE TABLE user_milestones (
    id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id        UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    milestone_type VARCHAR(30) NOT NULL
                       CHECK (milestone_type IN (
                           'first_article', 'first_association',
                           'first_echo', 'trial_summary', 'free_limit'
                       )),
    achieved_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    dismissed      BOOLEAN     NOT NULL DEFAULT FALSE,
    metadata       JSONB       DEFAULT '{}',
    UNIQUE (user_id, milestone_type)
);

CREATE INDEX idx_user_milestones_user ON user_milestones (user_id);

-- ============================================
-- 10. article_embeddings — P1 vector embedding placeholder
-- ============================================
CREATE TABLE article_embeddings (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id  UUID        NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
    embedding   BYTEA,
    model       VARCHAR(50),
    chunk_index INTEGER     NOT NULL DEFAULT 0,
    chunk_text  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (article_id, chunk_index)
);

CREATE INDEX idx_article_embeddings_user ON article_embeddings (user_id);

-- ============================================
-- 11. New columns on articles
-- ============================================
ALTER TABLE articles
    ADD COLUMN highlight_count  INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN echo_card_count  INTEGER NOT NULL DEFAULT 0;

-- ============================================
-- 12. Seed / upsert 9 preset categories
-- ============================================
INSERT INTO categories (slug, name_zh, name_en, icon, sort_order) VALUES
    ('tech',       '技术',     'Technology', 'cpu',            1),
    ('business',   '商业',     'Business',   'briefcase',      2),
    ('science',    '科学',     'Science',    'flask',          3),
    ('culture',    '文化',     'Culture',    'book-open',      4),
    ('lifestyle',  '生活方式', 'Lifestyle',  'heart',          5),
    ('news',       '新闻',     'News',       'newspaper',      6),
    ('education',  '教育',     'Education',  'academic-cap',   7),
    ('design',     '设计',     'Design',     'paint-brush',    8),
    ('other',      '其他',     'Other',      'dots-horizontal',9)
ON CONFLICT (slug) DO NOTHING;

COMMIT;
