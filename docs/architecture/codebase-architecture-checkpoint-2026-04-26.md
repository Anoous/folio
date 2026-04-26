# Codebase Architecture Checkpoint: Pipeline Module Deepening

Date: 2026-04-26

## Summary

This checkpoint records the backend architecture state after the pipeline and knowledge-service Module deepening pass.

The main outcome is that the crawl, AI, knowledge, and retry flows now have thin orchestration methods with deeper Modules behind explicit seams. The important behavior is covered at each Module interface: cache hits, task state ordering, fallback provider choice, AI failure handling, source collection, citation grounding, and retry task selection.

## Deepened Modules

### Crawl Pipeline

- `CrawlHandler.ProcessTask` is now a coordinator.
- Deep Modules now own cache handling, existing-content routing, Reader/Jina fetching, content postprocessing, AI handoff, and fetched-content completion.
- Task ordering rules are tested directly, especially cases where crawl must finish before enqueueing AI.

### AI Pipeline

- `AIHandler.ProcessTask` is now a coordinator.
- Deep Modules now own AI analysis execution, category fallback, AI result persistence, title backfill, tag application, content-cache writing, and follow-up enqueueing.
- Failure handling is concentrated around the Module that owns the side effect, instead of being spread through the handler.

### Knowledge Partner

- Evidence retrieval is owned by `EvidenceService`.
- Ask answer composition, Spark source collection, and Learn context collection have dedicated Modules.
- Grounding and citation rules are tested at the composer/grounding interfaces.

### Article Retry

- Failed-article retry is owned by `articleRetryWorkflow`.
- The retry Module owns status reset, task creation, and queue selection between crawl and AI processing.

## Verification

After the refactor series:

- `go test ./...` passes.
- Full e2e passes: 97 tests.
- `server/reader-service/package-lock.json` remains unchanged after e2e runs.

## Current Stop Line

Further splitting the remaining `auth` and `stats` services is intentionally deferred.

Reasons:

- `auth` contains protocol-heavy code around JWT, Apple JWKS, Redis verification codes, and refresh-session rotation. Its next improvement should be driven by a concrete correctness or security review, not by mechanical splitting.
- `stats` is mostly SQL aggregation and small formatting logic. Its best next improvement is likely repository/query test coverage, not more service-layer Modules.
- The highest-value ingestion, AI, knowledge, and retry flows now have adequate locality and test surfaces.

## Next Architectural Candidates

1. Auth correctness review: refresh-token rotation, Apple JWKS cache behavior, Redis verification-code attempt limits.
2. Stats query hardening: move SQL aggregation behind tested query Modules only if product requirements expand.
3. Test fixture cleanup: consolidate repeated recording/mock helpers if they begin to slow down future changes.
