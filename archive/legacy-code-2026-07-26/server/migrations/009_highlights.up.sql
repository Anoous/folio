CREATE TABLE IF NOT EXISTS highlights (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    start_offset INTEGER NOT NULL,
    end_offset INTEGER NOT NULL,
    color VARCHAR(20) NOT NULL DEFAULT 'accent',
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_highlights_unique ON highlights (article_id, user_id, start_offset, end_offset);
CREATE INDEX IF NOT EXISTS idx_highlights_article ON highlights (article_id, user_id);
CREATE INDEX IF NOT EXISTS idx_highlights_user ON highlights (user_id, created_at DESC);
