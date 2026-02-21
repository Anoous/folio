-- 001_init.up.sql — Folio 初始数据库结构

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================
-- 用户表
-- ============================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    apple_id        VARCHAR(255) UNIQUE,
    email           VARCHAR(255),
    nickname        VARCHAR(100),
    avatar_url      VARCHAR(500),

    subscription    VARCHAR(20) DEFAULT 'free',
    subscription_expires_at  TIMESTAMPTZ,

    monthly_quota   INTEGER DEFAULT 30,
    current_month_count INTEGER DEFAULT 0,
    quota_reset_at  TIMESTAMPTZ,

    preferred_language VARCHAR(10) DEFAULT 'zh',

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_apple_id ON users(apple_id);
CREATE INDEX idx_users_subscription ON users(subscription);

-- ============================================
-- 分类表
-- ============================================
CREATE TABLE categories (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug            VARCHAR(50) UNIQUE NOT NULL,
    name_zh         VARCHAR(50) NOT NULL,
    name_en         VARCHAR(50) NOT NULL,
    icon            VARCHAR(50),
    sort_order      INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO categories (slug, name_zh, name_en, icon, sort_order) VALUES
    ('tech',       '技术',   'Technology', 'cpu',              1),
    ('business',   '商业',   'Business',   'chart.bar',        2),
    ('science',    '科学',   'Science',    'atom',             3),
    ('culture',    '文化',   'Culture',    'book',             4),
    ('lifestyle',  '生活',   'Lifestyle',  'heart',            5),
    ('news',       '时事',   'News',       'newspaper',        6),
    ('education',  '学习',   'Education',  'graduationcap',    7),
    ('design',     '设计',   'Design',     'paintbrush',       8),
    ('other',      '其他',   'Other',      'ellipsis.circle',  9);

-- ============================================
-- 文章表
-- ============================================
CREATE TABLE articles (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    url             TEXT NOT NULL,
    title           VARCHAR(500),
    author          VARCHAR(200),
    site_name       VARCHAR(200),
    favicon_url     VARCHAR(500),
    cover_image_url VARCHAR(500),

    markdown_content TEXT,
    raw_html        TEXT,
    word_count      INTEGER DEFAULT 0,
    language        VARCHAR(10),

    category_id     UUID REFERENCES categories(id),
    summary         TEXT,
    key_points      JSONB DEFAULT '[]',
    ai_confidence   DECIMAL(3,2),

    status          VARCHAR(20) DEFAULT 'pending',
    source_type     VARCHAR(20) DEFAULT 'web',
    fetch_error     TEXT,
    retry_count     INTEGER DEFAULT 0,

    is_favorite     BOOLEAN DEFAULT FALSE,
    is_archived     BOOLEAN DEFAULT FALSE,
    read_progress   DECIMAL(3,2) DEFAULT 0.00,
    last_read_at    TIMESTAMPTZ,

    published_at    TIMESTAMPTZ,

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_articles_user_id ON articles(user_id);
CREATE INDEX idx_articles_status ON articles(status);
CREATE INDEX idx_articles_category ON articles(category_id);
CREATE INDEX idx_articles_source_type ON articles(source_type);
CREATE INDEX idx_articles_is_favorite ON articles(user_id, is_favorite) WHERE is_favorite = TRUE;
CREATE INDEX idx_articles_created_at ON articles(user_id, created_at DESC);
CREATE UNIQUE INDEX idx_articles_user_url ON articles(user_id, url);
CREATE INDEX idx_articles_title_trgm ON articles USING gin(title gin_trgm_ops);

-- ============================================
-- 标签表
-- ============================================
CREATE TABLE tags (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(50) NOT NULL,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    is_ai_generated BOOLEAN DEFAULT TRUE,
    article_count   INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_tags_user_name ON tags(user_id, name);
CREATE INDEX idx_tags_article_count ON tags(user_id, article_count DESC);

-- ============================================
-- 文章-标签关联表
-- ============================================
CREATE TABLE article_tags (
    article_id      UUID REFERENCES articles(id) ON DELETE CASCADE,
    tag_id          UUID REFERENCES tags(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (article_id, tag_id)
);

CREATE INDEX idx_article_tags_tag ON article_tags(tag_id);

-- ============================================
-- 抓取任务表
-- ============================================
CREATE TABLE crawl_tasks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id      UUID REFERENCES articles(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id),

    url             TEXT NOT NULL,
    source_type     VARCHAR(20),

    status          VARCHAR(20) DEFAULT 'queued',

    crawl_started_at  TIMESTAMPTZ,
    crawl_finished_at TIMESTAMPTZ,
    ai_started_at     TIMESTAMPTZ,
    ai_finished_at    TIMESTAMPTZ,

    error_message   TEXT,
    retry_count     INTEGER DEFAULT 0,

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_crawl_tasks_status ON crawl_tasks(status);
CREATE INDEX idx_crawl_tasks_user ON crawl_tasks(user_id);

-- ============================================
-- 用户操作日志表
-- ============================================
CREATE TABLE activity_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    action          VARCHAR(50) NOT NULL,
    article_id      UUID REFERENCES articles(id) ON DELETE SET NULL,
    metadata        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_activity_logs_user ON activity_logs(user_id, created_at DESC);

-- ============================================
-- 更新时间自动触发器
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_articles_updated_at
    BEFORE UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_crawl_tasks_updated_at
    BEFORE UPDATE ON crawl_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
