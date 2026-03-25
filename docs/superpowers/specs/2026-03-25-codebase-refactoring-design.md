# Codebase Refactoring Design

纯重构：不改变任何功能行为，消除迭代积累的重复代码、过大文件、接口碎片化。

## 策略

分 5 批渐进重构，按风险从低到高排列。每批独立 commit，跑全量测试确认无 regression。

---

## Batch 1: 机械清理（零风险）

消除明确的重复和组织问题，不改任何逻辑。

### 1.1 Go Worker helper 函数去重

**现状**：`derefOrEmpty`、`derefOrDefault`、`derefFloat` 在 `crawl_handler.go`、`ai_handler.go`、`echo_handler.go` 三个文件中各自定义了一份。

**改动**：
- 新建 `server/internal/worker/helpers.go`
- 将 `derefOrEmpty`、`derefOrDefault`、`derefFloat` 移入，首字母小写保持 package-private
- 三个 handler 文件删除各自的副本

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
- 确认两处的 UserDefaults 数据一致（如果历史数据在旧 key 下，做一次迁移读取，之后统一用新 key）

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
- `HomeView.swift:545` — `formattedDate()` 中的 `"M月d日，EEEE"` 格式
- `KnowledgeMapView.swift:267`
- `RAGAnswerView.swift:326`
- `SharedDataManager.swift:128`
- `Date+RelativeFormat.swift:35` — "older" 分支中的绝对日期格式

`Network.swift` 的 `ISO8601Formatters` 是正确的做法（`static let`），但其他文件没有效仿。

**改动**：
- 新建 `ios/Folio/Utils/Extensions/DateFormatters.swift`（或扩展现有 `Date+RelativeFormat.swift`）
- 定义常用格式的静态缓存：

```swift
enum CachedDateFormatters {
    /// "M月d日，EEEE" — 中文日期 + 星期（HomeView 顶部）
    static let chineseDateWithWeekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日，EEEE"
        return f
    }()

    /// "M月d日" / "yyyy年M月d日" — 中文短日期 / 长日期
    static let chineseShortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    /// "yyyy年M月" — 月份（KnowledgeMap, Stats）
    static let chineseYearMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f
    }()
}
```

各调用点改为引用静态实例。不需要全部统一——只需要确保每个格式只创建一次。

### 2.3b 运行 xcodegen generate

新增 Swift 文件后必须重新生成 Xcode 项目。

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

    func saveURL(_ urlString: String) -> SaveResult { ... }
    func saveManualContent(_ content: String) -> SaveResult { ... }
    func saveScreenshot(_ image: UIImage) -> SaveResult { ... }
    func saveVoiceNote(_ transcribedText: String) -> SaveResult { ... }
}
```

HomeView 的每个保存方法变成：
```swift
private func saveURL(_ url: String) {
    let result = saveService.saveURL(url)
    handleSaveResult(result)
    viewModel?.fetchArticles()
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

截图的 OCR 后台任务和图片压缩逻辑也移入 `ContentSaveService`（包括 `resizedImage` 静态方法）。

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

### 4.2 改动

新建 `server/internal/worker/interfaces.go`，定义统一接口：

```go
package worker

// ArticleRepository defines article operations used by worker handlers.
type ArticleRepository interface {
    GetByID(ctx context.Context, id string) (*domain.Article, error)
    UpdateCrawlResult(ctx context.Context, id string, cr repository.CrawlResult) error
    UpdateAIResult(ctx context.Context, id string, ai repository.AIResult) error
    UpdateTitle(ctx context.Context, articleID string, title string) error
    UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error
    SetError(ctx context.Context, id string, errMsg string) error
}

// TaskRepository defines task operations used by worker handlers.
type TaskRepository interface {
    SetCrawlStarted(ctx context.Context, id string) error
    SetCrawlFinished(ctx context.Context, id string) error
    SetAIStarted(ctx context.Context, id string) error
    SetAIFinished(ctx context.Context, id string) error
    SetFailed(ctx context.Context, id string, errMsg string) error
}

// TagRepository defines tag operations used by worker handlers.
type TagRepository interface {
    Create(ctx context.Context, userID, name string, isAIGenerated bool) (*domain.Tag, error)
    AttachToArticle(ctx context.Context, articleID, tagID string) error
}

// CategoryRepository defines category operations used by worker handlers.
type CategoryRepository interface {
    FindOrCreate(ctx context.Context, slug, nameZH, nameEN string) (*domain.Category, error)
}

// ContentCacheRepository defines content cache operations.
type ContentCacheRepository interface {
    GetByURL(ctx context.Context, url string) (*domain.ContentCache, error)
    Upsert(ctx context.Context, cache *domain.ContentCache) error
}

// Enqueuer abstracts the asynq client for enqueueing tasks.
type Enqueuer interface {
    EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}
```

各 handler 使用方式：
- `CrawlHandler` 直接使用 `ArticleRepository`、`TaskRepository`、`TagRepository`、`CategoryRepository`、`ContentCacheRepository`（的 `GetByURL` 子集）、`Enqueuer`
- `AIHandler` 使用 `ArticleRepository`、`TaskRepository`、`TagRepository`、`ContentCacheRepository`（的 `Upsert` 子集）、`Enqueuer`
- `EchoHandler` 保留自己的 `echoCardRepo`（不通用）和 `echoHighlightRepo`（不通用），但 `articleRepo` 改为引用统一的 `ArticleRepository`
- `RelateHandler` 保留 `relateRAGRepo`、`relateSelector`、`relateRelationRepo`（不通用），`articleRepo` 改为 `ArticleRepository`

**注意**：`service/interfaces.go` 不动。service 层的接口是按"最小依赖"原则为 ArticleService 定义的，与 worker 层的粒度不同，各管各的是合理的。

### 4.3 handler struct 字段类型更新

各 handler 的 struct 字段类型从私有接口改为引用 `interfaces.go` 中的公共接口。构造函数签名不变（仍接收具体类型 `*repository.ArticleRepo` 等），只改内部存储类型。

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

**改动**：RAG 源文章点击时，根据 `articleId` 从本地 SwiftData 查找文章，找到则调用 `selectArticle(article)`。找不到的情况（文章可能不在本地）暂时忽略（不 navigate）。

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
