# Manual Content Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to save pasted content and personal thoughts directly, without requiring a URL, via a unified bottom input bar that doubles as search.

**Architecture:** Extend the existing Article model (URL becomes optional, new `manual` source type). New `POST /api/v1/articles/manual` endpoint. iOS HomeView replaces top `.searchable()` with a bottom `UnifiedInputBar` that handles both search and content creation. Share Extension gains plain-text support.

**Tech Stack:** Go 1.24 / chi v5 / pgx v5 / asynq (backend), Swift 5.9 / SwiftUI / SwiftData (iOS), Python pytest (E2E tests)

**Spec:** `docs/superpowers/specs/2026-03-19-manual-content-input-design.md`

---

## Part A: Backend (Tasks 1-9)

### Task 1: Database Migration

**Files:**
- Create: `server/migrations/002_manual_content.up.sql`
- Create: `server/migrations/002_manual_content.down.sql`

- [ ] **Step 1: Write up migration**

```sql
-- server/migrations/002_manual_content.up.sql

-- articles.url: NOT NULL → nullable
ALTER TABLE articles ALTER COLUMN url DROP NOT NULL;

-- Unique constraint becomes partial (only for rows with URL)
DROP INDEX idx_articles_user_url;
CREATE UNIQUE INDEX idx_articles_user_url ON articles (user_id, url) WHERE url IS NOT NULL;

-- crawl_tasks.url: NOT NULL → nullable (manual entries have no URL)
ALTER TABLE crawl_tasks ALTER COLUMN url DROP NOT NULL;
```

- [ ] **Step 2: Write down migration**

```sql
-- server/migrations/002_manual_content.down.sql

-- Clean up URL-less records before restoring constraint
DELETE FROM crawl_tasks WHERE url IS NULL;
DELETE FROM articles WHERE url IS NULL;

ALTER TABLE crawl_tasks ALTER COLUMN url SET NOT NULL;

DROP INDEX idx_articles_user_url;
CREATE UNIQUE INDEX idx_articles_user_url ON articles (user_id, url);

ALTER TABLE articles ALTER COLUMN url SET NOT NULL;
```

- [ ] **Step 3: Apply migration to dev database**

```bash
docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -f - < server/migrations/002_manual_content.up.sql
```

Verify:
```bash
docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "\d articles" | grep url
```
Expected: `url` column shows nullable (no `not null`).

- [ ] **Step 4: Commit**

```bash
git add server/migrations/002_manual_content.up.sql server/migrations/002_manual_content.down.sql
git commit -m "feat: add migration for nullable URL and manual source type"
```

---

### Task 2: Go Domain — URL Nullable + Manual Source Type

**Files:**
- Modify: `server/internal/domain/article.go`

- [ ] **Step 1: Write test for SourceTypeManual constant**

Create test file:
```go
// server/internal/domain/article_test.go
package domain

import "testing"

func TestSourceManual(t *testing.T) {
	if SourceManual != "manual" {
		t.Errorf("expected 'manual', got %q", SourceManual)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd server && go test ./internal/domain/ -run TestSourceManual -v
```
Expected: FAIL — `SourceManual` undefined.

- [ ] **Step 3: Add SourceManual and change URL to *string**

In `server/internal/domain/article.go`:

Add `SourceManual` constant after the existing SourceType constants (after line 24), following the existing naming convention (`SourceWeb`, `SourceWechat`, etc.):
```go
SourceManual     SourceType = "manual"
```

Change `URL` field in Article struct (line 29) from:
```go
URL             string        `json:"url"`
```
to:
```go
URL             *string       `json:"url,omitempty"`
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd server && go test ./internal/domain/ -run TestSourceManual -v
```
Expected: PASS

- [ ] **Step 5: Fix compile errors from URL type change**

```bash
cd server && go build ./...
```

This will surface all compile errors from the `string` → `*string` change. Do NOT fix them yet — they will be addressed in Task 3 (repository) and Task 4-6 (service/handler). Just verify the domain package itself compiles:

```bash
cd server && go build ./internal/domain/
```
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add server/internal/domain/
git commit -m "feat(domain): make Article.URL nullable, add SourceTypeManual"
```

---

### Task 3: Go Repository — Nullable URL Adaptation

**Files:**
- Modify: `server/internal/repository/article.go` (lines 25-34 CreateArticleParams, lines 36-54 Create, lines 56-89 GetByID, lines 106-204 ListByUser, lines 377-386 ExistsByUserAndURL, lines 398-441 Search)
- Modify: `server/internal/repository/task.go` (lines 29-34 CreateTaskParams, lines 36-48 Create, lines 50-69 GetByID)

- [ ] **Step 1: Update CreateArticleParams**

In `server/internal/repository/article.go`, change `CreateArticleParams.URL` (line 27) from:
```go
URL             string
```
to:
```go
URL             *string
```

- [ ] **Step 2: Update Create method**

The INSERT statement at line 38 uses `p.URL` directly. No change needed — pgx handles `*string` as NULL when nil.

The RETURNING scan at line 45 scans into `&a.URL`. Since `a.URL` is now `*string`, pgx will scan NULL as nil. No change needed.

- [ ] **Step 3: Update GetByID scan**

In GetByID (line 66-73), the scan `&a.URL` works because `a.URL` is `*string` — pgx handles nullable scans for pointer types automatically. No code change needed.

- [ ] **Step 4: Update ListByUser scan**

In ListByUser (lines 191-198), same situation — `&a.URL` scan works with `*string`. No change needed.

- [ ] **Step 5: Update Search scan**

In Search (lines 427-434), same pattern. No change needed.

- [ ] **Step 6: Update ExistsByUserAndURL**

In `ExistsByUserAndURL` (line 380), the query uses `WHERE user_id = $1 AND url = $2`. This still works — for URL articles, we pass a non-nil `*string`; the function is only called for URL dedup, never for manual entries. No change needed.

- [ ] **Step 7: Update CreateTaskParams**

In `server/internal/repository/task.go`, change `CreateTaskParams.URL` (line 32) from:
```go
URL        string
```
to:
```go
URL        *string
```

- [ ] **Step 8: Update domain.CrawlTask.URL to *string**

In `server/internal/domain/task.go`, change `CrawlTask.URL` from `string` to `*string`. This is required because task Create and GetByID scan `url` into this field, which is now nullable in the DB.

- [ ] **Step 9: Update worker/tasks.go CrawlPayload.URL**

In `server/internal/worker/tasks.go`, `CrawlPayload.URL` (line 23) is `string`. For manual entries, `NewCrawlTask` won't be called (we use `NewAIProcessTask` directly), so `CrawlPayload.URL` can stay as `string`. No change needed.

- [ ] **Step 10: Verify full build**

```bash
cd server && go build ./...
```

Fix any remaining compile errors from the URL type change across the entire server codebase. Common patterns:
- `article.URL` used as string → dereference with `*article.URL` or nil-check
- String comparisons → pointer comparisons
- Function args expecting string → pass `&url` or handle nil

- [ ] **Step 11: Run existing tests**

```bash
cd server && go test ./internal/repository/ -v
```
Expected: All existing tests pass.

- [ ] **Step 12: Commit**

```bash
git add server/internal/repository/ server/internal/domain/
git commit -m "feat(repository): adapt article and task repos for nullable URL"
```

---

### Task 4: Go Service — SubmitManualContent

**Files:**
- Modify: `server/internal/service/article.go`

- [ ] **Step 1: Define SubmitManualContentRequest**

Add after `SubmitURLResponse` (after line 55):

```go
type SubmitManualContentRequest struct {
	Content string   `json:"content"`
	Title   *string  `json:"title,omitempty"`
	TagIDs  []string `json:"tag_ids,omitempty"`
}
```

- [ ] **Step 2: Export countWords from repository**

In `server/internal/repository/article.go`, rename `countWords` (line 265) to `CountWords` to export it for use from the service package. Update the one internal call site in the same file.

- [ ] **Step 3: Implement SubmitManualContent method**

Add after the `SubmitURL` method (after line 124). Follow the exact patterns from `SubmitURL`: use `s.quotaService` (not quotaRepo), use `worker.NewAIProcessTask()` factory (not raw asynq.NewTask), use `slog` for logging:

```go
func (s *ArticleService) SubmitManualContent(ctx context.Context, userID string, req SubmitManualContentRequest) (*SubmitURLResponse, error) {
	// Check quota
	if err := s.quotaService.CheckAndIncrement(ctx, userID); err != nil {
		return nil, err
	}

	// Calculate word count
	wordCount := repository.CountWords(req.Content)

	// Create article with no URL
	article, err := s.articleRepo.Create(ctx, repository.CreateArticleParams{
		UserID:          userID,
		URL:             nil,
		SourceType:      domain.SourceManual,
		Title:           req.Title,
		MarkdownContent: &req.Content,
		WordCount:       &wordCount,
	})
	if err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("create article: %w", err)
	}

	// Attach user-provided tags
	for _, tagID := range req.TagIDs {
		if err := s.tagRepo.AttachToArticle(ctx, article.ID, tagID); err != nil {
			slog.Error("failed to attach tag", "article_id", article.ID, "tag_id", tagID, "error", err)
			continue
		}
	}

	// Create task for tracking
	task, err := s.taskRepo.Create(ctx, repository.CreateTaskParams{
		ArticleID:  article.ID,
		UserID:     userID,
		URL:        nil,
		SourceType: string(domain.SourceManual),
	})
	if err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("create task: %w", err)
	}

	// Enqueue AI task directly (skip crawl — content already provided)
	// Use worker.NewAIProcessTask factory for correct queue/retry/timeout settings
	title := ""
	if req.Title != nil {
		title = *req.Title
	}
	aiTask := worker.NewAIProcessTask(article.ID, task.ID, userID, title, req.Content, "", "")
	if _, err := s.asynqClient.EnqueueContext(ctx, aiTask); err != nil {
		_ = s.quotaService.DecrementQuota(ctx, userID)
		return nil, fmt.Errorf("enqueue ai: %w", err)
	}

	slog.Info("manual content submitted", "article_id", article.ID, "task_id", task.ID)

	return &SubmitURLResponse{
		ArticleID: article.ID,
		TaskID:    task.ID,
	}, nil
}
```

- [ ] **Step 4: Update articleServicer interface**

In `server/internal/api/handler/article.go`, add to the `articleServicer` interface (after line 27):

```go
SubmitManualContent(ctx context.Context, userID string, req service.SubmitManualContentRequest) (*service.SubmitURLResponse, error)
```

- [ ] **Step 4: Verify build**

```bash
cd server && go build ./...
```

- [ ] **Step 5: Commit**

```bash
git add server/internal/service/ server/internal/api/handler/
git commit -m "feat(service): add SubmitManualContent for text-only articles"
```

---

### Task 5: Go Handler — HandleSubmitManual

**Files:**
- Modify: `server/internal/api/handler/article.go`

- [ ] **Step 1: Define request struct**

Add after the existing request structs (around line 44):

```go
type submitManualRequest struct {
	Content string   `json:"content"`
	Title   *string  `json:"title,omitempty"`
	TagIDs  []string `json:"tag_ids,omitempty"`
}
```

- [ ] **Step 2: Implement HandleSubmitManual**

Add after `HandleSubmitURL` (after line 92). Follow the exact patterns from `HandleSubmitURL`: use `middleware.UserIDFromContext`, `writeError`/`writeJSON` (not respondError/respondJSON), `handleServiceError(w, r, err)` (needs `r` parameter):

```go
func (h *ArticleHandler) HandleSubmitManual(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())

	var req submitManualRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Trim and validate content
	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" {
		writeError(w, http.StatusBadRequest, "content is required")
		return
	}

	// Truncate if exceeds max size (500KB), matching HandleSubmitURL pattern
	if len(req.Content) > maxMarkdownContentBytes {
		runes := []rune(req.Content)
		for len(string(runes)) > maxMarkdownContentBytes {
			runes = runes[:len(runes)-1]
		}
		req.Content = string(runes)
	}

	resp, err := h.articleService.SubmitManualContent(r.Context(), userID, service.SubmitManualContentRequest{
		Content: req.Content,
		Title:   req.Title,
		TagIDs:  req.TagIDs,
	})
	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusAccepted, resp)
}
```

Also add `"strings"` to the import block at the top of the file (line 3-18) if not already present.

- [ ] **Step 3: Verify build**

```bash
cd server && go build ./...
```

- [ ] **Step 4: Commit**

```bash
git add server/internal/api/handler/
git commit -m "feat(handler): add HandleSubmitManual for manual content endpoint"
```

---

### Task 6: Go Router — Register Manual Endpoint

**Files:**
- Modify: `server/internal/api/router.go` (add route around line 62)

- [ ] **Step 1: Add route**

Routes are NOT nested under `/articles` — they use full paths. Add the new route BEFORE `/articles/{id}` (line 64) to avoid chi route collision. Insert after line 62:

```go
r.Post("/articles/manual", deps.ArticleHandler.HandleSubmitManual)
```

The route order should be: `/articles/search` (GET), `/articles` (POST), `/articles/manual` (POST), then `/articles/{id}` (GET/PUT/DELETE).

- [ ] **Step 2: Verify build and route registration**

```bash
cd server && go build ./...
```

- [ ] **Step 3: Manual smoke test**

Start the server and test the new endpoint:

```bash
cd server && go run ./cmd/server &
sleep 2

# Get a token first (use email auth)
TOKEN=$(curl -s http://localhost:8080/api/v1/auth/email/verify \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","code":"..."}' | jq -r '.token')

# Test manual content submission
curl -s -X POST http://localhost:8080/api/v1/articles/manual \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"content":"This is a test thought about knowledge management"}' | jq .

# Test validation — empty content
curl -s -X POST http://localhost:8080/api/v1/articles/manual \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"content":"   "}' | jq .
```

Expected: 202 with `articleId` + `taskId` for valid content, 400 for empty.

- [ ] **Step 4: Commit**

```bash
git add server/internal/api/router.go
git commit -m "feat(router): register POST /api/v1/articles/manual endpoint"
```

---

### Task 7: Go Worker — AI Title Backfill + Cache Skip

**Files:**
- Modify: `server/internal/worker/ai_handler.go` (lines 119-132 UpdateAIResult area, lines 154-179 cache write area)
- Modify: `server/internal/repository/article.go` (add UpdateTitle method)

- [ ] **Step 1: Add UpdateTitle repository method**

In `server/internal/repository/article.go`, add after `UpdateAIResult` (after line 321):

```go
func (r *ArticleRepo) UpdateTitle(ctx context.Context, articleID string, title string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE articles SET title = $1, updated_at = NOW() WHERE id = $2`,
		title, articleID)
	return err
}
```

Also update the `aiArticleRepo` interface in `server/internal/worker/ai_handler.go` (line 23-28) to include:

```go
UpdateTitle(ctx context.Context, articleID string, title string) error
```

- [ ] **Step 2: Add title backfill logic in AI handler**

In `server/internal/worker/ai_handler.go`, after the `UpdateAIResult` call (around line 132), add:

```go
// Backfill title for manual entries that have no user-provided title
if article.Title == nil || *article.Title == "" {
	var generatedTitle string
	if len(result.KeyPoints) > 0 {
		generatedTitle = result.KeyPoints[0]
	} else if result.Summary != "" {
		generatedTitle = result.Summary
		// Truncate at word boundary, max 50 chars
		if len([]rune(generatedTitle)) > 50 {
			runes := []rune(generatedTitle)
			generatedTitle = string(runes[:50])
		}
	}
	if generatedTitle != "" {
		if err := h.articleRepo.UpdateTitle(ctx, payload.ArticleID, generatedTitle); err != nil {
			log.Printf("[ai] failed to backfill title for article %s: %v", payload.ArticleID, err)
			// Non-fatal — continue processing
		}
	}
}
```

- [ ] **Step 3: Add cache skip for nil URL**

In `server/internal/worker/ai_handler.go`, in the cache write section (line 154-179). The cache write fetches the article at line 155, then at line 158 checks `IsCacheWorthy`. Add a nil URL check before the cache-worthy check:

Change line 156-158 from:
```go
if err == nil && article != nil {
    markdown := derefOrEmpty(article.MarkdownContent)
    if domain.IsCacheWorthy(markdown, result.Confidence) {
```
to:
```go
if err == nil && article != nil && article.URL != nil {
    markdown := derefOrEmpty(article.MarkdownContent)
    if domain.IsCacheWorthy(markdown, result.Confidence) {
```

Also note: `article.URL` is now `*string`, and `ContentCache.URL` (line 161) accepts it directly since it should also be updated to `*string` in `domain/content_cache.go`. Check and update if needed.

- [ ] **Step 4: Verify build**

```bash
cd server && go build ./...
```

- [ ] **Step 5: Commit**

```bash
git add server/internal/worker/ai_handler.go server/internal/repository/article.go
git commit -m "feat(worker): add AI title backfill for manual entries, skip cache for nil URL"
```

---

### Task 8: Mock AI Service — No-URL Support

**Files:**
- Modify: `server/scripts/mock_ai_service.py`

- [ ] **Step 1: Update category detection**

In `mock_ai_service.py`, the `detect_category` function (around line 26) uses URL patterns. Add a fallback for when `source` is empty or None. Before the URL-based checks, add content-based detection:

```python
def detect_category(title, content, source=""):
    text = f"{title} {content[:200]}".lower()

    # URL-based detection (existing logic)
    if source:
        # ... existing URL pattern matching ...
        pass

    # Content-based fallback (for manual entries with no source URL)
    if "code" in text or "programming" in text or "api" in text or "software" in text:
        return "tech", "Technology"
    if "science" in text or "research" in text or "study" in text:
        return "science", "Science"
    if "design" in text or "ui" in text or "ux" in text:
        return "design", "Design"
    # ... more keyword patterns matching existing categories ...

    return "other", "Other"
```

- [ ] **Step 2: Handle missing source field in request**

In the analyze endpoint handler, ensure `source` defaults to empty string when not provided:

```python
source = data.get("source", "")
```

- [ ] **Step 3: Test with curl**

```bash
# Start mock AI
python3 server/scripts/mock_ai_service.py &
sleep 1

# Test with no source field
curl -s -X POST http://localhost:8000/api/analyze \
  -H 'Content-Type: application/json' \
  -d '{"title":"","content":"This is a thought about software programming and API design","source":"","author":""}' | jq .
```

Expected: Returns valid response with category, tags, summary.

- [ ] **Step 4: Commit**

```bash
git add server/scripts/mock_ai_service.py
git commit -m "feat(mock-ai): support manual content requests without URL"
```

---

### Task 9: E2E Tests — Manual Content

**Files:**
- Create: `server/tests/e2e/test_13_manual_content.py`
- Modify: `server/tests/e2e/helpers/api_client.py` (add `submit_manual` method)

- [ ] **Step 1: Add submit_manual to API client**

In `server/tests/e2e/helpers/api_client.py`, add method:

```python
def submit_manual(self, content, title=None, tag_ids=None):
    """Submit manual content (no URL)."""
    payload = {"content": content}
    if title:
        payload["title"] = title
    if tag_ids:
        payload["tag_ids"] = tag_ids
    return self.post("/api/v1/articles/manual", json=payload)
```

- [ ] **Step 2: Write test file**

```python
# server/tests/e2e/test_13_manual_content.py
"""Tests for manual content submission (no URL)."""
import pytest
from helpers.assertions import assert_uuid, assert_error_response
from helpers.polling import poll_until_done


class TestManualContentSubmission:
    """Test POST /api/v1/articles/manual."""

    def test_submit_short_thought(self, fresh_api):
        """Short text saves as manual article."""
        resp = fresh_api.submit_manual("This is a quick thought about knowledge management")
        assert resp.status_code == 202
        body = resp.json()
        assert_uuid(body["article_id"], "article_id")
        assert_uuid(body["task_id"], "task_id")

    def test_submit_long_content(self, fresh_api):
        """Long pasted content saves successfully."""
        content = "Deep learning fundamentals. " * 100  # ~2700 chars
        resp = fresh_api.submit_manual(content, title="Deep Learning Notes")
        assert resp.status_code == 202

    def test_submit_with_title(self, fresh_api):
        """User-provided title is preserved."""
        resp = fresh_api.submit_manual(
            content="Some thoughts here",
            title="My Custom Title"
        )
        assert resp.status_code == 202
        body = resp.json()

        # Fetch article and verify title
        article = fresh_api.get_article(body["article_id"]).json()
        assert article["title"] == "My Custom Title"

    def test_submit_empty_content_rejected(self, fresh_api):
        """Empty content returns 400."""
        resp = fresh_api.submit_manual("")
        assert_error_response(resp, 400, error_contains="content")

    def test_submit_whitespace_only_rejected(self, fresh_api):
        """Whitespace-only content returns 400."""
        resp = fresh_api.submit_manual("   \n\t  ")
        assert_error_response(resp, 400, error_contains="content")

    def test_no_url_in_article(self, fresh_api):
        """Manual article has no URL field."""
        resp = fresh_api.submit_manual("A thought without URL")
        body = resp.json()
        article = fresh_api.get_article(body["article_id"]).json()
        assert article.get("url") is None or article.get("url") == ""

    def test_source_type_is_manual(self, fresh_api):
        """Article source_type is 'manual'."""
        resp = fresh_api.submit_manual("Testing source type")
        body = resp.json()
        article = fresh_api.get_article(body["article_id"]).json()
        assert article["source_type"] == "manual"


class TestManualContentPipeline:
    """Test AI pipeline for manual content."""

    def test_ai_processes_manual_content(self, api):
        """Manual content goes through AI analysis."""
        resp = api.submit_manual("Artificial intelligence and machine learning are transforming software development")
        body = resp.json()

        # Poll until AI completes
        task = poll_until_done(api, body["task_id"], timeout=60)
        assert task["status"] == "done"

        # Verify AI results
        article = api.get_article(body["article_id"]).json()
        assert article["status"] == "ready"
        assert article.get("category") is not None
        assert article.get("summary") is not None
        assert len(article.get("tags", [])) > 0

    def test_title_backfill_when_no_title(self, api):
        """AI generates title when user doesn't provide one."""
        resp = api.submit_manual("The future of distributed systems lies in consensus algorithms")
        body = resp.json()

        poll_until_done(api, body["task_id"], timeout=60)
        article = api.get_article(body["article_id"]).json()

        # Title should be backfilled from AI key_points or summary
        assert article.get("title") is not None
        assert len(article["title"]) > 0

    def test_title_not_overwritten_when_provided(self, api):
        """User-provided title is NOT overwritten by AI."""
        resp = api.submit_manual(
            content="Some content about technology",
            title="My Original Title"
        )
        body = resp.json()

        poll_until_done(api, body["task_id"], timeout=60)
        article = api.get_article(body["article_id"]).json()
        assert article["title"] == "My Original Title"


class TestManualContentDuplication:
    """Test that manual entries allow duplicates."""

    def test_duplicate_content_allowed(self, fresh_api):
        """Same content can be saved multiple times."""
        content = "Repeated thought about productivity"
        resp1 = fresh_api.submit_manual(content)
        resp2 = fresh_api.submit_manual(content)
        assert resp1.status_code == 202
        assert resp2.status_code == 202
        assert resp1.json()["article_id"] != resp2.json()["article_id"]
```

- [ ] **Step 3: Run E2E tests**

```bash
cd server && ./scripts/run_e2e.sh
```

Or run just the new test file:
```bash
cd server && python -m pytest tests/e2e/test_13_manual_content.py -v
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add server/tests/e2e/test_13_manual_content.py server/tests/e2e/helpers/api_client.py
git commit -m "test(e2e): add manual content submission and pipeline tests"
```

---

## Part B: iOS (Tasks 10-17)

### Task 10: iOS Model — Article.url Optional + SourceType.manual

**Files:**
- Modify: `ios/Folio/Domain/Models/Article.swift`

- [ ] **Step 1: Add .manual to SourceType enum**

In `Article.swift`, in the `SourceType` enum (around line 20), add the new case:

```swift
case manual = "manual"
```

- [ ] **Step 2: Update SourceType extensions**

In the `SourceType` extension, add `iconName` and `displayName` for `.manual`:

```swift
// In iconName switch
case .manual: return "square.and.pencil"

// In displayName switch
case .manual: return String(localized: "source.manual", defaultValue: "Manual")
```

Do NOT add logic for "我的想法 vs 粘贴内容" here — that depends on `wordCount` and belongs in `ArticleCardView`.

- [ ] **Step 3: Make url optional**

Change line 70 from:
```swift
var url: String
```
to:
```swift
var url: String?
```

- [ ] **Step 4: Update displayTitle computed property**

Update `displayTitle` (lines 153-171) to handle nil url:

```swift
var displayTitle: String {
    if let title = title, !title.isEmpty {
        return title
    }
    if let url = url, let parsed = URL(string: url) {
        return parsed.host ?? url
    }
    // Fallback for manual entries: use content preview
    if let content = markdownContent, !content.isEmpty {
        let preview = String(content.prefix(50))
        return preview.count < content.count ? preview + "..." : preview
    }
    return String(localized: "article.untitled", defaultValue: "Untitled")
}
```

- [ ] **Step 5: Add convenience initializer for manual content**

After the existing initializer (around line 173), add:

```swift
convenience init(content: String, title: String? = nil) {
    self.init(url: nil, title: title, sourceType: .manual)
    self.markdownContent = content
    self.wordCount = content.count
    self.statusRaw = ArticleStatus.pending.rawValue
}
```

Also update the existing initializer to accept optional url:

Change the `init` signature from:
```swift
init(url: String, title: String? = nil, ..., sourceType: SourceType = .web)
```
to:
```swift
init(url: String?, title: String? = nil, ..., sourceType: SourceType = .web)
```

Update the body: `self.url = url` (this already works with optional).

- [ ] **Step 6: Update SourceType.detect(from:) to require non-optional**

The `detect(from urlString: String)` method should keep its non-optional parameter — callers must have a URL to detect source type. Manual entries bypass this entirely.

- [ ] **Step 7: Build to find all compile errors**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' 2>&1 | grep "error:" | head -50
```

This will show all the places that break from `url: String` → `url: String?`. Do NOT fix them in this task — they'll be handled in Task 11.

- [ ] **Step 8: Commit (model changes only)**

```bash
git add ios/Folio/Domain/Models/Article.swift
git commit -m "feat(ios): make Article.url optional, add SourceType.manual"
```

---

### Task 11: iOS URL Optional Adaptation

**Files:**
- Modify: ~100+ files across `ios/Folio/` and `ios/FolioTests/`

This task fixes all compile errors from `url: String` → `url: String?`.

- [ ] **Step 1: Get full list of errors**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' 2>&1 | grep "error:" > /tmp/url-optional-errors.txt
cat /tmp/url-optional-errors.txt | wc -l
```

- [ ] **Step 2: Fix production code errors**

Common patterns to apply:

| Error pattern | Fix |
|--------------|-----|
| `Article(url: "...")` in non-test code | Keep as-is (String literal auto-bridges to String?) |
| `article.url` used as `String` | Use `article.url ?? ""` or `if let url = article.url` |
| `URL(string: article.url)` | `article.url.flatMap { URL(string: $0) }` |
| Predicate `$0.url == someURL` | `$0.url == someURL` (works with optional comparison) |
| `apiClient.submitArticle(url: article.url)` | `apiClient.submitArticle(url: article.url!)` with guard |

Key files to fix (based on earlier exploration):
- `SharedDataManager.swift:20-37` — `saveArticle(url:)` predicate
- `SyncService.swift:42` — `submitArticle(url: article.url)`
- `ArticleRepository.swift:12-27` — `save(url:)` method
- `HomeView.swift` — URL-related alerts
- `HomeViewModel.swift` — retryArticle
- `ArticleCardView.swift` — source display
- `ReaderView.swift` — open in browser

- [ ] **Step 3: Fix test code errors**

Test files create `Article(url: "...")` — most should compile fine since String literal bridges to String?. Fix any remaining issues.

- [ ] **Step 4: Build and verify zero errors**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator' 2>&1 | grep "error:" | wc -l
```
Expected: 0

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: All existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add ios/
git commit -m "refactor(ios): adapt all url references for optional String?"
```

---

### Task 12: iOS Network — submitManualContent API

**Files:**
- Modify: `ios/Folio/Data/Network/Network.swift`

- [ ] **Step 1: Add DTO**

After `SubmitArticleRequest` (line 74), add:

```swift
struct SubmitManualContentRequest: Encodable {
    let content: String
    var title: String?
    var tagIds: [String]?
}
```

- [ ] **Step 2: Add APIClient method**

After `submitArticle` method (around line 475), add:

```swift
func submitManualContent(content: String, title: String? = nil, tagIds: [String] = []) async throws -> SubmitArticleResponse {
    var request = SubmitManualContentRequest(content: content)
    request.title = title
    request.tagIds = tagIds.isEmpty ? nil : tagIds
    return try await post("/api/v1/articles/manual", body: request)
}
```

Note: The return type is `SubmitArticleResponse` (reuses the same `articleId` + `taskId` structure, already defined at line 76-79).

- [ ] **Step 3: Make ArticleDTO.url and CrawlTaskDTO.url optional**

In `Network.swift`, change `ArticleDTO.url` (around line 83) from `let url: String` to `let url: String?`. Also change `CrawlTaskDTO.url` (around line 123) from `let url: String` to `let url: String?`. This is required because the server will return `null` for manual articles' URL field, and `JSONDecoder` will crash on non-optional `String` receiving `null`.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'
```

- [ ] **Step 4: Commit**

```bash
git add ios/Folio/Data/Network/Network.swift
git commit -m "feat(ios): add submitManualContent API client method"
```

---

### Task 13: iOS Data Layer — SharedDataManager + ArticleRepository + SyncService

**Files:**
- Modify: `ios/Folio/Data/SwiftData/SharedDataManager.swift`
- Modify: `ios/Folio/Data/Repository/ArticleRepository.swift`
- Modify: `ios/Folio/Data/Sync/SyncService.swift`

- [ ] **Step 1: Add saveManualContent to SharedDataManager**

In `SharedDataManager.swift`, after `saveArticleFromText` (after line 58), add:

```swift
func saveManualContent(content: String) throws -> Article {
    let article = Article(content: content)
    context.insert(article)
    try context.save()
    return article
}
```

- [ ] **Step 2: Add manual creation path to ArticleRepository**

In `ArticleRepository.swift`, after `save(url:tags:note:)` (after line 27), add:

```swift
func saveManualContent(content: String, title: String? = nil, tags: [Tag] = []) throws -> Article {
    let article = Article(content: content, title: title)
    context.insert(article)
    if !tags.isEmpty {
        article.tags = tags
    }
    try context.save()
    return article
}
```

- [ ] **Step 3: Update SyncService to route manual articles**

In `SyncService.swift`, in `submitPendingArticles` (around line 42), update the submission logic:

Find the line that calls `apiClient.submitArticle(url: ...)` and wrap it:

```swift
if article.sourceType == .manual {
    guard let content = article.markdownContent, !content.isEmpty else {
        continue
    }
    let response = try await apiClient.submitManualContent(
        content: content,
        title: article.title
    )
    article.serverID = response.articleId
    article.syncState = .synced
} else {
    guard let url = article.url else { continue }
    // ... existing submitArticle flow ...
}
```

- [ ] **Step 4: Build and run tests**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'
xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add ios/Folio/Data/
git commit -m "feat(ios): add manual content support to SharedDataManager, ArticleRepository, SyncService"
```

---

### Task 14: iOS UnifiedInputBar Component

**Files:**
- Create: `ios/Folio/Presentation/Home/UnifiedInputBar.swift`

- [ ] **Step 1: Create UnifiedInputBar component**

```swift
// ios/Folio/Presentation/Home/UnifiedInputBar.swift
import SwiftUI

struct UnifiedInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSend: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            TextField(
                String(localized: "input.placeholder",
                       defaultValue: "Search, jot a thought, or paste a link..."),
                text: $text,
                axis: .vertical
            )
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(Typography.body)
            .padding(.vertical, Spacing.xs)

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    text = ""
                    isFocused = false
                    onSend(content)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }
}
```

- [ ] **Step 2: Add URL detection utility**

Add below the struct in the same file, or in a shared location:

```swift
extension UnifiedInputBar {
    /// Returns true if the trimmed text is a single URL with no other meaningful text.
    static func isURLOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = detector?.matches(in: trimmed, range: range) ?? []

        guard matches.count == 1, let match = matches.first else { return false }
        // The URL match covers the entire input
        return match.range.length == range.length
    }
}
```

- [ ] **Step 3: Regenerate Xcode project**

```bash
cd ios && xcodegen generate
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'
```

- [ ] **Step 5: Commit**

```bash
git add ios/Folio/Presentation/Home/UnifiedInputBar.swift ios/project.yml
git commit -m "feat(ios): add UnifiedInputBar component with URL detection"
```

---

### Task 15: iOS HomeView — Replace .searchable with UnifiedInputBar

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`
- Modify: `ios/Folio/Presentation/Home/HomeViewModel.swift`

- [ ] **Step 1: Add state for input bar**

In `HomeView.swift`, add state properties (around line 15):

```swift
@FocusState private var isInputFocused: Bool
```

- [ ] **Step 2: Remove .searchable modifier**

Remove the `.searchable(...)` modifier block (lines 59-63) and the `.searchSuggestions { ... }` block (lines 64-131).

Remove the `onChange(of: searchText)` handler (lines 138-140) and `onSubmit(of: .search)` handler (lines 132-137).

- [ ] **Step 3: Add UnifiedInputBar to view body**

Wrap the existing content in a VStack or ZStack, and add the UnifiedInputBar at the bottom. Use `.safeAreaInset(edge: .bottom)`:

```swift
.safeAreaInset(edge: .bottom) {
    UnifiedInputBar(text: $searchText, isFocused: $isInputFocused) { content in
        if UnifiedInputBar.isURLOnly(content) {
            saveURL(content)
        } else {
            saveManualContent(content)
        }
    }
}
```

- [ ] **Step 4: Add saveManualContent method**

In `HomeView.swift`, add a method. Note: use `modelContext` from `@Environment(\.modelContext)`, NOT from viewModel (HomeViewModel doesn't hold a modelContext):

```swift
private func saveManualContent(_ content: String) {
    let manager = SharedDataManager(context: modelContext)
    do {
        let article = try manager.saveManualContent(content: content)
        viewModel?.fetchArticles()
        // Trigger sync if authenticated
        if let vm = viewModel, vm.isAuthenticated {
            Task {
                await vm.syncManualArticle(article)
            }
        }
    } catch {
        // Handle error (e.g., show alert)
    }
}
```

- [ ] **Step 5: Wire up real-time search filtering**

The `searchText` binding already exists. Add an `onChange(of: searchText)` that filters the article list:

```swift
.onChange(of: searchText) { _, newValue in
    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        viewModel?.clearSearch()
    } else {
        viewModel?.filterArticles(query: trimmed)
    }
}
```

- [ ] **Step 6: Integrate with existing SearchViewModel for filtering**

The existing search uses `SearchViewModel` with FTS5 full-text search, search history, and suggestions. Do NOT replace this with simple in-memory filtering — reuse `SearchViewModel` to maintain search quality.

In `HomeView.swift`, add a search state and delegate filtering to `SearchViewModel`:

```swift
@State private var isSearching = false

// In onChange(of: searchText):
.onChange(of: searchText) { _, newValue in
    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    isSearching = !trimmed.isEmpty
    if trimmed.isEmpty {
        // Show normal article list
    } else {
        // Delegate to existing SearchViewModel for FTS5 search
        searchViewModel?.searchText = trimmed
    }
}
```

When `isSearching` is true, show `SearchViewModel`'s results above the input bar instead of the normal article list. When the user taps a result, clear search text and navigate. This preserves the FTS5 search quality while integrating with the new input bar.

- [ ] **Step 7: Add syncManualArticle to HomeViewModel**

```swift
func syncManualArticle(_ article: Article) async {
    guard isAuthenticated else { return }
    do {
        let response = try await apiClient.submitManualContent(
            content: article.markdownContent ?? "",
            title: article.title
        )
        await MainActor.run {
            article.serverID = response.articleId
            article.syncState = .synced
            article.status = .processing
        }
    } catch {
        // Will retry on next sync cycle
    }
}
```

- [ ] **Step 8: Build and test**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'
```

- [ ] **Step 9: Visual verification on simulator**

Build and run on simulator. Verify:
- Bottom input bar is visible
- Typing shows send button
- Typing filters the article list
- Sending a URL creates an article (existing flow)
- Sending text creates a manual article
- Keyboard dismiss works

- [ ] **Step 10: Commit**

```bash
git add ios/Folio/Presentation/Home/
git commit -m "feat(ios): replace .searchable with UnifiedInputBar in HomeView"
```

---

### Task 16: iOS Share Extension — Text Support

**Files:**
- Modify: `ios/ShareExtension/ShareViewController.swift`

- [ ] **Step 1: Update processInput to handle plain text content**

In `ShareViewController.swift`, the `processInput()` method (lines 24-69) currently handles URL first, then plainText (but extracts URL from text). Update the plainText branch to also handle non-URL text:

In the existing `UTType.plainText` handler (around line 45-63), after extracting URL from text, add a fallback for pure text:

```swift
// Existing: try to extract URL from text
if let url = extractURL(from: text) {
    saveURL(url)
} else if let parsed = URL(string: text), parsed.scheme?.hasPrefix("http") == true {
    saveURL(text)
} else {
    // NEW: text is not a URL — save as manual content
    saveManualContent(text)
}
```

- [ ] **Step 2: Add saveManualContent method**

Add after `saveURL(_:)` (after line 104):

```swift
private func saveManualContent(_ content: String) {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        showAndDismiss(String(localized: "share.emptyContent", defaultValue: "No content to save"), delay: 1.5)
        return
    }

    // Quota check
    guard SharedDataManager.canSave(isPro: UserDefaults.appGroup?.bool(forKey: SharedDataManager.isProUserKey) ?? false) else {
        showAndDismiss(String(localized: "share.quotaExceeded", defaultValue: "Monthly quota exceeded"), delay: 2.0)
        return
    }

    let container = try! ModelContainer(for: Article.self, Tag.self, Category.self,
        configurations: .init(groupContainer: .identifier(AppConstants.appGroupIdentifier)))
    let manager = SharedDataManager(context: container.mainContext)

    do {
        _ = try manager.saveManualContent(content: trimmed)
        SharedDataManager.incrementQuota()
        UserDefaults.appGroup?.set(true, forKey: AppConstants.shareExtensionDidSaveKey)
        showAndDismiss(String(localized: "share.saved", defaultValue: "Saved!"), delay: 1.0)
    } catch {
        showAndDismiss(String(localized: "share.saveFailed", defaultValue: "Save failed"), delay: 1.5)
    }
}
```

- [ ] **Step 3: Update project.yml for text support**

In `ios/project.yml`, ensure the ShareExtension's `NSExtensionActivationRule` includes `NSExtensionActivationSupportsText = true` (it may already support `public.plain-text`). Check and update if needed.

- [ ] **Step 4: Regenerate and build**

```bash
cd ios && xcodegen generate
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'
```

- [ ] **Step 5: Commit**

```bash
git add ios/ShareExtension/ ios/project.yml
git commit -m "feat(ios): Share Extension supports plain text content"
```

---

### Task 17: iOS Display — ArticleCardView + ReaderView

**Files:**
- Modify: `ios/Folio/Presentation/Home/ArticleCardView.swift`
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`

- [ ] **Step 1: Update ArticleCardView source display for manual entries**

In `ArticleCardView.swift`, in the source line section (around lines 55-98), update the display logic for `.manual`:

Find where `article.siteName` or domain is displayed and add a check:

```swift
// Source label
if article.sourceType == .manual {
    Text(article.wordCount < 200
        ? String(localized: "source.thought", defaultValue: "My Thought")
        : String(localized: "source.pasted", defaultValue: "Pasted Content"))
        .font(Typography.caption)
        .foregroundStyle(Color.folio.textTertiary)
} else if let siteName = article.siteName, !siteName.isEmpty {
    // ... existing site name display ...
}
```

- [ ] **Step 2: Update ReaderView to hide "Open Original" for manual entries**

In `ReaderView.swift`, find the "Open Original" button in the bottom toolbar (around lines 362-372) and wrap it:

```swift
if article.url != nil {
    Button {
        openOriginal()
    } label: {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "safari")
            Text(String(localized: "reader.original", defaultValue: "Original"))
                .font(Typography.caption)
        }
    }
}
```

Also wrap the "Open Original" in the more menu (around lines 338-342):

```swift
if article.url != nil {
    Button {
        openOriginal()
    } label: {
        Label(String(localized: "reader.openInBrowser", defaultValue: "Open Original"), systemImage: "safari")
    }
}
```

- [ ] **Step 3: Build and visual test**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'
```

On simulator:
- Create a manual entry via input bar
- Verify card shows "My Thought" or "Pasted Content" instead of domain
- Tap into ReaderView — verify no "Open Original" button

- [ ] **Step 4: Commit**

```bash
git add ios/Folio/Presentation/Home/ArticleCardView.swift ios/Folio/Presentation/Reader/ReaderView.swift
git commit -m "feat(ios): show manual source label on cards, hide browser button in reader"
```

---

## Task Dependency Graph

```
Backend:                iOS:
  T1 (migration)         T10 (model)
    ↓                      ↓
  T2 (domain)            T11 (url optional adapt)
    ↓                      ↓
  T3 (repository)        T12 (network)
    ↓                      ↓
  T4 (service)           T13 (data layer)
    ↓                    ↙    ↘
  T5 (handler)        T14      T16
    ↓               (input)   (share ext)
  T6 (router)          ↓
    ↓                T15 (HomeView)
  T7 (worker)           ↓
    ↓                T17 (display)
  T8 (mock AI)
    ↓
  T9 (E2E tests)

Backend and iOS tracks are independent — can be parallelized.
```
