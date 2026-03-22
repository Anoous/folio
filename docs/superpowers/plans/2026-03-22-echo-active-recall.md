# Echo Active Recall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Echo spaced repetition system — AI generates recall cards from article key_points, cards appear in Home Feed, users interact (reveal answer → remembered/forgot), SM-2 algorithm schedules next review.

**Architecture:** Backend: new Worker task `echo:generate` chained after `article:ai`, new service/repository/handler layer for Echo CRUD + SM-2. iOS: new SwiftData model, EchoCardView with 4-step state machine, HomeView feed interleaving.

**Tech Stack:** Go 1.24 / chi v5 / asynq / pgx v5 / DeepSeek API | Swift 5.9 / SwiftUI / SwiftData / iOS 17.0

**Spec:** `docs/superpowers/specs/2026-03-22-echo-active-recall.md`

---

## File Map

### Backend (new files)
- `server/internal/domain/echo.go` — EchoCard + EchoReview structs, EchoResult enum
- `server/internal/repository/echo.go` — DB operations for echo_cards + echo_reviews
- `server/internal/service/echo.go` — SM-2 algorithm, streak calculation, quota check
- `server/internal/api/handler/echo.go` — HTTP handlers (GetToday, SubmitReview)
- `server/internal/worker/echo_handler.go` — echo:generate Worker task processor

### Backend (modify)
- `server/internal/worker/tasks.go` — add TypeEchoGenerate + EchoPayload + NewEchoTask
- `server/internal/worker/ai_handler.go` — chain echo:generate after AI success
- `server/internal/worker/server.go` — register echo handler
- `server/internal/api/router.go` — add echo routes
- `server/cmd/server/main.go` — wire up echo dependencies

### iOS (new files)
- `ios/Folio/Domain/Models/EchoCard.swift` — SwiftData model
- `ios/Folio/Presentation/Home/EchoCardView.swift` — 4-step interaction UI

### iOS (modify)
- `ios/Folio/Data/SwiftData/DataManager.swift` — register EchoCard in schema
- `ios/Folio/Data/Network/Network.swift` — add Echo DTOs + APIClient methods
- `ios/Folio/Presentation/Home/HomeViewModel.swift` — add echoCards + feed interleaving
- `ios/Folio/Presentation/Home/HomeView.swift` — render mixed feed (articles + echo cards)

---

## Task 1: Backend — Echo Domain Model

**Files:**
- Create: `server/internal/domain/echo.go`

- [ ] **Step 1: Create domain structs**

```go
// server/internal/domain/echo.go
package domain

import "time"

type EchoCardType string

const (
    EchoCardInsight   EchoCardType = "insight"
    EchoCardHighlight EchoCardType = "highlight"
    EchoCardRelated   EchoCardType = "related"
)

type EchoReviewResult string

const (
    EchoRemembered EchoReviewResult = "remembered"
    EchoForgot     EchoReviewResult = "forgot"
)

type EchoCard struct {
    ID               string
    UserID           string
    ArticleID        string
    CardType         EchoCardType
    Question         string
    Answer           string
    SourceContext    *string
    NextReviewAt     time.Time
    IntervalDays     int
    EaseFactor       float64
    ReviewCount      int
    CorrectCount     int
    RelatedArticleID *string
    HighlightID      *string
    CreatedAt        time.Time
    UpdatedAt        time.Time
    // Joined fields (not stored directly)
    ArticleTitle     string
}

type EchoReview struct {
    ID             string
    CardID         string
    UserID         string
    Result         EchoReviewResult
    ResponseTimeMs *int
    ReviewedAt     time.Time
}

type EchoStreak struct {
    WeeklyRate      int    // 0-100
    ConsecutiveDays int
    Display         string // "本周回忆率 85% · 已连续 7 天"
}
```

- [ ] **Step 2: Build**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add server/internal/domain/echo.go
git commit -m "feat: add Echo domain model (EchoCard, EchoReview, EchoStreak)"
```

---

## Task 2: Backend — Echo Repository

**Files:**
- Create: `server/internal/repository/echo.go`

- [ ] **Step 1: Create repository with CRUD + query operations**

```go
// server/internal/repository/echo.go
package repository

// EchoRepo handles echo_cards and echo_reviews tables.
type EchoRepo struct {
    db *pgxpool.Pool
}

func NewEchoRepo(db *pgxpool.Pool) *EchoRepo

// CreateCard inserts a new echo card.
func (r *EchoRepo) CreateCard(ctx context.Context, card *domain.EchoCard) error

// GetDueCards returns cards where next_review_at <= now for a user, ordered by next_review_at ASC.
func (r *EchoRepo) GetDueCards(ctx context.Context, userID string, limit int) ([]domain.EchoCard, error)
// JOIN articles ON echo_cards.article_id = articles.id to get article_title

// GetCardByID returns a single card by ID, verifying user ownership.
func (r *EchoRepo) GetCardByID(ctx context.Context, cardID, userID string) (*domain.EchoCard, error)

// UpdateCard updates SM-2 fields (interval_days, ease_factor, next_review_at, review_count, correct_count).
func (r *EchoRepo) UpdateCard(ctx context.Context, card *domain.EchoCard) error

// CreateReview inserts an echo_reviews record.
func (r *EchoRepo) CreateReview(ctx context.Context, review *domain.EchoReview) error

// GetWeeklyStats returns (remembered_count, total_count) for the current week for a user.
func (r *EchoRepo) GetWeeklyStats(ctx context.Context, userID string) (remembered, total int, err error)

// GetConsecutiveDays returns the number of consecutive days with at least one review.
func (r *EchoRepo) GetConsecutiveDays(ctx context.Context, userID string) (int, error)

// CountCardsByArticle returns how many echo cards exist for an article (to avoid duplicates).
func (r *EchoRepo) CountCardsByArticle(ctx context.Context, articleID string) (int, error)
```

Implement each method using pgx queries against the `echo_cards` and `echo_reviews` tables created in migration 008.

- [ ] **Step 2: Build**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add server/internal/repository/echo.go
git commit -m "feat: add Echo repository (CRUD for echo_cards + echo_reviews)"
```

---

## Task 3: Backend — Echo Service (SM-2 + Streak)

**Files:**
- Create: `server/internal/service/echo.go`

- [ ] **Step 1: Create service with SM-2 logic and streak calculation**

```go
// server/internal/service/echo.go
package service

type EchoService struct {
    echoRepo    *repository.EchoRepo
    articleRepo *repository.ArticleRepo
    userRepo    *repository.UserRepo
}

func NewEchoService(echoRepo *repository.EchoRepo, articleRepo *repository.ArticleRepo, userRepo *repository.UserRepo) *EchoService

// GetTodayCards returns due echo cards for a user, respecting Free quota.
// Free users: first check if echo_week_reset_at < start of this Monday — if so,
// reset echo_count_this_week to 0 and set echo_week_reset_at to next Monday 00:00.
// Then check echo_count_this_week against weekly limit (3).
// Returns cards + remaining_today + weekly_count + weekly_limit.
func (s *EchoService) GetTodayCards(ctx context.Context, userID string, limit int) (cards []domain.EchoCard, remaining int, weeklyCount int, weeklyLimit *int, err error)

// SubmitReview processes a review: runs SM-2, creates review record, updates quota, returns streak.
func (s *EchoService) SubmitReview(ctx context.Context, userID, cardID string, result domain.EchoReviewResult, responseTimeMs *int) (*ReviewResult, error)

type ReviewResult struct {
    NextReviewAt time.Time
    IntervalDays int
    ReviewCount  int
    CorrectCount int
    Streak       domain.EchoStreak
}

// updateSM2 applies the SM-2 algorithm to a card.
func updateSM2(card *domain.EchoCard, result domain.EchoReviewResult) {
    card.ReviewCount++
    if result == domain.EchoRemembered {
        card.CorrectCount++
        switch card.ReviewCount {
        case 1:
            card.IntervalDays = 1
        case 2:
            card.IntervalDays = 3
        default:
            card.IntervalDays = int(math.Round(float64(card.IntervalDays) * card.EaseFactor))
        }
        card.EaseFactor = math.Min(3.0, card.EaseFactor+0.1)
    } else {
        card.IntervalDays = 1
        card.EaseFactor = math.Max(1.3, card.EaseFactor-0.2)
    }
    card.NextReviewAt = time.Now().Add(time.Duration(card.IntervalDays) * 24 * time.Hour)
}

// buildStreak aggregates weekly stats and consecutive days into EchoStreak.
func (s *EchoService) buildStreak(ctx context.Context, userID string) (domain.EchoStreak, error)
```

- [ ] **Step 2: Build**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add server/internal/service/echo.go
git commit -m "feat: add Echo service (SM-2 algorithm + streak calculation)"
```

---

## Task 4: Backend — Echo Worker (echo:generate)

**Files:**
- Create: `server/internal/worker/echo_handler.go`
- Modify: `server/internal/worker/tasks.go`

- [ ] **Step 1: Add task type and payload to tasks.go**

Add to `server/internal/worker/tasks.go`:

```go
const TypeEchoGenerate = "echo:generate"

type EchoPayload struct {
    ArticleID string `json:"article_id"`
    UserID    string `json:"user_id"`
}

func NewEchoTask(articleID, userID string) (*asynq.Task, error) {
    payload, err := json.Marshal(EchoPayload{ArticleID: articleID, UserID: userID})
    if err != nil {
        return nil, err
    }
    return asynq.NewTask(TypeEchoGenerate, payload,
        asynq.Queue(QueueDefault),
        asynq.MaxRetry(2),
        asynq.Timeout(30*time.Second),
    ), nil
}
```

- [ ] **Step 2: Create echo_handler.go**

```go
// server/internal/worker/echo_handler.go
package worker

type EchoHandler struct {
    aiClient    client.Analyzer  // reuse existing DeepSeek client
    articleRepo *repository.ArticleRepo
    echoRepo   *repository.EchoRepo
}

func NewEchoHandler(aiClient client.Analyzer, articleRepo *repository.ArticleRepo, echoRepo *repository.EchoRepo) *EchoHandler

func (h *EchoHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
    // 1. Unmarshal payload
    // 2. Fetch article (need title, key_points, site_name, created_at)
    // 3. Skip if article has no key_points
    // 4. Skip if echo cards already exist for this article (CountCardsByArticle > 0)
    // 5. Call AI to generate question/answer pairs from key_points
    //    - Use a dedicated prompt (see spec) via h.aiClient.Analyze or direct DeepSeek call
    //    - Parse JSON array response: [{"question":"...", "answer":"...", "source_context":"..."}]
    // 6. Insert 1-2 EchoCard records with card_type='insight', next_review_at=now+1day
    // 7. Increment articles.echo_card_count
}
```

**Echo AI call approach:** Do NOT reuse the `Analyzer` interface (it returns category/tags/summary, not question/answer pairs). Instead, add a new method `GenerateEchoCards` directly on `DeepSeekAnalyzer` (not on the `Analyzer` interface). This method makes its own DeepSeek chat completions call with the Echo-specific prompt from the spec, parses a JSON array response `[{"question":"...", "answer":"...", "source_context":"..."}]`, and returns `[]EchoQAPair`. Define `EchoQAPair` struct in `client/ai.go`. The `EchoHandler` takes a `*client.DeepSeekAnalyzer` (concrete type, not interface) since the mock analyzer doesn't need Echo generation.

- [ ] **Step 3: Build**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 4: Commit**

```bash
git add server/internal/worker/echo_handler.go server/internal/worker/tasks.go
git commit -m "feat: add echo:generate Worker task handler"
```

---

## Task 5: Backend — Chain Echo from AI Worker + Wire Up

**Files:**
- Modify: `server/internal/worker/ai_handler.go` — enqueue echo task after AI success
- Modify: `server/internal/worker/server.go` — register echo handler
- Modify: `server/cmd/server/main.go` — instantiate and wire echo dependencies

- [ ] **Step 1: Chain echo:generate from ai_handler.go**

At the end of `AIHandler.ProcessTask`, after successful AI analysis, add:

```go
// Enqueue echo card generation (non-blocking, error is OK)
echoTask, err := NewEchoTask(p.ArticleID, p.UserID)
if err == nil {
    if _, err := h.asynqClient.EnqueueContext(ctx, echoTask); err != nil {
        log.Printf("[ECHO] failed to enqueue echo:generate for article %s: %v", p.ArticleID, err)
    }
}
```

`AIHandler` does NOT currently have an `asynqClient` field (verified). You MUST:
1. Add `asynqClient *asynq.Client` field to the `AIHandler` struct in `ai_handler.go`
2. Add it as a parameter to `NewAIHandler()` constructor
3. Update the `NewAIHandler()` call in `cmd/server/main.go` to pass the existing `asynqClient`

- [ ] **Step 2: Register in server.go**

In `NewWorkerServer`, add echo handler parameter and register:
```go
mux.HandleFunc(TypeEchoGenerate, echo.ProcessTask)
```

- [ ] **Step 3: Wire up in main.go**

In `cmd/server/main.go`, instantiate:
```go
echoRepo := repository.NewEchoRepo(db)
echoHandler := worker.NewEchoHandler(aiClient, articleRepo, echoRepo)
// Pass to NewWorkerServer
```

- [ ] **Step 4: Build and verify**

```bash
cd server && go build ./cmd/server && echo "OK"
```

- [ ] **Step 5: Commit**

```bash
git add server/internal/worker/ai_handler.go server/internal/worker/server.go server/cmd/server/main.go
git commit -m "feat: chain echo:generate from AI worker, wire up dependencies"
```

---

## Task 6: Backend — Echo API Handler + Routes

**Files:**
- Create: `server/internal/api/handler/echo.go`
- Modify: `server/internal/api/router.go`

- [ ] **Step 1: Create echo handler**

```go
// server/internal/api/handler/echo.go
package handler

type EchoHandler struct {
    echoService *service.EchoService
}

func NewEchoHandler(echoService *service.EchoService) *EchoHandler

// HandleGetToday handles GET /api/v1/echo/today
func (h *EchoHandler) HandleGetToday(w http.ResponseWriter, r *http.Request) {
    userID := middleware.GetUserID(r.Context())
    limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
    if limit <= 0 { limit = 5 }
    cards, remaining, weeklyCount, weeklyLimit, err := h.echoService.GetTodayCards(r.Context(), userID, limit)
    // Marshal and respond with JSON matching spec format
}

// HandleSubmitReview handles POST /api/v1/echo/{id}/review
func (h *EchoHandler) HandleSubmitReview(w http.ResponseWriter, r *http.Request) {
    userID := middleware.GetUserID(r.Context())
    cardID := chi.URLParam(r, "id")
    // Decode request body: { "result": "remembered"|"forgot", "response_time_ms": int }
    // Call echoService.SubmitReview
    // Marshal and respond with JSON matching spec format (including streak)
}
```

- [ ] **Step 2: Register routes in router.go**

Add to the protected route group in `router.go`:
```go
r.Get("/echo/today", deps.EchoHandler.HandleGetToday)
r.Post("/echo/{id}/review", deps.EchoHandler.HandleSubmitReview)
```

Add `EchoHandler *handler.EchoHandler` to `RouterDeps`.

- [ ] **Step 3: Wire up in main.go**

```go
echoService := service.NewEchoService(echoRepo, articleRepo, userRepo)
echoAPIHandler := handler.NewEchoHandler(echoService)
// Add to RouterDeps
```

- [ ] **Step 4: Build**

```bash
cd server && go build ./cmd/server && echo "OK"
```

- [ ] **Step 5: Test with curl**

```bash
# After starting server with dev-start.sh:
# 1. Get auth token
# 2. Submit an article, wait for AI + Echo processing
# 3. Fetch echo cards
curl -s http://localhost:8080/api/v1/echo/today -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

- [ ] **Step 6: Commit**

```bash
git add server/internal/api/handler/echo.go server/internal/api/router.go server/cmd/server/main.go
git commit -m "feat: add Echo API endpoints (GET /echo/today, POST /echo/{id}/review)"
```

---

## Task 7: iOS — EchoCard SwiftData Model

**Files:**
- Create: `ios/Folio/Domain/Models/EchoCard.swift`
- Modify: `ios/Folio/Data/SwiftData/DataManager.swift`

- [ ] **Step 1: Create EchoCard model**

```swift
// ios/Folio/Domain/Models/EchoCard.swift
import Foundation
import SwiftData

@Model
final class EchoCard {
    @Attribute(.unique) var id: UUID
    var serverID: String?
    var articleID: UUID
    var articleTitle: String
    var cardTypeRaw: String
    var question: String
    var answer: String
    var sourceContext: String?
    var nextReviewAt: Date
    var intervalDays: Int
    var reviewCount: Int
    var correctCount: Int
    var createdAt: Date

    var cardType: EchoCardType {
        EchoCardType(rawValue: cardTypeRaw) ?? .insight
    }

    init(id: UUID = UUID(), serverID: String? = nil, articleID: UUID, articleTitle: String,
         cardType: EchoCardType = .insight, question: String, answer: String,
         sourceContext: String? = nil, nextReviewAt: Date = Date().addingTimeInterval(86400),
         intervalDays: Int = 1, reviewCount: Int = 0, correctCount: Int = 0) {
        self.id = id
        self.serverID = serverID
        self.articleID = articleID
        self.articleTitle = articleTitle
        self.cardTypeRaw = cardType.rawValue
        self.question = question
        self.answer = answer
        self.sourceContext = sourceContext
        self.nextReviewAt = nextReviewAt
        self.intervalDays = intervalDays
        self.reviewCount = reviewCount
        self.correctCount = correctCount
        self.createdAt = Date()
    }
}

enum EchoCardType: String {
    case insight
    case highlight
    case related
}
```

- [ ] **Step 2: Register in DataManager.schema**

In `DataManager.swift`, add `EchoCard.self` to `modelTypes` array.

- [ ] **Step 3: Run xcodegen + build**

```bash
cd ios && xcodegen generate
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep "error:" | head -5
```

- [ ] **Step 4: Commit**

```bash
git add ios/Folio/Domain/Models/EchoCard.swift ios/Folio/Data/SwiftData/DataManager.swift
git commit -m "feat: add EchoCard SwiftData model"
```

---

## Task 8: iOS — Echo DTOs + APIClient Methods

**Files:**
- Modify: `ios/Folio/Data/Network/Network.swift`

- [ ] **Step 1: Add Echo DTOs**

Add to `Network.swift`:

```swift
// MARK: - Echo DTOs

struct EchoCardDTO: Codable {
    let id: String
    let articleId: String
    let articleTitle: String
    let cardType: String
    let question: String
    let answer: String
    let sourceContext: String?
    let nextReviewAt: Date
    let intervalDays: Int
    let reviewCount: Int
}

struct EchoTodayResponse: Codable {
    let data: [EchoCardDTO]
    let remainingToday: Int
    let weeklyCount: Int
    let weeklyLimit: Int?
}

struct EchoReviewRequest: Codable {
    let result: String
    let responseTimeMs: Int?
}

struct EchoReviewResponse: Codable {
    let nextReviewAt: Date
    let intervalDays: Int
    let reviewCount: Int
    let correctCount: Int
    let streak: EchoStreak
}

struct EchoStreak: Codable {
    let weeklyRate: Int
    let consecutiveDays: Int
    let display: String
}
```

- [ ] **Step 2: Add APIClient methods**

```swift
// MARK: - Echo

func getEchoToday(limit: Int = 5) async throws -> EchoTodayResponse {
    return try await request(method: "GET", path: "/api/v1/echo/today", queryItems: [
        URLQueryItem(name: "limit", value: "\(limit)")
    ])
}

func submitEchoReview(cardID: String, result: String, responseTimeMs: Int? = nil) async throws -> EchoReviewResponse {
    let body = EchoReviewRequest(result: result, responseTimeMs: responseTimeMs)
    return try await request(method: "POST", path: "/api/v1/echo/\(cardID)/review", body: body)
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep "error:" | head -5
```

- [ ] **Step 4: Commit**

```bash
git add ios/Folio/Data/Network/Network.swift
git commit -m "feat: add Echo DTOs and APIClient methods"
```

---

## Task 9: iOS — EchoCardView (4-Step Interaction)

**Files:**
- Create: `ios/Folio/Presentation/Home/EchoCardView.swift`

- [ ] **Step 1: Create EchoCardView**

Build the 4-step state machine matching prototype 01's Home Feed Echo card exactly. Reference the spec section "2. EchoCardView（新增）" for all pixel values.

Key structure:
```swift
struct EchoCardView: View {
    let card: EchoCard
    let onReview: (String) -> Void  // "remembered" or "forgot"

    @State private var step: Int = 0  // 0=question, 1=revealed, 2=confirmed
    @State private var reviewResult: String?
    @State private var streakDisplay: String?

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case 0: questionView
            case 1: revealedView
            default: confirmedView
            }
        }
        .padding(step == 2 ? 18 : (step == 1 ? 24 : 28))
        .padding(.horizontal, step == 2 ? 24 : (step == 1 ? 0 : 0)) // adjust per step
        .background(Color.folio.echoBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, 12)
    }
}
```

Step 0 (question): ✦ ECHO label + question text + source + "揭晓答案" button
Step 1 (revealed): dimmed question + answer with accent bar + source + 记得/忘了 buttons
Step 2 (confirmed): "✓ 已记录 · 下次 X 后回顾" + streak line

Animations:
- Step 0→1: `withAnimation(Motion.settle)`
- Step 1→2: `withAnimation(Motion.exit)`

- [ ] **Step 2: Run xcodegen + build**

```bash
cd ios && xcodegen generate
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep "error:" | head -5
```

- [ ] **Step 3: Commit**

```bash
git add ios/Folio/Presentation/Home/EchoCardView.swift
git commit -m "feat: add EchoCardView with 4-step interaction state machine"
```

---

## Task 10: iOS — HomeView Feed Interleaving

**Files:**
- Modify: `ios/Folio/Presentation/Home/HomeViewModel.swift`
- Modify: `ios/Folio/Presentation/Home/HomeView.swift`

- [ ] **Step 1: Add echo support to HomeViewModel**

```swift
// Add to HomeViewModel:

var echoCards: [EchoCard] = []

func fetchEchoCards() async {
    guard isAuthenticated else { return }
    do {
        let response = try await apiClient.getEchoToday()
        // Map DTOs to local EchoCard models or use DTOs directly
        // Store in echoCards
    } catch {
        // Silent failure — just don't show echo cards
    }
}

func submitEchoReview(cardID: String, result: String) {
    // Optimistic: remove card from echoCards
    echoCards.removeAll { $0.serverID == cardID }

    // Async submit
    Task {
        do {
            let response = try await apiClient.submitEchoReview(cardID: cardID, result: result)
            // Return streak for UI update
        } catch {
            // Error handling — card already removed from UI, that's OK
        }
    }
}
```

- [ ] **Step 2: Add FeedItem enum and mixed feed**

```swift
enum FeedItem: Identifiable {
    case article(Article)
    case echo(EchoCard)

    var id: String {
        switch self {
        case .article(let a): return "article-\(a.id)"
        case .echo(let e): return "echo-\(e.id)"
        }
    }
}

var feedItems: [FeedItem] {
    var items: [FeedItem] = []
    var echoIndex = 0
    for (i, article) in articles.enumerated() {
        items.append(.article(article))
        if (i + 1) % 4 == 0, echoIndex < echoCards.count {
            items.append(.echo(echoCards[echoIndex]))
            echoIndex += 1
        }
    }
    return items
}
```

- [ ] **Step 3: Update HomeView to render mixed feed**

In HomeView's article list section, replace the current `ForEach` over articles with a `ForEach` over `feedItems` that switches between `HomeArticleRow` and `EchoCardView`.

**Interleaving strategy for the sectioned list:**

The current HomeView uses `vm.groupedArticles` → `ForEach` over sections → nested `ForEach` over articles. Echo cards should be inserted WITHIN sections, not between them.

Approach: keep the sectioned structure. In HomeViewModel, compute a mixed feed per section:

```swift
struct FeedSection {
    let group: TimeGroup
    let items: [FeedItem]  // articles + echo cards interleaved
}

var feedSections: [FeedSection] {
    var echoIdx = 0
    return groupedArticles.map { section in
        var items: [FeedItem] = []
        for (i, article) in section.articles.enumerated() {
            items.append(.article(article))
            if (i + 1) % 4 == 0, echoIdx < echoCards.count {
                items.append(.echo(echoCards[echoIdx]))
                echoIdx += 1
            }
        }
        return FeedSection(group: section.group, items: items)
    }
}
```

In HomeView, replace `ForEach(section.articles)` with `ForEach(section.items)` and switch on `.article` vs `.echo` to render the appropriate view.

- [ ] **Step 4: Trigger echo fetch on app launch and refresh**

In HomeView's `.onAppear` or `initializeViewModels`, add:
```swift
Task { await viewModel?.fetchEchoCards() }
```

In `.refreshable`, after sync:
```swift
Task { await viewModel?.fetchEchoCards() }
```

Only fetch echo cards when:
- `isAuthenticated == true`
- `offlineQueueManager?.isNetworkAvailable == true`
- Not in processing/error state

- [ ] **Step 5: Build and test**

```bash
cd ios && xcodegen generate
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | grep "error:" | head -5
```

- [ ] **Step 6: Commit**

```bash
git add ios/Folio/Presentation/Home/HomeViewModel.swift ios/Folio/Presentation/Home/HomeView.swift
git commit -m "feat: integrate Echo cards into Home Feed with interleaving"
```

---

## Task 11: End-to-End Test

- [ ] **Step 1: Start dev server**

```bash
cd server && ./scripts/dev-start.sh
```

- [ ] **Step 2: Submit an article and wait for echo generation**

```bash
# Login, submit article, wait 30s for AI + Echo pipeline
# Then check echo cards
curl -s http://localhost:8080/api/v1/echo/today -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

Expected: at least 1 echo card with question/answer/source_context.

- [ ] **Step 3: Test review endpoint**

```bash
CARD_ID=<from step 2>
curl -s -X POST "http://localhost:8080/api/v1/echo/$CARD_ID/review" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"result":"remembered"}' | python3 -m json.tool
```

Expected: response with updated next_review_at, interval_days, streak.

- [ ] **Step 4: Install iOS app and verify**

Build, install on simulator, login, pull to refresh. Echo cards should appear in feed after every 4th article.

- [ ] **Step 5: Commit any fixes**

---

## Execution Order

```
Task 1 (domain) → Task 2 (repository) → Task 3 (service) → Task 4 (worker)
    → Task 5 (chain + wire up) → Task 6 (API handler + routes)
        → Task 7 (iOS model) → Task 8 (iOS DTOs) → Task 9 (iOS EchoCardView)
            → Task 10 (feed interleaving) → Task 11 (E2E test)
```

All tasks are sequential — each depends on the previous.
