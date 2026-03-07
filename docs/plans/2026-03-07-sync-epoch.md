# Sync Epoch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a sync epoch mechanism so the iOS client detects server-side data resets and purges stale local articles.

**Architecture:** The `users` table gets a `sync_epoch` integer column (default 1). The server returns `sync_epoch` in both the auth response (login/refresh) and the list articles response. The iOS client stores `lastEpoch` locally; when the server epoch differs, the client purges all locally-synced articles (preserving pending/clientReady), resets `lastSyncedAt`, and performs a full sync.

**Tech Stack:** Go (migration + domain + handler), Swift (SyncService + DTOs)

---

### Task 1: Database Migration — Add `sync_epoch` to `users`

**Files:**
- Create: `server/migrations/003_sync_epoch.up.sql`
- Create: `server/migrations/003_sync_epoch.down.sql`

**Step 1: Write the up migration**

```sql
-- 003_sync_epoch.up.sql
ALTER TABLE users ADD COLUMN sync_epoch INTEGER NOT NULL DEFAULT 1;
```

**Step 2: Write the down migration**

```sql
-- 003_sync_epoch.down.sql
ALTER TABLE users DROP COLUMN IF EXISTS sync_epoch;
```

**Step 3: Apply migration to dev database**

Run:
```bash
docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "ALTER TABLE users ADD COLUMN sync_epoch INTEGER NOT NULL DEFAULT 1;"
```
Expected: `ALTER TABLE`

**Step 4: Verify column exists**

Run:
```bash
docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "\d users" | grep sync_epoch
```
Expected: `sync_epoch | integer | not null default 1`

**Step 5: Commit**

```bash
git add server/migrations/003_sync_epoch.up.sql server/migrations/003_sync_epoch.down.sql
git commit -m "feat(db): add sync_epoch column to users table"
```

---

### Task 2: Go Domain — Add `SyncEpoch` to User struct

**Files:**
- Modify: `server/internal/domain/user.go:13-27` (User struct)

**Step 1: Add SyncEpoch field to User struct**

Add after the `UpdatedAt` field (line 26):

```go
SyncEpoch            int          `json:"sync_epoch"`
```

**Step 2: Verify build compiles**

Run:
```bash
cd /Users/mac/github/folio/server && go build ./...
```
Expected: Build errors in repository/user.go (Scan calls don't include new column yet). This is expected — we fix it in the next task.

**Step 3: Commit**

```bash
git add server/internal/domain/user.go
git commit -m "feat(domain): add SyncEpoch field to User struct"
```

---

### Task 3: Go Repository — Read `sync_epoch` in user queries

**Files:**
- Modify: `server/internal/repository/user.go`

**Step 1: Update all SELECT queries and Scan calls in user.go**

Every query that reads from `users` must include `sync_epoch` in the SELECT list and the corresponding `.Scan()` call. There are three functions to update:

In `GetByID` (line 23): add `sync_epoch` to the SELECT column list (after `updated_at`), and add `&u.SyncEpoch` to the Scan call (after `&u.UpdatedAt`).

In `GetByAppleID` (line 47): same changes — add `sync_epoch` to SELECT and `&u.SyncEpoch` to Scan.

Find any other functions that SELECT from users (e.g., `Create`, `GetOrCreate`) and apply the same pattern.

**Step 2: Verify build compiles**

Run:
```bash
cd /Users/mac/github/folio/server && go build ./...
```
Expected: SUCCESS (no errors)

**Step 3: Commit**

```bash
git add server/internal/repository/user.go
git commit -m "feat(repo): read sync_epoch in user queries"
```

---

### Task 4: Go API — Add `sync_epoch` to list articles response

**Files:**
- Modify: `server/internal/api/handler/response.go:48-52` (ListResponse struct)
- Modify: `server/internal/api/handler/article.go:74-127` (HandleListArticles)

**Step 1: Add SyncEpoch to ListResponse**

In `server/internal/api/handler/response.go`, add a field to the `ListResponse` struct:

```go
type ListResponse struct {
	Data       any                `json:"data"`
	Pagination PaginationResponse `json:"pagination"`
	ServerTime string             `json:"server_time,omitempty"`
	SyncEpoch  int                `json:"sync_epoch,omitempty"`
}
```

**Step 2: Pass sync_epoch in HandleListArticles**

The handler needs access to the user's sync_epoch. The simplest approach: add a `userRepo` to `ArticleHandler`, look up the user, and include the epoch.

In `server/internal/api/handler/article.go`:

Add a `userRepo` field to ArticleHandler:

```go
type ArticleHandler struct {
	articleService articleServicer
	userRepo       userGetter
}

type userGetter interface {
	GetByID(ctx context.Context, id string) (*domain.User, error)
}
```

Update `NewArticleHandler` to accept the user repo:

```go
func NewArticleHandler(articleService *service.ArticleService, userRepo *repository.UserRepo) *ArticleHandler {
	return &ArticleHandler{articleService: articleService, userRepo: userRepo}
}
```

In `HandleListArticles`, after getting `userID` (line 75), fetch the user and include epoch in response:

```go
func (h *ArticleHandler) HandleListArticles(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	// Fetch user for sync_epoch
	user, err := h.userRepo.GetByID(r.Context(), userID)
	if err != nil || user == nil {
		writeError(w, http.StatusInternalServerError, "failed to load user")
		return
	}

	// ... existing query param parsing unchanged ...

	result, err := h.articleService.ListByUser(r.Context(), params)
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, ListResponse{
		Data: result.Articles,
		Pagination: PaginationResponse{
			Page:    page,
			PerPage: perPage,
			Total:   result.Total,
		},
		ServerTime: time.Now().UTC().Format(time.RFC3339),
		SyncEpoch:  user.SyncEpoch,
	})
}
```

**Step 3: Fix the NewArticleHandler call site**

Find where `NewArticleHandler` is called (likely in `server/internal/api/router.go` or a deps/wire file) and pass the `userRepo`:

```go
// Before:
NewArticleHandler(articleService)
// After:
NewArticleHandler(articleService, userRepo)
```

**Step 4: Verify build compiles**

Run:
```bash
cd /Users/mac/github/folio/server && go build ./...
```
Expected: SUCCESS

**Step 5: Test manually**

Run (with dev server running):
```bash
# Get a dev token
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/dev | jq -r '.access_token')
# List articles, check for sync_epoch
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/articles | jq '.sync_epoch'
```
Expected: `1`

**Step 6: Commit**

```bash
git add server/internal/api/handler/response.go server/internal/api/handler/article.go server/internal/api/router.go
git commit -m "feat(api): return sync_epoch in list articles response"
```

---

### Task 5: iOS DTO — Add `syncEpoch` to ListResponse and AuthResponse

**Files:**
- Modify: `ios/Folio/Data/Network/Network.swift`

**Step 1: Add syncEpoch to ListResponse**

At line 153-157, update:

```swift
struct ListResponse<T: Decodable>: Decodable {
    let data: [T]
    let pagination: PaginationDTO
    let serverTime: String?
    let syncEpoch: Int?
}
```

**Step 2: Add syncEpoch to UserDTO**

At line 31-43, add after `updatedAt`:

```swift
struct UserDTO: Decodable {
    let id: String
    let email: String?
    let nickname: String?
    let avatarUrl: String?
    let subscription: String
    let subscriptionExpiresAt: Date?
    let monthlyQuota: Int
    let currentMonthCount: Int
    let preferredLanguage: String
    let createdAt: Date
    let updatedAt: Date
    let syncEpoch: Int?
}
```

**Step 3: Verify iOS builds**

Run:
```bash
cd /Users/mac/github/folio/ios && xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add ios/Folio/Data/Network/Network.swift
git commit -m "feat(ios): add syncEpoch to ListResponse and UserDTO"
```

---

### Task 6: iOS SyncService — Epoch detection and purge logic

**Files:**
- Modify: `ios/Folio/Data/Sync/SyncService.swift`

This is the core logic. SyncService needs to:
1. Store `lastEpoch` in UserDefaults
2. On every sync, compare server epoch with local epoch
3. If mismatch: purge synced articles, reset `lastSyncedAt`, save new epoch, then full sync

**Step 1: Add epoch storage and key**

Add after line 13 (`lastSyncedAtKey`):

```swift
private static let lastEpochKey = "com.folio.lastSyncEpoch"

private var lastEpoch: Int {
    get { UserDefaults.standard.integer(forKey: Self.lastEpochKey) }
    set { UserDefaults.standard.set(newValue, forKey: Self.lastEpochKey) }
}
```

**Step 2: Add purge method**

Add a new method in the `// MARK: - Article Sync` section:

```swift
/// Purge all locally-synced articles (preserving pending/clientReady that haven't been uploaded).
private func purgeLocalSyncedArticles() {
    let syncedRaw = SyncState.synced.rawValue
    let descriptor = FetchDescriptor<Article>(
        predicate: #Predicate<Article> { $0.syncStateRaw == syncedRaw }
    )
    guard let articles = try? context.fetch(descriptor) else { return }
    for article in articles {
        context.delete(article)
    }

    // Also clear deletion records since they reference a previous epoch
    let deletionDescriptor = FetchDescriptor<DeletionRecord>()
    if let records = try? context.fetch(deletionDescriptor) {
        for record in records {
            context.delete(record)
        }
    }

    try? context.save()
    FolioLogger.sync.info("purged \(articles.count) synced article(s) due to epoch change")
}
```

**Step 3: Add epoch check method**

```swift
/// Check the server epoch from a list response. Returns true if epoch is OK (no reset needed).
private func checkEpoch(_ serverEpoch: Int?) -> Bool {
    guard let serverEpoch, serverEpoch > 0 else { return true }
    let local = lastEpoch
    if local == 0 {
        // First sync ever — just record the epoch
        lastEpoch = serverEpoch
        return true
    }
    if local == serverEpoch {
        return true
    }
    // Epoch mismatch — server data was reset
    FolioLogger.sync.info("epoch mismatch: local=\(local) server=\(serverEpoch), purging")
    purgeLocalSyncedArticles()
    lastSyncedAt = nil
    lastEpoch = serverEpoch
    return false
}
```

**Step 4: Integrate epoch check into fullSyncArticles**

Modify `fullSyncArticles()`. After the first page response, check the epoch. Replace the existing method:

```swift
private func fullSyncArticles() async {
    FolioLogger.sync.info("starting full article sync")
    let merger = ArticleMerger(context: context)
    var page = 1
    let perPage = 50
    var latestServerTime: String?

    do {
        while true {
            let response = try await apiClient.listArticles(page: page, perPage: perPage)
            if let serverTime = response.serverTime {
                latestServerTime = serverTime
            }
            // Epoch check on first page
            if page == 1 {
                let epochOK = checkEpoch(response.syncEpoch)
                if !epochOK {
                    // We just purged — continue with this full sync to repopulate
                }
            }
            for dto in response.data {
                _ = try? merger.merge(dto: dto)
            }
            try? context.save()

            let fetched = (page - 1) * perPage + response.data.count
            if fetched >= response.pagination.total {
                break
            }
            page += 1
        }
        lastSyncedAt = parseServerTime(latestServerTime) ?? Date()
        FolioLogger.sync.info("full article sync completed")
    } catch {
        FolioLogger.sync.error("full article sync failed: \(error)")
    }
}
```

**Step 5: Integrate epoch check into incrementalSyncArticles**

Modify `incrementalSyncArticles()`. Check epoch on first page; if mismatch, abort incremental and fall through to full sync:

```swift
private func incrementalSyncArticles() async {
    guard let since = lastSyncedAt else {
        await fullSyncArticles()
        return
    }
    FolioLogger.sync.debug("incremental sync since \(since)")
    let merger = ArticleMerger(context: context)
    var page = 1
    let perPage = 50
    var latestServerTime: String?

    do {
        while true {
            let response = try await apiClient.listArticles(
                page: page, perPage: perPage, updatedSince: since
            )
            if let serverTime = response.serverTime {
                latestServerTime = serverTime
            }
            // Epoch check on first page
            if page == 1 && !checkEpoch(response.syncEpoch) {
                // Epoch changed — checkEpoch already purged and reset lastSyncedAt
                // Fall through to full sync
                await fullSyncArticles()
                return
            }
            for dto in response.data {
                _ = try? merger.merge(dto: dto)
            }
            try? context.save()

            let fetched = (page - 1) * perPage + response.data.count
            if fetched >= response.pagination.total {
                break
            }
            page += 1
        }
        lastSyncedAt = parseServerTime(latestServerTime) ?? Date()
    } catch {
        FolioLogger.sync.error("incremental sync failed: \(error)")
    }
}
```

**Step 6: Also check epoch on login (from AuthResponse)**

In `performFullSync()`, add epoch check from user profile. Modify the `syncUserQuota()` method to also handle epoch:

```swift
private func syncUserQuota() async {
    do {
        let response = try await apiClient.refreshAuth()
        let user = response.user
        let isPro = user.subscription != "free"
        SharedDataManager.syncQuotaFromServer(
            monthlyQuota: user.monthlyQuota,
            currentMonthCount: user.currentMonthCount,
            isPro: isPro
        )
        // Check epoch from auth response
        if let epoch = user.syncEpoch {
            _ = checkEpoch(epoch)
        }
    } catch {
        FolioLogger.sync.error("quota sync failed: \(error)")
    }
}
```

**Step 7: Verify iOS builds**

Run:
```bash
cd /Users/mac/github/folio/ios && xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```bash
git add ios/Folio/Data/Sync/SyncService.swift
git commit -m "feat(sync): epoch detection — purge stale local data on server reset"
```

---

### Task 7: Integration test — verify epoch reset flow

**Step 1: Manual test with curl + simulator**

```bash
# 1. Get dev token
TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/dev | jq -r '.access_token')

# 2. Verify epoch is 1
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/articles | jq '.sync_epoch'
# Expected: 1

# 3. Bump epoch in database (simulate server reset)
docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "UPDATE users SET sync_epoch = 2;"

# 4. Verify epoch is now 2
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/articles | jq '.sync_epoch'
# Expected: 2
```

**Step 2: Test on iOS simulator**

1. Build and install the updated app on simulator
2. Open the app — it should detect epoch=2, purge old local articles, and full sync
3. Since server has 0 articles, the local list should now be empty
4. Take a screenshot to verify

Run:
```bash
cd /Users/mac/github/folio/ios && xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,id=7910EBEA-1F8E-47B3-9AF4-7A30F48407C9' -quiet 2>&1 | tail -5
xcrun simctl install 7910EBEA-1F8E-47B3-9AF4-7A30F48407C9 "$(xcodebuild -project Folio.xcodeproj -scheme Folio -showBuildSettings 2>/dev/null | grep ' TARGET_BUILD_DIR' | head -1 | awk '{print $3}')/Folio.app"
xcrun simctl launch 7910EBEA-1F8E-47B3-9AF4-7A30F48407C9 com.7WSH9CR7KS.folio.app
sleep 5
xcrun simctl io 7910EBEA-1F8E-47B3-9AF4-7A30F48407C9 screenshot /tmp/folio_epoch_test.png
```

**Step 3: Verify via logs**

Run:
```bash
xcrun simctl spawn 7910EBEA-1F8E-47B3-9AF4-7A30F48407C9 log stream --level debug --predicate 'subsystem == "com.folio.app" AND category == "sync"' --timeout 10
```
Expected: Log lines containing "epoch mismatch" and "purged X synced article(s)"

**Step 4: Commit (if not already)**

```bash
git add -A
git commit -m "feat: sync epoch — detect server resets and purge stale local data"
```

---

## Summary

| Task | What | Where |
|------|------|-------|
| 1 | DB migration: `sync_epoch` column | `server/migrations/003_*` |
| 2 | Go domain: add field | `server/internal/domain/user.go` |
| 3 | Go repo: read field in queries | `server/internal/repository/user.go` |
| 4 | Go API: return epoch in list response | `server/internal/api/handler/` |
| 5 | iOS DTO: parse epoch | `ios/Folio/Data/Network/Network.swift` |
| 6 | iOS sync: epoch check + purge | `ios/Folio/Data/Sync/SyncService.swift` |
| 7 | Integration test | Manual curl + simulator |

Total: ~7 small tasks, each independently committable.
