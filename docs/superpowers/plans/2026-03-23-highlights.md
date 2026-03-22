# Highlights + WKWebView Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftUI MarkdownRenderer with WKWebView-based article reader, add text highlighting with server sync and Echo integration.

**Architecture:** Markdown → HTML converter with dynamic CSS (reading preferences). WKWebView renders content, JS handles text selection + highlight rendering. Swift↔JS bridge for highlight CRUD, scroll progress, image/link interception. Backend CRUD API + Echo highlight card generation.

**Tech Stack:** Swift 5.9 / WKWebView / SwiftData / iOS 17.0 | Go 1.24 / chi v5 / pgx v5 / DeepSeek API

**Spec:** `docs/superpowers/specs/2026-03-23-highlights.md`

---

## File Map

### Backend (new)
- `server/internal/domain/highlight.go` — Highlight struct
- `server/internal/repository/highlight.go` — CRUD
- `server/internal/service/highlight.go` — create (with echo enqueue), delete
- `server/internal/api/handler/highlight.go` — HTTP handlers

### Backend (modify)
- `server/internal/api/router.go` — add highlight routes
- `server/cmd/server/main.go` — wire highlight dependencies
- `server/internal/worker/echo_handler.go` — support highlight card type

### iOS (new)
- `ios/Folio/Domain/Models/Highlight.swift` — SwiftData model
- `ios/Folio/Presentation/Reader/MarkdownToHTML.swift` — Markdown → HTML + CSS + JS
- `ios/Folio/Presentation/Reader/ArticleWebView.swift` — UIViewRepresentable WKWebView
- `ios/Folio/Presentation/Reader/article.css` — article styles (bundled resource)
- `ios/Folio/Presentation/Reader/article.js` — highlight + selection + scroll JS

### iOS (modify)
- `ios/Folio/Data/SwiftData/DataManager.swift` — register Highlight model
- `ios/Folio/Data/Network/Network.swift` — Highlight DTOs + APIClient methods
- `ios/Folio/Presentation/Reader/ReaderView.swift` — replace MarkdownRenderer with ArticleWebView
- `ios/Folio/Presentation/Reader/ReaderViewModel.swift` — add highlight state + API calls

---

## Task 1: Backend — Highlight Domain + Repository

**Files:**
- Create: `server/internal/domain/highlight.go`
- Create: `server/internal/repository/highlight.go`

- [ ] **Step 1: Create migration 009 for highlights table + unique index**

Create `server/migrations/009_highlights.up.sql`:
```sql
CREATE TABLE IF NOT EXISTS highlights (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    start_offset INTEGER NOT NULL,
    end_offset INTEGER NOT NULL,
    color VARCHAR(20) NOT NULL DEFAULT 'accent',
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_highlights_unique ON highlights (article_id, user_id, start_offset, end_offset);
CREATE INDEX IF NOT EXISTS idx_highlights_article ON highlights (article_id, user_id);
CREATE INDEX IF NOT EXISTS idx_highlights_user ON highlights (user_id, created_at DESC);
```

Create `server/migrations/009_highlights.down.sql`:
```sql
DROP TABLE IF EXISTS highlights;
```

Apply to dev DB:
```bash
cd server && docker compose -f docker-compose.local.yml exec -T postgres psql -U folio -d folio < migrations/009_highlights.up.sql
```

- [ ] **Step 2: Create domain/highlight.go**

```go
package domain

import "time"

type Highlight struct {
    ID          string
    ArticleID   string
    UserID      string
    Text        string
    StartOffset int
    EndOffset   int
    Color       string
    Note        *string
    CreatedAt   time.Time
}
```

- [ ] **Step 3: Create repository/highlight.go**

Methods:
- `CreateHighlight(ctx, h *Highlight) error` — INSERT with uuid cast, RETURNING id + created_at
- `GetByArticle(ctx, articleID, userID string) ([]Highlight, error)` — ORDER BY start_offset ASC
- `GetByID(ctx, id, userID string) (*Highlight, error)` — ownership check
- `DeleteHighlight(ctx, id, userID string) error` — DELETE with ownership check, return article_id for count update
- `IncrementArticleHighlightCount(ctx, articleID string) error`
- `DecrementArticleHighlightCount(ctx, articleID string) error`

Follow patterns from `repository/echo.go` — use `::uuid` casts for ID parameters.

- [ ] **Step 4: Build and commit**

```bash
cd server && go build ./... && echo "OK"
git add server/internal/domain/highlight.go server/internal/repository/highlight.go
git commit -m "feat: add Highlight domain model and repository"
```

---

## Task 2: Backend — Highlight Service + API + Routes

**Files:**
- Create: `server/internal/service/highlight.go`
- Create: `server/internal/api/handler/highlight.go`
- Modify: `server/internal/api/router.go`
- Modify: `server/cmd/server/main.go`

- [ ] **Step 0: Add crawl protection in crawl_handler.go**

Modify `server/internal/worker/crawl_handler.go`: at the start of `ProcessTask`, after fetching the article, check `articles.highlight_count > 0`. If true, skip re-crawling and return nil (article content is protected).

```go
// Early in ProcessTask, after fetching article:
if article.HighlightCount > 0 {
    log.Printf("[CRAWL] skipping re-crawl for article %s: has %d highlights", p.ArticleID, article.HighlightCount)
    return nil
}
```

Note: `Article` domain struct needs a `HighlightCount int` field (added in migration 008 column `highlight_count`). Verify `domain/article.go` has this field, add if not.

- [ ] **Step 1: Create service/highlight.go**

```go
type HighlightService struct {
    highlightRepo *repository.HighlightRepo
    articleRepo   *repository.ArticleRepo
    asynqClient   *asynq.Client
}
```

Methods:
- `CreateHighlight(ctx, userID, articleID, text string, startOffset, endOffset int) (*domain.Highlight, error)` — verify article ownership → insert → increment count → enqueue echo:generate with highlight_id
- `GetArticleHighlights(ctx, userID, articleID string) ([]domain.Highlight, error)`
- `DeleteHighlight(ctx, userID, highlightID string) error` — get highlight → delete → decrement count

- [ ] **Step 2: Create handler/highlight.go**

Handlers:
- `HandleCreateHighlight` — POST /api/v1/articles/{id}/highlights — parse body {text, start_offset, end_offset}, call service, respond with HighlightDTO
- `HandleGetHighlights` — GET /api/v1/articles/{id}/highlights — call service, respond with {data: [...]}
- `HandleDeleteHighlight` — DELETE /api/v1/highlights/{id} — call service, respond 204

- [ ] **Step 3: Register routes in router.go**

Add to protected group:
```go
r.Post("/articles/{id}/highlights", deps.HighlightHandler.HandleCreateHighlight)
r.Get("/articles/{id}/highlights", deps.HighlightHandler.HandleGetHighlights)
r.Delete("/highlights/{id}", deps.HighlightHandler.HandleDeleteHighlight)
```

Add `HighlightHandler *handler.HighlightHandler` to RouterDeps.

- [ ] **Step 4: Wire in main.go**

```go
highlightRepo := repository.NewHighlightRepo(pool)
highlightService := service.NewHighlightService(highlightRepo, articleRepo, asynqClient)
highlightHandler := handler.NewHighlightHandler(highlightService)
```

- [ ] **Step 5: Build and commit**

```bash
cd server && go build ./cmd/server && echo "OK"
git add server/internal/service/highlight.go server/internal/api/handler/highlight.go server/internal/api/router.go server/cmd/server/main.go
git commit -m "feat: add Highlight API (POST/GET/DELETE) with Echo integration"
```

---

## Task 3: Backend — Echo Highlight Card Support

**Files:**
- Modify: `server/internal/worker/echo_handler.go`
- Modify: `server/internal/worker/tasks.go`

- [ ] **Step 1: Extend EchoPayload with optional HighlightID**

In `tasks.go`, add to `EchoPayload`:
```go
type EchoPayload struct {
    ArticleID   string `json:"article_id"`
    UserID      string `json:"user_id"`
    HighlightID string `json:"highlight_id,omitempty"` // new
}
```

Update `NewEchoTask` to accept optional highlightID. **Existing callers** (in `ai_handler.go`) must be updated to pass `""` for highlightID.

- [ ] **Step 2: Add highlightRepo to EchoHandler**

The `EchoHandler` struct needs a highlight repository to fetch highlight text for highlight-type cards. Add `highlightRepo` to the struct, update `NewEchoHandler` constructor, and update wiring in `cmd/server/main.go` to pass `highlightRepo`.

- [ ] **Step 3: Update echo_handler.go ProcessTask**

When `payload.HighlightID` is non-empty:
- Fetch the highlight text from DB
- Generate a `card_type = 'highlight'` card
- AI prompt: "你在一篇关于 {topic} 的文章中标注了一句话。还记得你标注的原文是什么吗？"
- answer = highlight text
- source_context = "你在 {date} 标注了这段文字 · 来自《{title}》"
- Set `echo_cards.highlight_id = highlightID`

When `payload.HighlightID` is empty → existing insight card logic (unchanged).

- [ ] **Step 4: Build and commit**

```bash
cd server && go build ./... && echo "OK"
git add server/internal/worker/echo_handler.go server/internal/worker/tasks.go server/internal/worker/ai_handler.go server/cmd/server/main.go
git commit -m "feat: support highlight-type Echo cards in echo:generate worker"
```

---

## Task 4: iOS — Highlight Model + DTOs

**Files:**
- Create: `ios/Folio/Domain/Models/Highlight.swift`
- Modify: `ios/Folio/Data/SwiftData/DataManager.swift`
- Modify: `ios/Folio/Data/Network/Network.swift`

- [ ] **Step 1: Create Highlight SwiftData model**

```swift
@Model
final class Highlight {
    @Attribute(.unique) var id: UUID
    var serverID: String?
    var articleID: UUID
    var text: String
    var startOffset: Int
    var endOffset: Int
    var color: String
    var createdAt: Date
    var isSynced: Bool  // false until server confirms

    init(id: UUID = UUID(), serverID: String? = nil, articleID: UUID,
         text: String, startOffset: Int, endOffset: Int,
         color: String = "accent", isSynced: Bool = false) { ... }
}
```

Register in `DataManager.modelTypes`.

- [ ] **Step 2: Add DTOs + APIClient methods**

```swift
struct HighlightDTO: Codable { id, text, startOffset, endOffset, color, createdAt }
struct CreateHighlightRequest: Codable { text, startOffset, endOffset }
struct HighlightsResponse: Codable { data: [HighlightDTO] }

func createHighlight(articleID: String, text: String, startOffset: Int, endOffset: Int) async throws -> HighlightDTO
func getHighlights(articleID: String) async throws -> HighlightsResponse
func deleteHighlight(id: String) async throws
```

- [ ] **Step 3: Build and commit**

---

## Task 5: iOS — MarkdownToHTML Converter

**Files:**
- Create: `ios/Folio/Presentation/Reader/MarkdownToHTML.swift`

- [ ] **Step 1: Create the converter**

A function that takes markdown + reading preferences + highlights and returns a complete HTML document string:

```swift
struct MarkdownToHTML {
    static func convert(
        markdown: String,
        title: String?,
        highlights: [Highlight],
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        fontFamily: ReadingFontFamily,
        theme: ReadingTheme
    ) -> String
}
```

**Implementation:**
1. Preprocess markdown (strip title, metadata — reuse `MarkdownRenderer.preprocessed`)
2. Convert Markdown → HTML (use `swift-markdown` library's HTML visitor, or a simple regex-based converter for: headings, paragraphs, bold, italic, code, blockquote, lists, images, links, tables, hr)
3. Wrap in HTML template:
   - `<head>`: meta viewport, inline CSS with dynamic variables
   - `<body class="{theme}">`: article content
   - `<script>`: article.js content (inline for single-string loading)
4. Inject highlights as `<mark>` tags at the correct character offsets
5. CSS variables from preferences:
   - `--font-size: {fontSize}px`
   - `--line-height: {lineSpacing ratio}`
   - `--font-family: {fontFamily CSS name}`
   - Theme colors (bg, text, secondary, accent, etc.)

**CSS must cover:** body, h1-h6, p, blockquote, pre/code, table, img, a, ul/ol/li, hr, mark.hl, .hl-popup — all matching prototype 04 styles.

**Note:** The CSS and JS can be inline strings in the Swift file, or loaded from bundled resource files. Inline is simpler for a single-file converter.

- [ ] **Step 2: Build and commit**

---

## Task 6: iOS — article.js (Highlight + Selection + Scroll)

**Files:**
- Create: `ios/Folio/Presentation/Reader/ArticleJS.swift` (JS as a Swift string constant)

Or if preferred, create `ios/Folio/Resources/article.js` as a bundled file.

- [ ] **Step 1: Implement the JS**

**Text selection → highlight menu:**
```javascript
document.addEventListener('touchend', function(e) {
    setTimeout(function() {
        var sel = window.getSelection();
        if (!sel || sel.isCollapsed || sel.toString().trim().length < 3) return;
        if (sel.anchorNode.closest && sel.anchorNode.closest('.hl')) return;
        showMenu(sel, 'create'); // "高亮" + "复制"
    }, 200);
});
```

**Offset calculation:**
```javascript
function getTextOffset(node, offset) {
    var body = document.querySelector('.article-body');
    var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
    var pos = 0;
    while (walker.nextNode()) {
        if (walker.currentNode === node) return pos + offset;
        pos += walker.currentNode.length;
    }
    return pos;
}
```

**Highlight creation:**
```javascript
function createHighlight(id, start, end) {
    // Walk text nodes, find start/end positions, wrap in <mark class="hl" data-id="id">
}
```

**Highlight removal:**
```javascript
function removeHighlight(id) {
    var mark = document.querySelector('.hl[data-id="' + id + '"]');
    if (mark) { mark.outerHTML = mark.innerHTML; }
}
```

**Menu (floating popup):**
- Position above selection/highlight using `getBoundingClientRect()`
- "高亮" → create mark + postMessage `highlight.create` + postMessage `{ type: "toast", message: "已高亮" }`
- "复制" → `navigator.clipboard.writeText()` + postMessage `{ type: "toast", message: "已复制" }`
- "移除高亮" → removeHighlight + postMessage `highlight.remove` + postMessage `{ type: "toast", message: "已移除高亮" }`
- Click elsewhere → close menu

**Scroll progress:**
```javascript
window.addEventListener('scroll', throttle(function() {
    var pct = window.scrollY / (document.body.scrollHeight - window.innerHeight);
    window.webkit.messageHandlers.folio.postMessage({type:'scroll.progress', percent: pct});
}, 100));
```

**Image click:**
```javascript
document.addEventListener('click', function(e) {
    if (e.target.tagName === 'IMG') {
        window.webkit.messageHandlers.folio.postMessage({type:'image.tap', src: e.target.src});
    }
});
```

**Link click interception:**
```javascript
document.addEventListener('click', function(e) {
    var a = e.target.closest('a');
    if (a) {
        e.preventDefault();
        window.webkit.messageHandlers.folio.postMessage({type:'link.tap', href: a.href});
    }
});
```

**Scroll restoration:**
```javascript
function scrollToProgress(pct) {
    window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * pct);
}
```

**Theme/preference update:**
```javascript
function setPreferences(fontSize, lineHeight, fontFamily, theme) {
    document.documentElement.style.setProperty('--font-size', fontSize + 'px');
    // ... etc
}
```

- [ ] **Step 2: Build and commit**

---

## Task 7: iOS — ArticleWebView (UIViewRepresentable)

**Files:**
- Create: `ios/Folio/Presentation/Reader/ArticleWebView.swift`

- [ ] **Step 1: Create ArticleWebView**

```swift
struct ArticleWebView: UIViewRepresentable {
    let htmlContent: String
    let initialProgress: Double
    let onHighlightCreate: (String, Int, Int) -> Void  // text, start, end
    let onHighlightRemove: (String) -> Void             // highlightId
    let onScrollProgress: (Double) -> Void
    let onImageTap: (String) -> Void                    // image src
    let onLinkTap: (String) -> Void                     // href
    let onToast: (String) -> Void                       // toast message
}
```

**makeUIView:**
- Create WKWebView with WKUserContentController
- Register message handler "folio" (WKScriptMessageHandler)
- Disable default context menu
- Set `isOpaque = false`, `backgroundColor = .clear`
- Load HTML string

**Coordinator (WKScriptMessageHandler):**
- Parse JSON messages from JS
- Dispatch to appropriate callback based on `type`

**updateUIView:**
- If htmlContent changed → reload
- If preferences changed → call `evaluateJavaScript("setPreferences(...)")`

**WKNavigationDelegate:**
- `decidePolicyFor` → block all external navigation (`.cancel`)
- Use callbacks for link/image taps instead

- [ ] **Step 2: Build and commit**

---

## Task 8: iOS — ReaderView Integration

**Files:**
- Modify: `ios/Folio/Presentation/Reader/ReaderView.swift`
- Modify: `ios/Folio/Presentation/Reader/ReaderViewModel.swift`

This is the largest task — replaces MarkdownRenderer with ArticleWebView and adds highlight management.

- [ ] **Step 1: Add highlight state to ReaderViewModel**

```swift
var highlights: [Highlight] = []

func fetchHighlights() async {
    guard let serverID = article.serverID else { return }
    do {
        let response = try await apiClient.getHighlights(articleID: serverID)
        // Map DTOs to local Highlight models or store as DTOs
        highlights = response.data.map { ... }
    } catch { /* silent */ }
}

func createHighlight(text: String, startOffset: Int, endOffset: Int) {
    // 1. Create local Highlight (isSynced = false)
    // 2. Add to highlights array
    // 3. Async POST to server
    // 4. On success: update serverID + isSynced
}

func deleteHighlight(id: String) {
    // 1. Remove from local highlights
    // 2. Async DELETE from server
}
```

- [ ] **Step 2: Replace MarkdownRenderer with ArticleWebView in ReaderView**

In the content area (where `MarkdownRenderer` is currently used), replace with:

```swift
if let markdown = article.markdownContent {
    let html = MarkdownToHTML.convert(
        markdown: markdown,
        title: article.title,
        highlights: viewModel?.highlights ?? [],
        fontSize: fontSize,
        lineSpacing: lineSpacing,
        fontFamily: fontFamily,
        theme: readingTheme
    )
    ArticleWebView(
        htmlContent: html,
        initialProgress: article.readProgress,
        onHighlightCreate: { text, start, end in
            viewModel?.createHighlight(text: text, startOffset: start, endOffset: end)
        },
        onHighlightRemove: { id in
            viewModel?.deleteHighlight(id: id)
        },
        onScrollProgress: { progress in
            viewModel?.updateReadingProgress(progress)
        },
        onImageTap: { src in
            // Show ImageViewerOverlay
        },
        onLinkTap: { href in
            // Open in Safari/WebViewContainer
        },
        onToast: { message in
            viewModel?.showToastMessage(message, icon: nil)
        }
    )
}
```

- [ ] **Step 3: Preserve existing features**

Keep:
- Insight panel (above the WebView)
- Article header (title + meta info, above the WebView)
- Bottom toolbar (progress %, globe, share)
- Menu sheet (favorite, copy markdown, etc.)
- Reading progress bar at top
- Entrance animation (container opacity transition after WebView loads)
- Delete confirmation
- Toast notifications

The article header + insight panel remain native SwiftUI. Only the article body (markdown content) is replaced by WebView.

- [ ] **Step 4: Fetch highlights on appear**

In ReaderView's `.task` or `.onAppear`:
```swift
Task { await viewModel?.fetchHighlights() }
```

- [ ] **Step 5: Build, test on simulator, commit**

```bash
cd ios && xcodegen generate
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

---

## Task 9: End-to-End Test

- [ ] **Step 1: Test backend highlight API**

```bash
# Create highlight
curl -s -X POST "http://localhost:8080/api/v1/articles/{id}/highlights" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"test highlight","start_offset":100,"end_offset":114}'

# Get highlights
curl -s "http://localhost:8080/api/v1/articles/{id}/highlights" \
  -H "Authorization: Bearer $TOKEN"

# Delete highlight
curl -s -X DELETE "http://localhost:8080/api/v1/highlights/{hid}" \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] **Step 2: Test on simulator**

1. Build and install iOS app
2. Open an article in Reader
3. Verify content renders correctly in WebView (fonts, spacing, images, code blocks)
4. Select text → verify "高亮/复制" menu appears
5. Tap "高亮" → verify highlight appears (accent background)
6. Tap highlighted text → verify "移除高亮/复制" menu
7. Tap "移除高亮" → verify highlight removed + toast
8. Scroll → verify progress bar updates
9. Change reading preferences → verify WebView updates dynamically

- [ ] **Step 3: Verify Echo highlight card generation**

After creating a highlight, wait 30s, then check echo_cards for a `card_type='highlight'` entry.

- [ ] **Step 4: Commit any fixes**

---

## Execution Order

```
Task 1 (domain + repo) → Task 2 (service + API + routes) → Task 3 (echo support)
    → Task 4 (iOS model + DTOs) → Task 5 (MarkdownToHTML) → Task 6 (article.js)
        → Task 7 (ArticleWebView) → Task 8 (ReaderView integration) → Task 9 (E2E test)
```

All tasks are sequential. Task 8 is the largest and highest risk (Reader rewrite integration).

---

## Risk Notes

- **Task 5 (MarkdownToHTML)** is the most complex new code — Markdown → HTML conversion must handle all block types correctly. Consider using `swift-markdown`'s HTML visitor if available, or a well-tested regex pipeline.
- **Task 8 (ReaderView integration)** touches the largest existing file. Read it thoroughly before editing. Keep the native SwiftUI header/toolbar/insight panel — only replace the body content area.
- **WKWebView scroll tracking** may have edge cases (content not fully loaded, dynamic height changes). Test thoroughly.
- **Existing `MarkdownRenderer`** is NOT deleted — it stays for potential use elsewhere. The import/reference in ReaderView changes but the file remains.
