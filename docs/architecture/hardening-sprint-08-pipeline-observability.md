# Hardening Sprint 08: Pipeline Error Taxonomy and Observability

## Problem

The article ingestion pipeline already has logs, but failures are still operationally opaque.

Current behavior:

- `reader`, `jina`, and `ai` clients mostly return free-form `error` strings.
- `crawl_tasks` persists only `error_message`.
- worker logs are readable by humans but not easy to aggregate by failure class.
- fallback behavior (`reader -> jina`) is not measurable as a first-class signal.

That is sufficient for debugging a single request, but not for production operations.

We cannot answer basic questions reliably:

- which stage is failing most often
- which provider is failing
- whether failures are retryable
- whether the failure was `timeout`, `network`, `empty_content`, `rate_limited`, or `invalid_response`
- how often `jina` is rescuing failed `reader` attempts

## Scope

This sprint hardens the ingestion pipeline only:

- `crawl -> reader -> jina -> ai analyze`

Out of scope for this sprint:

- `rag`
- `echo`
- `related articles`
- user-facing API contract changes unrelated to ingestion

## Decisions

### 1. Introduce one shared pipeline error model

Pipeline-facing external dependency failures must be represented as a typed internal error instead of raw strings.

Base dimensions:

- `stage`
- `provider`
- `code`
- `retryable`
- `status_code`
- `message`
- `cause`

Initial stages:

- `crawl_reader`
- `crawl_jina`
- `ai_analyze`

Initial providers:

- `reader`
- `jina`
- `deepseek`

Initial codes:

- `invalid_request`
- `blocked_target`
- `timeout`
- `network`
- `rate_limited`
- `upstream_4xx`
- `upstream_5xx`
- `empty_content`
- `invalid_response`
- `internal`

### 2. Reader-service must expose a stable machine-readable error contract

`reader-service` is currently the first boundary in the crawl path.
Its error body must become structured so the Go client can classify failures without brittle string parsing.

Stable response body:

```json
{
  "error": "human readable message",
  "code": "timeout",
  "provider": "reader",
  "retryable": true
}
```

Initial contract:

- malformed request body -> `400 invalid_request`
- blocked URL / SSRF rejection -> `400 blocked_target`
- extraction returned no markdown -> `422 empty_content`
- upstream timeout -> `504 timeout`
- upstream network failure -> `502 network`
- unclassified internal failure -> `502 internal`

### 3. Classification belongs at the dependency boundary

The client nearest to the external dependency is responsible for error classification.

That means:

- `ReaderClient` classifies `reader-service` responses and transport errors
- `JinaClient` classifies Jina transport/status/decode failures
- `DeepSeekAnalyzer` classifies AI transport/status/decode failures

Workers should consume typed errors, persist the structured fields, and emit structured logs.
Workers should not reverse-engineer strings.

### 4. Fallbacks are an outcome, not just a log line

`reader` failure followed by `jina` success is not a normal success path.
It is a fallback success and must be measurable separately from direct success.

This sprint introduces the error model and contract first.
Worker metrics and persistence changes follow immediately after.

## Implementation Plan

### Phase 1: Foundation

- add `internal/pipeline/error.go`
- add tests for error wrapping and extraction
- harden `reader-service` error body contract
- update `ReaderClient` to parse the structured error body
- add `ReaderClient` unit tests

### Phase 2: Worker integration

- extend `crawl_tasks` with structured failure metadata
- update `TaskRepo.SetFailed(...)`
- update crawl/AI workers to persist structured fields

### Phase 3: Lightweight observability

- standardize worker log events:
  - `pipeline_started`
  - `pipeline_succeeded`
  - `pipeline_failed`
  - `pipeline_fallback_started`
  - `pipeline_fallback_succeeded`
- standardize searchable log fields:
  - `pipeline_stage`
  - `provider`
  - `error_code`
  - `retryable`
  - `status_code`
  - `duration_ms`
  - `task_id`
  - `article_id`
  - `user_id`
  - `url_host`
  - `fallback_from`
  - `fallback_to`
- keep logs lean:
  - no article body
  - no raw upstream response body
  - no full URL when host is sufficient

Prometheus metrics are intentionally deferred for now to keep operational cost low.

## Testing Strategy

1. `reader-service` tests must assert status code and structured error body.
2. `ReaderClient` tests must assert typed pipeline errors for:
   - blocked target
   - timeout
   - network failure
   - invalid response body
3. `JinaClient` and `DeepSeekAnalyzer.Analyze` tests must assert typed pipeline errors for:
   - timeout
   - network failure
   - upstream non-200
   - invalid response body
4. Full regressions must remain green:
   - `go test ./...`
   - `npm test`
   - `./scripts/run_e2e.sh`

## Expected Outcome

- pipeline failures become machine-classifiable
- `reader-service` and Go client stop depending on brittle string matching
- logs become greppable by `stage/provider/code/retryable` without adding a metrics stack yet
