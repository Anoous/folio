-- Folio 合并迁移: 008 ~ 012
-- 目标: 广州服务器从 007 (client_id) 升级到 012 (smart_retrieval)
-- 生成时间: 2026-03-25

BEGIN;

-- ============================================
-- 008: V3 大版本升级
-- ============================================

-- 1. pro_plus → pro (无 pro_plus 用户时为空操作)
UPDATE users SET subscription = 'pro' WHERE subscription = 'pro_plus';

-- 2. users 新增列
ALTER TABLE users ADD COLUMN echo_count_this_week   INTEGER     NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN echo_week_reset_at     TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN rag_count_this_month   INTEGER     NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN rag_month_reset_at     TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN total_storage_bytes    BIGINT      NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN article_count          INTEGER     NOT NULL DEFAULT 0;

-- 3. echo_cards — Echo 回忆卡片
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
    highlight_id        UUID,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_echo_cards_user_review ON echo_cards (user_id, next_review_at);
CREATE INDEX idx_echo_cards_article     ON echo_cards (article_id);
CREATE INDEX idx_echo_cards_user_type   ON echo_cards (user_id, card_type);

CREATE TRIGGER tr_echo_cards_updated_at
    BEFORE UPDATE ON echo_cards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 4. echo_reviews — Echo 答题记录
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

-- 5. highlights — 文本高亮
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

-- 6. echo_cards → highlights FK
ALTER TABLE echo_cards
    ADD CONSTRAINT fk_echo_cards_highlight
        FOREIGN KEY (highlight_id) REFERENCES highlights(id) ON DELETE SET NULL;

-- 7. rag_conversations — RAG 对话会话
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

-- 8. rag_messages — RAG 聊天消息
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

-- 9. user_milestones — 冷启动里程碑
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

-- 10. articles 新增列 (008)
ALTER TABLE articles
    ADD COLUMN highlight_count  INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN echo_card_count  INTEGER NOT NULL DEFAULT 0;

-- 11. categories upsert
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

-- NOTE: 跳过 article_embeddings (008 创建, 012 删除, 净效果为无)

-- ============================================
-- 009: highlights 补充索引
-- ============================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_highlights_unique
    ON highlights (article_id, user_id, start_offset, end_offset);

-- ============================================
-- 010: 订阅交易 ID
-- ============================================
ALTER TABLE users ADD COLUMN original_transaction_id TEXT;

CREATE UNIQUE INDEX idx_users_original_txn_id
    ON users (original_transaction_id)
    WHERE original_transaction_id IS NOT NULL;

-- ============================================
-- 011: 推送设备表
-- ============================================
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL DEFAULT 'ios',
    last_push_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, token)
);

CREATE INDEX idx_devices_user ON devices (user_id);

-- ============================================
-- 012: 智能检索
-- ============================================

-- semantic_keywords 列 + GIN 索引
ALTER TABLE articles ADD COLUMN semantic_keywords TEXT[] DEFAULT '{}';
CREATE INDEX idx_articles_semantic_keywords ON articles USING GIN (semantic_keywords);

-- summary trigram 索引
CREATE INDEX idx_articles_summary_trgm ON articles USING GIN (summary gin_trgm_ops);

-- 相关文章缓存表
CREATE TABLE article_relations (
    source_article_id  UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    related_article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    relevance_reason   TEXT,
    score              SMALLINT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_article_id, related_article_id)
);

CREATE INDEX idx_article_relations_source ON article_relations (source_article_id, score);

COMMIT;
