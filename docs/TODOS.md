# TODOS

## Active

### ReaderView hero/WebView bridge refactor
**What:** Full ReaderView architectural refactor separating hero transition, WebView bridge, and content display.
**Why:** ReaderView is 774 lines with tightly coupled state. Phase 2 menu/insights extraction only gets to ~500. The real complexity knot is the hero transition (line 48) and WebView bridge (line 263).
**Effort:** L (human: 2 weeks / CC: 1-2 hours)
**Priority:** P2
**Depends on:** Phase 2 ReaderView menu/insights extraction

### Investigate ReaderViewModel.persistProgressIfNeeded() dead code
**What:** Check if reading progress is being lost when leaving ReaderView. `persistProgressIfNeeded()` exists but has no call sites — either dead code or a missing lifecycle hook.
**Why:** If progress isn't persisted on view disappear, users lose their reading position.
**Effort:** S (human: 2 hours / CC: 15 min)
**Priority:** P1 (if progress is lost) / P3 (if dead code)
**Depends on:** Nothing

### Move ShareSheet to Components/
**What:** Extract ShareSheet from ReaderView.swift:725 to its own file. Currently used by HomeView:357, SettingsView:103, and ReaderView.
**Why:** Hidden coupling — extracting ReaderView subviews could accidentally break sharing in other views.
**Effort:** S (human: 30 min / CC: 5 min)
**Priority:** P3 — should be done before ReaderView extraction
**Depends on:** Nothing

### ViewModel-wide UserFacingError + ViewState migration
**What:** Migrate remaining ViewModels (AuthVM, SearchVM, etc.) to use UserFacingError protocol and ViewState<T> enum introduced in Phase 2.
**Why:** Phase 2 introduces these abstractions and migrates HomeVM + ReaderVM. Remaining VMs need migration to justify the abstraction.
**Effort:** M (human: 1 week / CC: 30 min)
**Priority:** P3
**Depends on:** Phase 2 completion (UserFacingError + ViewState<T> landed)
