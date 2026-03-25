# Codebase Refactoring Design

纯重构：不改变任何功能行为，消除迭代积累的重复代码、过大文件、接口碎片化。

## 策略

分 5 批渐进重构，按风险从低到高排列。每批独立 commit，跑全量测试确认无 regression。

---

## Batch 1: 机械清理（零风险）

消除明确的重复和组织问题，不改任何逻辑。

### 1.1 Go Worker helper 函数归位

**现状**：`derefOrEmpty`、`derefOrDefault`、`derefFloat` 定义在 `crawl_handler.go`（行 365-386）中，但被 `ai_handler.go` 和 `echo_handler.go` 跨文件调用。它们不是重复定义（同 package 共享），但放在 484 行的 crawl handler 底部不利于发现和维护。

**改动**：
- 新建 `server/internal/worker/helpers.go`
- 将 `derefOrEmpty`、`derefOrDefault`、`derefFloat` 从 `crawl_handler.go` 移入
- 纯文件重组，无逻辑变化

### 1.2 SyncService 重复注释

**现状**：`SyncService.swift:393-394` 有两行完全相同的文档注释。

**改动**：删除重复的那一行。

### 1.3 搜索历史 key 统一

**现状**：
- `HomeView.swift:280` 使用硬编码 `"recent_searches"`
- `AppConstants.swift` 定义了 `searchHistoryKey = "folio_search_history"`
- 两个不同的 key 做同一件事，实际上它们操作的是不同的 UserDefaults 存储

**改动**：
- `HomeView` 的 `recentSearchesKey` 改为引用 `AppConstants.searchHistoryKey`
- 旧 key `"recent_searches"` 下的数据直接丢弃（仅最近搜索词，非关键数据），不做迁移
- 删除 `HomeView` 中的 `recentSearchesKey` 常量定义

### 1.4 UpgradeComparisonView 拆分

**现状**：`SettingsView.swift`（753 行）包含两个完整的独立视图：`SettingsView` 和 `UpgradeComparisonView`。

**改动**：
- 新建 `ios/Folio/Presentation/Settings/UpgradeComparisonView.swift`
- 将 `UpgradeComparisonView` 及其内部类型（`ComparisonValue`、`ComparisonRow`）移入
- `SettingsView.swift` 从 ~753 行降到 ~520 行

### 1.4b 运行 xcodegen generate

新增 Swift 文件后必须重新生成 Xcode 项目。

---

## Batch 2: iOS 重复模式消除

合并高度相似的代码，逻辑行为不变。

### 2.1 Article toggle actions 合并

**现状**：`Article+Actions.swift` 中 `toggleFavoriteWithSync` 和 `toggleArchiveWithSync` 结构几乎 100% 相同，仅以下不同：
- 操作的属性（`isFavorite` vs `isArchived`）
- toast 文案和图标
- API request 参数（`UpdateArticleRequest(isFavorite:)` vs `UpdateArticleRequest(isArchived:)`)

**改动**：抽取通用私有方法：

```swift
// Article+Actions.swift
private func toggleBoolWithSync(
    toggle: () -> Void,
    makeRequest: () -> UpdateArticleRequest,
    toastOn: (String, String),   // (message, icon)
    toastOff: (String, String),
    getValue: () -> Bool,
    context: ModelContext,
    apiClient: APIClient,
    isAuthenticated: Bool,
    showToast: @escaping (String, String?) -> Void
) {
    toggle()
    markPendingUpdateIfNeeded()
    ModelContext.safeSave(context)

    let value = getValue()
    let toast = value ? toastOn : toastOff
    showToast(toast.0, toast.1)

    guard isAuthenticated, let serverID else { return }
    Task {
        do {
            try await apiClient.updateArticle(id: serverID, request: makeRequest())
            syncState = .synced
            ModelContext.safeSave(context)
        } catch {
            syncState = .pendingUpdate
            ModelContext.safeSave(context)
            showToast(String(localized: "home.article.syncFailed", defaultValue: "Sync failed, will retry"), "exclamationmark.icloud")
        }
    }
}
```

`toggleFavoriteWithSync` 和 `toggleArchiveWithSync` 各自变成 3-5 行调用。

### 2.2 ReaderView menu dismiss 去重

**现状**：`ReaderView.swift` 中有 6 处相同的模式：
```swift
showMoreMenu = false
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    // 实际操作
}
```

**改动**：在 ReaderView 中添加私有 helper：

```swift
private func dismissMenuThen(_ action: @escaping () -> Void) {
    showMoreMenu = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
}
```

6 处调用点都改为 `dismissMenuThen { ... }`。

### 2.3 DateFormatter 静态缓存

**现状**：以下位置每次调用都创建新的 `DateFormatter()`：
- `HomeView.swift:545` — `formattedDate()` 中 `"M月d日，EEEE"` 格式
- `KnowledgeMapView.swift:267` — `"yyyy 年 M 月"` 格式（注意空格）
- `RAGAnswerView.swift:326` — `"M月d日收藏"` 格式（含后缀文字）
- `Date+RelativeFormat.swift:35` — "older" 分支中的绝对日期格式

注意：`SharedDataManager.swift:127` 已经正确使用 `private static let quotaFormatter`，不需要改动。

`Network.swift` 的 `ISO8601Formatters` 是正确的做法（`static let`），上述文件没有效仿。

**改动**：
各调用点就地改为 `private static let` 缓存（与 `SharedDataManager` 同一模式），而非统一到一个全局文件。原因：每个格式字符串都不同（含空格、含后缀文字），强行统一为通用 enum 反而增加耦合。

具体：
- `HomeView` 中 `formattedDate()` → 添加 `private static let dateWeekdayFormatter: DateFormatter = { ... }()`
- `KnowledgeMapView` 中 `currentMonthLabel` → 添加 `private static let monthLabelFormatter: DateFormatter = { ... }()`
- `RAGAnswerView` 中 `formatSourceDate` → 添加 `private static let sourceDateFormatter: DateFormatter = { ... }()`
- `Date+RelativeFormat.swift` 中 "older" 分支 → 添加两个 `private static let`（中文/英文格式各一个）

每处改动后确认 format string 与原始代码完全一致。

Batch 2 不新增文件，无需运行 xcodegen。

---

## Batch 3: HomeView 拆分（最大收益）

将 865 行的 God View 拆成职责清晰的组件。

### 3.1 ContentSaveService — 统一保存逻辑

**现状**：`HomeView` 中 `saveURL`、`saveManualContent`、`saveScreenshot`、`saveVoiceNote` 四个方法都包含相同的样板：
1. 读 isPro + 检查配额
2. 执行保存操作
3. incrementQuota + fetchArticles + showToast + toggle haptic
4. Task { syncService.incrementalSync() }

**改动**：新建 `ios/Folio/Data/ContentSaveService.swift`：

```swift
@MainActor
final class ContentSaveService {
    private let context: ModelContext
    private let syncService: SyncService?

    init(context: ModelContext, syncService: SyncService?) {
        self.context = context
        self.syncService = syncService
    }

    enum SaveResult {
        case success(message: String, icon: String)
        case duplicate
        case quotaExceeded
        case error(message: String)
    }

    /// URL/笔记/语音 — 同步保存，返回结果。调用者处理 UI 反馈。
    func saveURL(_ urlString: String) -> SaveResult { ... }
    func saveManualContent(_ content: String) -> SaveResult { ... }
    func saveVoiceNote(_ transcribedText: String) -> SaveResult { ... }

    /// 截图 — 同步保存图片文件 + 创建 Article，返回结果。
    /// OCR 在后台异步执行，完成后通过 onOCRComplete 回调通知调用者刷新。
    func saveScreenshot(_ image: UIImage, onOCRComplete: @escaping () -> Void) -> SaveResult { ... }
}
```

**异步边界说明**：
- `saveURL`/`saveManualContent`/`saveVoiceNote` 是纯同步的（SwiftData 写入 + 配额检查），返回 `SaveResult` 即可。
- `saveScreenshot` 的即时保存（写文件 + 创建 Article）也是同步的，但 OCR 是后台 `Task`。OCR 完成后调用 `onOCRComplete` 闭包让 HomeView 执行 `fetchArticles()`。
- `syncService?.incrementalSync()` 在每个 save 方法内部启动（fire-and-forget `Task`），不影响 `SaveResult` 返回。

HomeView 的每个保存方法变成：
```swift
private func saveURL(_ url: String) {
    let result = saveService.saveURL(url)
    handleSaveResult(result)
    if case .success = result { viewModel?.fetchArticles() }
}

private func handleSaveResult(_ result: ContentSaveService.SaveResult) {
    switch result {
    case .success(let msg, let icon):
        showToast(msg, icon: icon); saveSucceeded.toggle()
    case .duplicate:
        showToast(...); saveFailed.toggle()
    case .quotaExceeded:
        showToast(...); saveFailed.toggle()
    case .error(let msg):
        showToast(msg, icon: "xmark.circle.fill"); saveFailed.toggle()
    }
}
```

图片压缩（`resizedImage`）和 OCR 调用逻辑移入 `ContentSaveService`。

### 3.2 HomeSearchView — 搜索 UI 抽离

**现状**：`HomeView.swift:178-276`（`searchContent`）包含搜索栏 UI + RAG/FTS 分支逻辑，约 100 行。

**改动**：新建 `ios/Folio/Presentation/Home/HomeSearchView.swift`：

```swift
struct HomeSearchView: View {
    @Binding var searchText: String
    let viewModel: HomeViewModel
    let searchViewModel: SearchViewModel?
    let onDismiss: () -> Void
    let onSaveURL: (String) -> Void
    let onSaveNote: (String) -> Void
    let findExistingArticle: (String) -> Article?

    var body: some View { ... }  // 原 searchContent 逻辑
}
```

### 3.3 SearchSuggestionsView — 搜索建议抽离

**现状**：`HomeView.swift:309-406`（`searchSuggestionsContent` + `quickActionCard`）约 100 行。

**改动**：新建 `ios/Folio/Presentation/Home/SearchSuggestionsView.swift`：

```swift
struct SearchSuggestionsView: View {
    @Binding var searchText: String
    let recentSearches: [String]
    let onShowNoteSheet: () -> Void

    var body: some View { ... }  // 原 searchSuggestionsContent
}
```

`suggestedQuestions` 常量和 `quickActionCard` helper 一起迁移。

### 3.4 HomeView 最终形态

拆分后 `HomeView` 职责：
- 顶部导航栏
- `mainContent` 分发（搜索 / 空状态 / 文章列表）
- 文章列表（`articleList`）
- 生命周期管理（`onAppear`、`scenePhase`）
- Sheet/Alert 声明

预计 ~350 行。

### 3.4b 运行 xcodegen generate

新增 Swift 文件后必须重新生成 Xcode 项目。

---

## Batch 4: Go Worker 接口统一

消除 5 个 handler 文件（crawl、ai、echo、relate、push）各自定义重叠接口的碎片化。

### 4.1 现状分析

各 handler 对相同 repo 定义了各自的接口：

| 方法 | crawl | ai | echo | relate |
|------|-------|----|------|--------|
| `GetByID` | ✓ | ✓ | ✓ | ✓ |
| `UpdateCrawlResult` | ✓ | | | |
| `UpdateAIResult` | ✓ | ✓ | | |
| `UpdateStatus` | ✓ | ✓ | | |
| `SetError` | ✓ | ✓ | | |
| `UpdateTitle` | | ✓ | | |

同理 `taskRepo`（SetCrawlStarted/Finished, SetAIStarted/Finished, SetFailed）和 `tagRepo`（Create, AttachToArticle）也在多处重复。

### 4.2 设计原则

Go 惯例是 "accept the smallest interface you need"（接口隔离原则）。各 handler 定义窄接口本身没有问题，问题是**完全相同的接口被定义了多次**。

策略：定义**细粒度的共享 building-block 接口**，各 handler 按需组合，而非一个大 fat interface。这样：
- 消除真正重复的接口定义
- 不迫使 test mock 实现不需要的方法
- 保持 Go 的 ISP 惯例

### 4.3 改动

新建 `server/internal/worker/interfaces.go`，定义细粒度 building blocks：

```go
package worker

// --- Article repository building blocks ---

// ArticleGetter reads articles.
type ArticleGetter interface {
    GetByID(ctx context.Context, id string) (*domain.Article, error)
}

// ArticleStatusUpdater updates article status and errors.
type ArticleStatusUpdater interface {
    UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error
    SetError(ctx context.Context, id string, errMsg string) error
}

// ArticleCrawlUpdater updates crawl results.
type ArticleCrawlUpdater interface {
    UpdateCrawlResult(ctx context.Context, id string, cr repository.CrawlResult) error
}

// ArticleAIUpdater updates AI results.
type ArticleAIUpdater interface {
    UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error
}

// ArticleTitleUpdater updates article title.
type ArticleTitleUpdater interface {
    UpdateTitle(ctx context.Context, articleID string, title string) error
}

// --- Task repository building blocks ---

// TaskCrawlTracker tracks crawl task lifecycle.
type TaskCrawlTracker interface {
    SetCrawlStarted(ctx context.Context, id string) error
    SetCrawlFinished(ctx context.Context, id string) error
}

// TaskAIStarter marks AI processing as started.
type TaskAIStarter interface {
    SetAIStarted(ctx context.Context, id string) error
}

// TaskAIFinisher marks AI processing as finished.
type TaskAIFinisher interface {
    SetAIFinished(ctx context.Context, id string) error
}

// TaskFailer marks a task as failed.
type TaskFailer interface {
    SetFailed(ctx context.Context, id string, errMsg string) error
}

// --- Other shared interfaces ---

// TagCreator creates tags and attaches them to articles.
type TagCreator interface {
    Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error)
    AttachToArticle(ctx context.Context, articleID, tagID string) error
}

// CategoryFinder finds or creates categories.
type CategoryFinder interface {
    FindOrCreate(ctx context.Context, slug, nameZH, nameEN string) (*domain.Category, error)
}

// ContentCacheReader reads content cache by URL.
type ContentCacheReader interface {
    GetByURL(ctx context.Context, url string) (*domain.ContentCache, error)
}

// ContentCacheWriter writes to content cache.
type ContentCacheWriter interface {
    Upsert(ctx context.Context, cache *domain.ContentCache) error
}

// Enqueuer abstracts the asynq client for enqueueing tasks.
type Enqueuer interface {
    EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}
```

### 4.4 各 handler 的 struct 字段类型更新

各 handler 删除自己的私有接口定义，struct 字段改为组合共享接口：

**CrawlHandler**:
```go
type CrawlHandler struct {
    readerClient scraper              // 保留（scraper 是 CrawlHandler 独有的）
    jinaClient   scraper
    articleRepo  interface {           // 组合：Get + Crawl + AI + Status
        ArticleGetter; ArticleCrawlUpdater; ArticleAIUpdater; ArticleStatusUpdater
    }
    taskRepo     interface { TaskCrawlTracker; TaskAIFinisher; TaskFailer }
    asynqClient  Enqueuer
    enableImage  bool
    cacheRepo    ContentCacheReader
    tagRepo      TagCreator
    categoryRepo CategoryFinder
}
```

**AIHandler**:
```go
type AIHandler struct {
    aiClient     analyzer              // 保留（analyzer 是 AI 独有的）
    articleRepo  interface {
        ArticleGetter; ArticleAIUpdater; ArticleTitleUpdater; ArticleStatusUpdater
    }
    taskRepo     interface { TaskAIStarter; TaskAIFinisher; TaskFailer }
    categoryRepo CategoryFinder        // 从具体类型 *repository.CategoryRepo 改为接口
    tagRepo      TagCreator
    cacheRepo    ContentCacheWriter
    asynqClient  Enqueuer
}
```

**EchoHandler**：`articleRepo` 改为 `ArticleGetter`，其余保留独有接口（`echoCardRepo`、`echoHighlightRepo`、`echoCardGenerator`）。

**RelateHandler**：`articleRepo` 改为 `ArticleGetter`，其余保留独有接口（`relateRAGRepo`、`relateSelector`、`relateRelationRepo`）。

**ImageHandler**：`articleRepo` 从具体类型 `*repository.ArticleRepo` 改为所需的最小接口（needs `GetByID` + markdown update method）。

### 4.5 测试 mock 影响

因为使用细粒度接口，现有 test mock 只需满足各 handler 实际需要的方法子集，**不需要添加任何多余的 stub 方法**。例如 `mockAIArticleRepo` 原来实现 `aiArticleRepo`（5 个方法），改后实现 `ArticleGetter + ArticleAIUpdater + ArticleTitleUpdater + ArticleStatusUpdater`（仍然是同样的 5 个方法）。

**注意**：`service/interfaces.go` 不动。service 层的接口是按"最小依赖"原则为 ArticleService 定义的，与 worker 层的粒度不同，各管各的是合理的。

---

## Batch 5: 跨端一致性 + 收尾

### 5.1 iOS SourceType.detect 补齐

**现状**：Go 端 `DetectSource()` 识别 `substack.com` 和 `mailchi.mp` → `newsletter`，iOS 端 `SourceType.detect(from:)` 不识别这两个。

**改动**：在 `Article.swift` 的 `SourceType.detect(from:)` 中添加：
```swift
} else if host.contains("substack.com") || host.contains("mailchi.mp") {
    return .newsletter
}
```

### 5.2 清理 TODO

**MilestoneCardView.swift:68** — `// TODO: Navigate to upgrade`

**改动**：改为展示 `UpgradeComparisonView` sheet（Batch 1 已拆出为独立文件）。在 `MilestoneCardView` 中添加 `@State private var showUpgrade = false` + `.sheet`，按钮触发 `showUpgrade = true`。

**HomeView.swift:248** — `// TODO: Navigate to reader for this article`

**改动**：RAG 源文章点击时，`articleId` 是服务端 ID（非本地 UUID），需通过 `serverID` 字段查询 SwiftData。使用 `ArticleRepository.fetchByServerID(articleId)` 查找本地文章，找到则调用 `selectArticle(article)`。找不到的情况（文章可能不在本地）暂不处理。

---

## 测试策略

| Batch | 验证方式 |
|-------|---------|
| 1 | `go build ./...` + `go test ./internal/worker/...` + iOS 编译通过 |
| 2 | iOS 单元测试全量（`xcodebuild test`），特别关注 Article action 相关测试 |
| 3 | iOS 单元测试全量 + 手动验证保存流程（URL/笔记/截图/语音） |
| 4 | `go test ./internal/worker/...` + `go test ./internal/service/...` + E2E |
| 5 | iOS 编译 + 手动验证 newsletter URL 检测和 milestone 升级导航 |

## 不在范围内

- 迁移文件编号问题（002 的 up 文件不对称）——迁移已经 applied，改编号无意义
- Network.swift 拆分（800 行但结构清晰：DTOs + APIClient，不值得动）
- 新增任何功能或 UI 变更
