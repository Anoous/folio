CREATE TABLE content_cache (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    url              TEXT NOT NULL UNIQUE,
    title            VARCHAR(500),
    author           VARCHAR(200),
    site_name        VARCHAR(200),
    favicon_url      VARCHAR(500),
    cover_image_url  VARCHAR(500),
    markdown_content TEXT,
    word_count       INTEGER DEFAULT 0,
    language         VARCHAR(10),
    published_at     TIMESTAMPTZ,
    category_slug    VARCHAR(50),
    summary          TEXT,
    key_points       JSONB DEFAULT '[]',
    ai_confidence    DECIMAL(3,2),
    ai_tag_names     TEXT[] DEFAULT '{}',
    crawled_at       TIMESTAMPTZ,
    ai_analyzed_at   TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER update_content_cache_updated_at
    BEFORE UPDATE ON content_cache
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
