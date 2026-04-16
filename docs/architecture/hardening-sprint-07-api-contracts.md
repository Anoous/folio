# Hardening Sprint 07: API Contract Validation

## Problem

Several path-parameter endpoints accepted arbitrary strings and let invalid UUIDs fall through to the repository layer.
That produced PostgreSQL `22P02` errors and leaked outward as `500 Internal Server Error`.

This was incorrect for three reasons:

1. The request is invalid before any business logic runs.
2. The API contract became inconsistent across endpoints.
3. Tests could pass while production still exposed database parsing behavior to clients.

## Scope

This sprint hardens request-contract validation only. It does not change crawl/AI behavior.

Endpoints covered:

- `GET/PUT/DELETE/POST retry /api/v1/articles/{id}`
- `GET /api/v1/tasks/{id}`
- `DELETE /api/v1/tags/{id}`
- `GET /api/v1/articles/{id}/related`
- `POST/GET /api/v1/articles/{id}/highlights`
- `DELETE /api/v1/highlights/{id}`
- `POST /api/v1/echo/{id}/review`

## Decisions

### 1. Reject malformed UUIDs at the handler boundary

All malformed route IDs should return `400 Bad Request`.

Rationale:

- malformed ID: client contract error
- valid UUID but missing resource: `404`
- valid UUID owned by another user: existing endpoint semantics remain unchanged

### 2. Use one shared helper

UUID validation must not be copy-pasted per handler.

Shared helper behavior:

- missing param -> `400`
- malformed UUID -> `400`
- valid UUID -> continue

### 3. Preserve existing business semantics for valid IDs

This sprint does not alter:

- soft-delete incremental sync behavior
- forbidden/not found masking decisions
- related-articles behavior for nonexistent but valid UUIDs

## Testing Strategy

1. Handler unit tests verify invalid IDs return `400` before any service/repository call.
2. E2E edge-case tests verify public API behavior for malformed article/task/tag/related IDs.
3. Full server + reader + E2E regression must remain green.

## Expected Outcome

- No malformed UUID should reach PostgreSQL.
- API error semantics become predictable and production-safe.
- Future path-ID endpoints can reuse the same helper instead of reintroducing `500` regressions.
