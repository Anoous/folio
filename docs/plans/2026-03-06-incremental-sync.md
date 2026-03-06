# Incremental Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure iOS client and server stay in sync — full sync on login, incremental sync on foreground, polling while articles are processing.

**Architecture:** Server adds `updated_since` query param to `GET /articles`. iOS stores `lastSyncedAt` in UserDefaults, passes it on every sync. SyncService gains `incrementalSync()` that fetches only changed articles. HomeView triggers sync on appear/foreground, and polls while any article is processing.

**Tech Stack:** Go (chi, pgx), Swift (SwiftUI, SwiftData, Combine)

---

### Task 1: Server — add `updated_since` filter to ListArticles

**Files:**
- Modify: `server/internal/repository/article.go:83-90` (ListArticlesParams)
- Modify: `server/internal/repository/article.go:97-151` (ListByUser query)
- Modify: `server/internal/api/handler/article.go:73-120` (HandleListArticles)

**Step 1: Add `UpdatedSince` to ListArticlesParams**

In `server/internal/repository/article.go`, add a field to the params struct:

```go
type ListArticlesParams struct {
	UserID       string
	Category     *string
	Status       *domain.ArticleStatus
	Favorite     *bool
	UpdatedSince *time.Time  // NEW
	Page         int
	PerPage      int
}
```

**Step 2: Add WHERE clause to both count and query in ListByUser**

After the existing `Favorite` filter blocks in `ListByUser`, add:

```go
if p.UpdatedSince != nil {
    countQuery += fmt.Sprintf(` AND updated_at > $%d`, argIdx)
    args = append(args, *p.UpdatedSince)
    argIdx++
}
```

And the same pattern for `query`/`queryArgs`/`qArgIdx`.

**Step 3: Parse `updated_since` query param in handler**

In `server/internal/api/handler/article.go` `HandleListArticles`, after the `favorite` param block:

```go
if since := r.URL.Query().Get("updated_since"); since != "" {
    if t, err := time.Parse(time.RFC3339, since); err == nil {
        params.UpdatedSince = &t
    }
}
```

Add `"time"` to the import block if not present.

**Step 4: Test manually**

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/dev -H "Content-Type: application/json" -d '{}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# All articles
curl -s "http://localhost:8080/api/v1/articles" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['pagination']['total'])"

# Articles updated since a future date — should return 0
curl -s "http://localhost:8080/api/v1/articles?updated_since=2099-01-01T00:00:00Z" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['pagination']['total'])"

# Articles updated since epoch — should return all
curl -s "http://localhost:8080/api/v1/articles?updated_since=2000-01-01T00:00:00Z" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['pagination']['total'])"
```

**Step 5: Commit**

```bash
git add server/internal/repository/article.go server/internal/api/handler/article.go
git commit -m "feat(server): add updated_since filter to ListArticles API"
```

---

### Task 2: iOS — add `updatedSince` param to APIClient.listArticles

**Files:**
- Modify: `ios/Folio/Data/Network/Network.swift:440-461` (listArticles method)

**Step 1: Add `updatedSince` parameter**

```swift
func listArticles(
    page: Int = 1,
    perPage: Int = 20,
    category: String? = nil,
    status: String? = nil,
    favorite: Bool? = nil,
    updatedSince: Date? = nil  // NEW
) async throws -> ListResponse<ArticleDTO> {
    var queryItems = [
        URLQueryItem(name: "page", value: "\(page)"),
        URLQueryItem(name: "per_page", value: "\(perPage)")
    ]
    if let category {
        queryItems.append(URLQueryItem(name: "category", value: category))
    }
    if let status {
        queryItems.append(URLQueryItem(name: "status", value: status))
    }
    if let favorite {
        queryItems.append(URLQueryItem(name: "favorite", value: favorite ? "true" : "false"))
    }
    if let updatedSince {
        let formatter = ISO8601DateFormatter()
        queryItems.append(URLQueryItem(name: "updated_since", value: formatter.string(from: updatedSince)))
    }
    return try await request(method: "GET", path: "/api/v1/articles", queryItems: queryItems)
}
```

**Step 2: Commit**

```bash
git add ios/Folio/Data/Network/Network.swift
git commit -m "feat(ios): add updatedSince param to listArticles API"
```

---

### Task 3: iOS — rewrite SyncService with incremental sync

**Files:**
- Modify: `ios/Folio/Data/Sync/SyncService.swift`

This is the core change. Replace the single `syncArticles()` method with:
1. `fullSync()` — paginated fetch of ALL articles (for first login / reinstall)
2. `incrementalSync()` — fetch only articles updated since `lastSyncedAt`
3. Store `lastSyncedAt` in UserDefaults

**Step 1: Add lastSyncedAt storage**

Add at the top of SyncService, inside the class:

```swift
private static let lastSyncedAtKey = "com.folio.lastSyncedAt"

private var lastSyncedAt: Date? {
    get { UserDefaults.standard.object(forKey: Self.lastSyncedAtKey) as? Date }
    set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncedAtKey) }
}
```

**Step 2: Replace `syncArticles()` with paginated full sync**

Replace the existing `syncArticles()` method:

```swift
private func syncArticles() async {
    if lastSyncedAt == nil {
        await fullSyncArticles()
    } else {
        await incrementalSyncArticles()
    }
}

private func fullSyncArticles() async {
    FolioLogger.sync.info("starting full article sync")
    let merger = ArticleMerger(context: context)
    var page = 1
    let perPage = 50

    do {
        while true {
            let response = try await apiClient.listArticles(page: page, perPage: perPage)
            for dto in response.data {
                try? merger.merge(dto: dto)
            }
            try? context.save()

            let fetched = (page - 1) * perPage + response.data.count
            if fetched >= response.pagination.total {
                break
            }
            page += 1
        }
        lastSyncedAt = Date()
        FolioLogger.sync.info("full sync completed")
    } catch {
        FolioLogger.sync.error("full article sync failed: \(error)")
    }
}

private func incrementalSyncArticles() async {
    guard let since = lastSyncedAt else {
        await fullSyncArticles()
        return
    }
    FolioLogger.sync.debug("incremental sync since \(since)")
    let merger = ArticleMerger(context: context)
    var page = 1
    let perPage = 50

    do {
        while true {
            let response = try await apiClient.listArticles(
                page: page, perPage: perPage, updatedSince: since
            )
            for dto in response.data {
                try? merger.merge(dto: dto)
            }
            try? context.save()

            let fetched = (page - 1) * perPage + response.data.count
            if fetched >= response.pagination.total {
                break
            }
            page += 1
        }
        lastSyncedAt = Date()
    } catch {
        FolioLogger.sync.error("incremental sync failed: \(error)")
    }
}
```

**Step 3: Add public `incrementalSync()` for foreground triggers**

Add a new public method:

```swift
func incrementalSync() async {
    await incrementalSyncArticles()
    await fetchProcessingArticles()
}
```

**Step 4: Add processing article polling**

Add a method to find locally-processing articles and fetch their latest status:

```swift
func fetchProcessingArticles() async {
    let descriptor = FetchDescriptor<Article>(
        predicate: #Predicate<Article> {
            $0.statusRaw == "processing" || $0.statusRaw == "clientReady"
        }
    )
    guard let processing = try? context.fetch(descriptor), !processing.isEmpty else { return }

    FolioLogger.sync.debug("fetching \(processing.count) processing articles")
    for article in processing {
        guard let serverID = article.serverID else { continue }
        do {
            let dto = try await apiClient.getArticle(id: serverID)
            article.updateFromDTO(dto)
            let merger = ArticleMerger(context: context)
            try merger.resolveRelationships(for: article, from: dto)
        } catch {
            continue
        }
    }
    try? context.save()
}
```

**Step 5: Commit**

```bash
git add ios/Folio/Data/Sync/SyncService.swift
git commit -m "feat(ios): incremental sync with lastSyncedAt + processing article polling"
```

---

### Task 4: iOS — trigger sync on foreground and on login

**Files:**
- Modify: `ios/Folio/App/FolioApp.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

**Step 1: In FolioApp, store syncService as @State and trigger on scenePhase**

In `FolioApp.swift`, ensure `syncService` is accessible and add a `.onChange(of: scenePhase)` handler. Find where `scenePhase` is declared (or add `@Environment(\.scenePhase) private var scenePhase`) and add:

```swift
.onChange(of: scenePhase) { _, newPhase in
    if newPhase == .active, authViewModel.authState == .signedIn {
        if let sync = syncService {
            Task { await sync.incrementalSync() }
        }
    }
}
```

**Step 2: In HomeView, remove the manual `refreshFromServer` calls we added earlier**

In `HomeView.swift`, remove the two `Task { await viewModel?.refreshFromServer() }` calls we added in `.onAppear` and `.onChange(of: authViewModel?.isAuthenticated)`. The sync is now handled at the app level by SyncService. Keep the `viewModel?.fetchArticles()` calls (they read from local SwiftData).

The `.refreshable` pull-to-refresh should trigger incremental sync. Change it to:

Find the `.refreshable` block in `articleList` and update it. HomeView needs access to SyncService. Add to HomeView:

```swift
@Environment(SyncService.self) private var syncService: SyncService?
```

Then update refreshable:

```swift
.refreshable {
    if let syncService {
        await syncService.incrementalSync()
    }
    viewModel?.fetchArticles()
}
```

**Step 3: Ensure SyncService is in the environment**

In `FolioApp.swift`, wherever the sync service is created, make sure it's passed into the environment:

```swift
.environment(syncService)
```

This requires making SyncService `@Observable`. Add `@Observable` to the class declaration:

```swift
@MainActor
@Observable
final class SyncService {
```

**Step 4: Commit**

```bash
git add ios/Folio/App/FolioApp.swift ios/Folio/Presentation/Home/HomeView.swift ios/Folio/Data/Sync/SyncService.swift
git commit -m "feat(ios): trigger sync on foreground, login, and pull-to-refresh"
```

---

### Task 5: iOS — auto-poll while processing articles exist

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

**Step 1: Add a timer that polls while any article has processing status**

In the `articleList` view or the main `body`, add a `.task` modifier that watches for processing articles:

```swift
.task(id: articles.contains { $0.status == .processing || $0.status == .clientReady }) {
    guard articles.contains(where: { $0.status == .processing || $0.status == .clientReady }) else { return }
    // Poll every 5 seconds while processing articles exist
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { break }
        await syncService?.fetchProcessingArticles()
        viewModel?.fetchArticles()
    }
}
```

The `task(id:)` modifier will cancel and restart whenever the condition changes, so polling stops automatically when all articles are ready.

**Step 2: Commit**

```bash
git add ios/Folio/Presentation/Home/HomeView.swift
git commit -m "feat(ios): auto-poll processing articles every 5s"
```

---

### Task 6: Build verify + manual test

**Step 1: Rebuild Go server**

```bash
cd server && go build ./cmd/server
```

**Step 2: Regenerate Xcode project and build**

```bash
cd ios && xcodegen generate
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'
```

**Step 3: Manual test flow**

1. Start dev backend (`./scripts/dev-start.sh`)
2. Delete app from simulator
3. Run app, tap Dev Login
4. Verify: articles appear automatically (full sync)
5. Submit a new URL via the + button
6. Verify: article appears as "processing", then updates to "ready" automatically (polling)
7. Background the app, wait 10s, foreground
8. Verify: no visible change (incremental sync ran, but no new data)
9. Pull-to-refresh — verify it works

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: incremental sync — full sync on login, incremental on foreground, auto-poll processing"
```
