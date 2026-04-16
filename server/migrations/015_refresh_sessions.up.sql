CREATE TABLE refresh_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    last_used_at TIMESTAMPTZ,
    rotated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    replaced_by_token_hash TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_sessions_user_active
    ON refresh_sessions (user_id, revoked_at);

CREATE INDEX idx_refresh_sessions_expires_at
    ON refresh_sessions (expires_at);

CREATE TRIGGER tr_refresh_sessions_updated_at
    BEFORE UPDATE ON refresh_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
