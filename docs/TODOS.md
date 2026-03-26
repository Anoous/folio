# TODOS

## Active

### ReaderView hero/WebView bridge refactor
**What:** Full ReaderView architectural refactor separating hero transition, WebView bridge, and content display.
**Why:** ReaderView is 619 lines after Phase 2 menu/insights extraction. The remaining complexity knot is the hero transition and WebView bridge.
**Effort:** L (human: 2 weeks / CC: 1-2 hours)
**Priority:** P2
**Depends on:** Nothing (Phase 2 prereqs complete)

### ViewModel-wide UserFacingError + ViewState migration
**What:** Migrate remaining ViewModels (AuthVM, SearchVM, etc.) to use UserFacingError protocol and ViewState<T> enum introduced in Phase 2.
**Why:** Phase 2 introduced these abstractions and migrated HomeVM + ReaderVM. Remaining VMs need migration to justify the abstraction.
**Effort:** M (human: 1 week / CC: 30 min)
**Priority:** P3
**Depends on:** Phase 2 completion (done)

## Completed

### ~~Investigate ReaderViewModel.persistProgressIfNeeded() dead code~~
**Resolved:** Phase 2 Batch 1 — wired `persistProgressIfNeeded()` to `ReaderView.onDisappear`. Was a real bug (reading progress lost on navigate back). Fixed in commit `c67a1a5`.

### ~~Move ShareSheet to Components/~~
**Resolved:** Phase 2 Batch 3 — extracted to `ios/Folio/Presentation/Components/ShareSheet.swift`. Fixed in commit `0a17e15`.
