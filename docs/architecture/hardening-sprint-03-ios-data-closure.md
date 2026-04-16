# Hardening Sprint 03: iOS Data Closure

## Date

2026-04-15

## Goal

Close three remaining client-side production gaps that still make the app feel like a toy under failure or cross-session use:

1. Pending StoreKit subscription verifications are persisted but not replayed on app startup.
2. Local full-text search (FTS5) is rebuilt only on search page init, so writes, deletes, OCR completion, and sync merges drift out of sync.
3. Failed screenshot and voice-note articles retry through the wrong API path.

This sprint is intentionally narrow. It does not redesign purchase architecture or search ranking. It closes correctness gaps in the current design.

## Non-Goals

- No redesign of server-side subscription/session model.
- No semantic search changes.
- No background OCR pipeline redesign.
- No UI changes.

## Current Problems

### 1. Subscription compensation is incomplete

`SubscriptionManager.retryPendingVerifications()` exists, but app startup does not invoke it. A transient server outage during purchase can leave App Store entitlement and server subscription state diverged indefinitely.

### 2. FTS index has no write-side consistency model

The search page rebuilds the index when `SearchViewModel` initializes, but core write paths do not notify the index:

- save URL
- save manual content
- save voice note
- screenshot OCR completion
- local extraction completion
- local delete
- sync merge / reconciliation / polling updates

This creates a production-visible inconsistency: an article can appear in the feed but remain unsearchable until the user re-enters search or rebuilds implicitly.

### 3. Retry semantics diverge from submit semantics

`SyncService.submitPendingArticles()` correctly treats `manual`, `screenshot`, and `voice` as text-only content submitted to `/articles/manual`.

`HomeViewModel.retryArticle()` only special-cases `.manual`, so failed screenshot/voice retries fall through to URL submission, which is wrong for URL-less content.

## Design

### A. Startup compensation via a small coordinator

Introduce a lightweight startup coordinator for subscription boot tasks. It will:

1. fetch products
2. refresh local entitlements
3. replay pending server verifications
4. start StoreKit transaction listener

This keeps `FolioApp` thin and gives the startup sequence a unit-testable seam.

### B. Search index consistency via a dedicated coordinator

Introduce a `SearchIndexCoordinator` responsible for all FTS index mutations. The coordinator will own a `FTS5SearchManager` and expose:

- `index(_ article:)`
- `update(_ article:)`
- `remove(articleID:)`
- `rebuild(context:)`

Usage model:

- Local immediate writes use targeted `index/update/remove`
- Sync-heavy paths use `rebuild(context:)` after batch merges/reconciliation

This is a deliberate trade-off:

- targeted updates keep save/delete paths cheap
- batch rebuilds keep sync code simple and reduce missed edge cases

### C. Align retry path with submit path

`HomeViewModel.retryArticle()` must mirror `SyncService.submitPendingArticles()`:

- `manual`, `screenshot`, `voice` -> `/api/v1/articles/manual`
- client-extracted URL content -> enriched `/api/v1/articles`
- raw URL -> simple URL submit

The retry code must also pass `sourceType` so the server can preserve correct provenance.

## Touch Points

### New

- `ios/Folio/App/AppStartupCoordinator.swift`
- `ios/Folio/Data/Search/SearchIndexCoordinator.swift`

### Updated

- `ios/Folio/App/FolioApp.swift`
- `ios/Folio/Data/Subscription/SubscriptionManager.swift`
- `ios/Folio/Data/SwiftData/SharedDataManager.swift`
- `ios/Folio/Data/ContentSaveService.swift`
- `ios/Folio/Data/Sync/SyncService.swift`
- `ios/Folio/Domain/Models/Article+Actions.swift`
- `ios/Folio/Presentation/Home/HomeViewModel.swift`

### Tests

- `ios/FolioTests/App/AppStartupCoordinatorTests.swift`
- `ios/FolioTests/Data/ContentSaveServiceTests.swift`
- `ios/FolioTests/Data/SharedDataManagerExtractionTests.swift`
- `ios/FolioTests/ViewModels/HomeViewModelTests.swift`

## Correctness Invariants

After this sprint:

1. A persisted pending subscription verification is retried on next app launch.
2. A locally saved or updated article becomes searchable without requiring a search page rebuild.
3. A locally deleted article is removed from search immediately.
4. Sync merges and server-driven deletions cannot leave stale search rows behind.
5. Screenshot and voice retry use manual-content submission even when `url == nil`.

## Test Strategy

### Startup

- Unit test the startup coordinator invokes retry replay in the startup sequence.

### Search index

- Extraction update refreshes indexed content/title.
- Voice save creates a searchable row immediately.
- Delete removes the row from FTS.

### Retry semantics

- Failed screenshot retry hits `/api/v1/articles/manual` and includes `source_type`.
- Failed voice retry hits `/api/v1/articles/manual` and includes `source_type`.

## Rollout Notes

- Keep the existing `SearchViewModel.rebuildIndex()` for now as a defensive fallback.
- This sprint improves correctness first; later optimization can reduce rebuild frequency if needed.
