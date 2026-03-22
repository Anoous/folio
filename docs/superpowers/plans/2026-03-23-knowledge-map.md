# Knowledge Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Knowledge Map statistics page — monthly overview (articles/insights/streak), topic distribution bar chart, AI trend insight, Echo absorption stats. Accessible from Settings, Pro only.

**Architecture:** Two backend stats endpoints (monthly + echo) with SQL aggregation + optional AI trend analysis. One new iOS view (KnowledgeMapView) navigated from Settings.

**Tech Stack:** Go 1.24 / pgx v5 / DeepSeek API | Swift 5.9 / SwiftUI / iOS 17.0

**Spec:** `docs/superpowers/specs/2026-03-23-knowledge-map.md`

---

## File Map

### Backend (new)
- `server/internal/service/stats.go` — statistics aggregation + AI trend
- `server/internal/api/handler/stats.go` — HTTP handlers

### Backend (modify)
- `server/internal/api/router.go` — add stats routes
- `server/cmd/server/main.go` — wire stats handler

### iOS (new)
- `ios/Folio/Presentation/Settings/KnowledgeMapView.swift` — statistics UI

### iOS (modify)
- `ios/Folio/Data/Network/Network.swift` — stats DTOs + API methods
- `ios/Folio/Presentation/Settings/SettingsView.swift` — NavigationLink to KnowledgeMapView

---

## Task 1: Backend — Stats Service + API

**Files:**
- Create: `server/internal/service/stats.go`
- Create: `server/internal/api/handler/stats.go`
- Modify: `server/internal/api/router.go`
- Modify: `server/cmd/server/main.go`

- [ ] **Step 1: Create service/stats.go**

```go
type StatsService struct {
    db       *pgxpool.Pool  // direct DB access for aggregation queries
    aiClient *client.DeepSeekAnalyzer
}

func NewStatsService(db *pgxpool.Pool, aiClient *client.DeepSeekAnalyzer) *StatsService
```

Methods:

**GetMonthlyStats(ctx, userID, year, month int) → MonthlyStats:**
1. articles_count: `SELECT COUNT(*) FROM articles WHERE user_id=$1 AND created_at >= $2 AND created_at < $3 AND status='ready'`
2. insights_count: `SELECT COUNT(*) FROM articles WHERE user_id=$1 AND summary IS NOT NULL AND created_at >= $2 AND created_at < $3`
3. streak_days: Query distinct dates with articles, walk backwards from today counting consecutive
4. topic_distribution: `SELECT c.slug, c.name_zh, COUNT(*) FROM articles a JOIN categories c ON a.category_id=c.id WHERE a.user_id=$1 AND a.created_at >= $2 AND a.created_at < $3 GROUP BY c.slug, c.name_zh ORDER BY count DESC`
5. trend_insight: Compare this month vs last month category counts. Call DeepSeek with a short prompt: "用户本月收藏分布：{categories}。上月：{categories}。用一句话总结趋势变化。" Mock fallback: return nil.

**GetEchoStats(ctx, userID, year, month int) → EchoStats:**
1. `SELECT COUNT(*) FILTER (WHERE result='remembered'), COUNT(*) FROM echo_reviews WHERE user_id=$1 AND reviewed_at >= $2 AND reviewed_at < $3`
2. completion_rate = remembered * 100 / total (0 if no reviews)

- [ ] **Step 2: Create handler/stats.go**

```go
type StatsHandler struct {
    statsService *service.StatsService
}

func NewStatsHandler(statsService *service.StatsService) *StatsHandler
func (h *StatsHandler) HandleMonthlyStats(w http.ResponseWriter, r *http.Request)
func (h *StatsHandler) HandleEchoStats(w http.ResponseWriter, r *http.Request)
```

Both handlers:
- Extract userID from context
- Parse `?month=2026-03` query param (default: current month)
- Check Pro subscription (return 403 for Free users)
- Call service, return JSON

- [ ] **Step 3: Register routes + wire**

Router (protected group):
```go
r.Get("/stats/monthly", deps.StatsHandler.HandleMonthlyStats)
r.Get("/stats/echo", deps.StatsHandler.HandleEchoStats)
```

main.go:
```go
statsService := service.NewStatsService(pool, aiAnalyzer)
statsHandler := handler.NewStatsHandler(statsService)
```

- [ ] **Step 4: Build and commit**

```bash
cd server && go build ./cmd/server && echo "OK"
```

---

## Task 2: iOS — Stats DTOs + APIClient

**Files:**
- Modify: `ios/Folio/Data/Network/Network.swift`

- [ ] **Step 1: Add DTOs + methods**

```swift
// MARK: - Stats DTOs

struct MonthlyStatsResponse: Codable {
    let articlesCount: Int
    let insightsCount: Int
    let streakDays: Int
    let topicDistribution: [TopicStat]
    let trendInsight: String?
}

struct TopicStat: Codable {
    let categorySlug: String
    let categoryName: String
    let count: Int
}

struct EchoStatsResponse: Codable {
    let completionRate: Int
    let totalReviews: Int
    let rememberedCount: Int
    let forgottenCount: Int
}

// MARK: - Stats API

func getMonthlyStats(month: String? = nil) async throws -> MonthlyStatsResponse {
    var queryItems: [URLQueryItem] = []
    if let month { queryItems.append(URLQueryItem(name: "month", value: month)) }
    return try await request(method: "GET", path: "/api/v1/stats/monthly", queryItems: queryItems)
}

func getEchoStats(month: String? = nil) async throws -> EchoStatsResponse {
    var queryItems: [URLQueryItem] = []
    if let month { queryItems.append(URLQueryItem(name: "month", value: month)) }
    return try await request(method: "GET", path: "/api/v1/stats/echo", queryItems: queryItems)
}
```

- [ ] **Step 2: Build and commit**

---

## Task 3: iOS — KnowledgeMapView

**Files:**
- Create: `ios/Folio/Presentation/Settings/KnowledgeMapView.swift`
- Modify: `ios/Folio/Presentation/Settings/SettingsView.swift`

- [ ] **Step 1: Create KnowledgeMapView**

Matching prototype 05 layout:

```swift
struct KnowledgeMapView: View {
    @State private var monthlyStats: MonthlyStatsResponse?
    @State private var echoStats: EchoStatsResponse?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title + month
                header

                // Monthly overview (3 numbers)
                if let stats = monthlyStats {
                    monthlyOverview(stats)
                    topicDistribution(stats.topicDistribution)
                    if let trend = stats.trendInsight {
                        trendInsight(trend)
                    }
                }

                // Echo stats
                if let echo = echoStats {
                    echoAbsorption(echo)
                }

                // Bottom encouragement
                footerMessage
            }
            .padding(.horizontal, Spacing.screenPadding)
        }
        .background(Color.folio.background)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStats()
        }
    }
}
```

**Sections:**

1. **Header**: "知识地图" (v3PageTitle) + "2026 年 3 月" (13px, textTertiary)

2. **Monthly Overview** (HStack, 3 equal columns):
   - Number: 28px bold, textPrimary
   - Label: 13px, textTertiary ("篇收藏" / "个洞察" / "天连续")
   - Background: echoBg, 14px radius, padding 20px

3. **Topic Distribution**:
   - "主题分布" header (16px, 600 weight)
   - Each row: category name (15px) + count + horizontal bar
   - Bar: accent color, width proportional to max count, 6px height, 3px radius
   - Top 6 categories only

4. **Trend Insight**:
   - "✦ 趋势洞察" label (accent)
   - Text: serif 15px, textSecondary, line-height 1.6

5. **Echo Absorption**:
   - "Echo 吸收统计" header
   - Rate circle: large ring (accent stroke), percentage number in center
   - Stats row: "本月 N 次 Echo" + "记得 X / 忘了 Y"

6. **Footer**: "知识在积累，你正在变得更强。" (13px, textTertiary, centered)

- [ ] **Step 2: Add NavigationLink in SettingsView**

Find the "知识地图" row in SettingsView. Wrap it with a NavigationLink:
```swift
NavigationLink { KnowledgeMapView() } label: { /* existing row content */ }
```

For Free users: show an alert or sheet prompting upgrade instead of navigating.

- [ ] **Step 3: xcodegen + build + commit**

---

## Task 4: End-to-End Test

- [ ] **Step 1: Rebuild backend**

```bash
cd server && docker compose -f docker-compose.local.yml up --build -d app
```

- [ ] **Step 2: Test API**

```bash
curl -s http://localhost:8080/api/v1/stats/monthly -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
curl -s http://localhost:8080/api/v1/stats/echo -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

- [ ] **Step 3: Test on simulator**

Build iOS app, navigate to Settings → 知识地图. Verify:
- Monthly numbers display
- Topic bars render
- Echo stats show

- [ ] **Step 4: Commit any fixes**

---

## Execution Order

```
Task 1 (backend service + API) → Task 2 (iOS DTOs) → Task 3 (KnowledgeMapView) → Task 4 (E2E)
```
