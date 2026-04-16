# Hardening Sprint 06: E2E Stability and API Semantics

## Problem

The default end-to-end suite was green only as long as three unstable assumptions held:

1. Soft-deleted articles were still readable by `GET /api/v1/articles/{id}`.
2. Function-scoped E2E clients reused the same synthetic user, so long test runs consumed the same monthly quota bucket.
3. Reader and AI quality tests depended on public internet scraping succeeding in the current environment.

That is no longer acceptable after the SSRF hardening work:

- `reader-service` now blocks targets that resolve into reserved ranges.
- In this local E2E environment, public DNS names resolve into `198.18.0.0/15`, so direct Reader success is intentionally impossible.
- Jina fallback is still external and subject to rate limits, so default E2E cannot depend on repeated public scrapes.

## Decisions

### 1. Treat deleted articles as not found on direct reads

Soft delete remains the storage model because incremental sync still needs tombstones via `GET /articles?updated_since=...`.
But direct article reads, updates, retries, and deletes should behave as if deleted content no longer exists.

Decision:

- Keep `deleted_at` in storage.
- Keep deleted rows visible only in incremental sync list queries.
- Return `ErrNotFound` from article service methods when `deleted_at` is set.

### 2. Isolate E2E users per test when test semantics require freshness

`fresh_api` must mean a fresh identity, not just a fresh HTTP client.

Decision:

- Session fixtures may keep a shared user.
- Function-scoped `fresh_api` gets a unique synthetic alias every test.

### 3. Make default E2E deterministic

Default E2E should validate product behavior, not the public internet.

Decision:

- AI quality tests submit URL records with client-provided `markdown_content`, so the pipeline still exercises `SubmitURL -> CrawlTask -> AIProcessTask` without Reader/Jina dependency.
- Direct Reader E2E covers health and input-validation/security contracts, not public-page extraction success.
- Public-page extraction remains covered by reader-service unit tests and optional targeted/manual verification.

### 4. Fix pytest marker hygiene

Decision:

- Use `--strict-markers` in `addopts`.
- Remove deprecated/unknown `strict_markers` config key.

## Implementation Plan

1. Update article service semantics for deleted rows.
2. Add service tests for deleted article behavior.
3. Change `fresh_api` to create a unique user per test.
4. Extend E2E API helper to submit prefilled URL content.
5. Rewrite AI quality E2E to use deterministic markdown fixtures.
6. Rewrite Reader E2E to assert current validation/security behavior.
7. Rerun focused failing suites, then rerun full E2E.

## Expected Outcome

- Deleted articles disappear from direct reads.
- Default E2E no longer burns one shared monthly quota bucket.
- Reader/AI tests stop failing due to external DNS, Jina quota, or public site variability.
- Full `./scripts/run_e2e.sh` becomes repeatable in local and CI-like environments.
