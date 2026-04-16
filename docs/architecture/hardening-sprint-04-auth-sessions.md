# Hardening Sprint 04: Revocable Auth Sessions

## Date

2026-04-16

## Goal

Upgrade refresh-token handling from a long-lived self-contained JWT into a revocable, rotation-safe session model without breaking the existing client contract:

- `POST /api/v1/auth/apple`
- `POST /api/v1/auth/email/verify`
- `POST /api/v1/auth/refresh`

The API response shape remains:

- `access_token`
- `refresh_token`
- `expires_in`
- `user`

## Current Problem

The current refresh token is a 90-day JWT signed only with the global secret. That has three production problems:

1. It cannot be revoked per device/session.
2. It does not rotate, so replayed stolen tokens remain valid until expiry.
3. Compromise response is global and blunt: rotate `JWT_SECRET` and invalidate everyone.

## Design

### Access token

Keep access tokens as short-lived JWTs:

- signed with the existing `JWT_SECRET`
- 2 hour TTL
- contains `uid`
- now also carries `sid` for observability and future policy hooks

Access tokens remain stateless for request authentication.

### Refresh token

Replace refresh JWTs with opaque session-bound tokens:

- format: `<session_id>.<secret>`
- `session_id`: UUID
- `secret`: 32 random bytes, base64url encoded without padding

The server stores only `sha256(secret)` in Postgres, never the raw secret.

### Session persistence

Add a `refresh_sessions` table:

- `id UUID PRIMARY KEY`
- `user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`
- `token_hash TEXT NOT NULL`
- `expires_at TIMESTAMPTZ NOT NULL`
- `last_used_at TIMESTAMPTZ`
- `rotated_at TIMESTAMPTZ`
- `revoked_at TIMESTAMPTZ`
- `replaced_by_token_hash TEXT`
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

Indexes:

- unique on `(id)`
- unique on `token_hash`
- index on `(user_id, revoked_at)`
- index on `(expires_at)`

### Rotation algorithm

On login:

1. create a new session row
2. mint refresh token from `session_id + secret`
3. return access JWT + refresh token

On refresh:

1. parse `session_id` and `secret`
2. hash `secret`
3. atomically rotate the session row with compare-and-swap semantics:
   - match `id`
   - match current `token_hash`
   - require `revoked_at IS NULL`
   - require `expires_at > NOW()`
4. set:
   - `token_hash = new_hash`
   - `replaced_by_token_hash = new_hash`
   - `rotated_at = NOW()`
   - `last_used_at = NOW()`
   - `expires_at = NOW() + refresh_ttl`
5. return a new access JWT and a new refresh token

This makes the old refresh token invalid immediately.

### Reuse detection

If a refresh token references an existing live session but the secret hash does not match, treat that as reuse of a stale or stolen token:

1. revoke the session row
2. deny the refresh request

This is intentionally strict. It forces re-authentication after refresh-token replay instead of silently allowing the newer holder to continue indefinitely.

### Revocation

Add service-level session revocation and expose a public endpoint:

- `POST /api/v1/auth/logout`

Request:

- `refresh_token`

Behavior:

- parse the refresh token
- revoke the matching session if it exists
- return `204 No Content`

This keeps revocation independent from access-token lifetime.

## Non-Goals

- No full access-token introspection on every request.
- No multi-session management UI yet.
- No device metadata capture in this sprint.
- No Redis-based auth/session cache.

## Compatibility

### iOS client

The client continues to receive the same auth payload fields. It does not need to know whether the refresh token is JWT or opaque.

### Existing access token validation

`JWTAuth` middleware continues to validate short-lived access JWTs exactly as before.

### E2E helpers

Python E2E helpers that currently mint refresh JWTs directly must be updated to insert `refresh_sessions` rows and generate opaque refresh tokens matching server semantics.

## Test Strategy

### Service tests

- login issues access token plus persisted refresh session
- refresh rotates token and invalidates the old one
- replaying the old token revokes the session
- revoked session cannot refresh
- expired session cannot refresh
- logout revokes the session

### Repository tests

Covered indirectly through service tests using a real Postgres-backed repository.

### E2E auth tests

- refresh success still returns a new token pair
- invalid token still returns 403
- missing token still returns 400

## Rollout Notes

- Access token TTL remains unchanged, so request-path auth behavior stays stable.
- Session revocation affects refresh only; already-issued access tokens remain valid until their 2 hour expiry.
- This is acceptable for this sprint and materially better than the current 90 day irrevocable token model.
