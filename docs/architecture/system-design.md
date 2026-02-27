# Folio（页集）- 系统架构设计

> 版本：1.1（MVP）
> 更新日期：2026-02-20
> 关联文档：[PRD](../design/prd.md) | [交互流程](../interaction/core-flows.md)

---

## 一、架构总览

### 1.1 系统全景

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS 客户端                               │
│                                                                 │
│  ┌──────────────────────┐    ┌────────────────────────────────┐│
│  │     iOS Main App      │    │      Share Extension           ││
│  │    (Swift/SwiftUI)    │    │   (接收外部 App 分享的 URL)     ││
│  │                       │    │                                ││
│  │  ┌─────────────────┐ │    │  ┌──────────────────────────┐  ││
│  │  │  收藏列表/搜索   │ │    │  │  URL 接收 + 快速预览     │  ││
│  │  │  分类浏览/标签   │ │    │  │  标签选择 + 一键保存      │  ││
│  │  ├─────────────────┤ │    │  └──────────────────────────┘  ││
│  │  │  SwiftData       │ │    └────────────────────────────────┘│
│  │  │  本地持久化存储   │ │                                      │
│  │  ├─────────────────┤ │                                      │
│  │  │  SQLite FTS5     │ │                                      │
│  │  │  全文搜索引擎    │ │                                      │
│  │  ├─────────────────┤ │                                      │
│  │  │  CloudKit        │ │                                      │
│  │  │  iCloud 同步     │ │                                      │
│  │  └─────────────────┘ │                                      │
│  └──────────┬───────────┘                                      │
└─────────────┼──────────────────────────────────────────────────┘
              │ HTTPS
              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       API Gateway (Caddy)                        │
│               JWT 认证 · 限流 · CORS · 自动 HTTPS                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Go API 服务（核心后端）                         │
│                       (chi router)                               │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│  │  API 层       │  │  Worker 层   │  │  Service 层            │ │
│  │              │  │  (asynq)     │  │                       │ │
│  │ ·认证/授权   │  │              │  │ ·文章管理              │ │
│  │ ·文章接口    │  │ ·抓取任务    │  │ ·用户管理              │ │
│  │ ·搜索接口    │  │ ·AI处理任务  │  │ ·配额管理              │ │
│  │ ·用户接口    │  │ ·图片转存    │  │ ·标签管理              │ │
│  │ ·标签接口    │  │ ·重试/超时   │  │                       │ │
│  └──────────────┘  └──────┬───────┘  └───────────────────────┘ │
└───────────────────────────┼─────────────────────────────────────┘
                            │ 内部调用
                ┌───────────┴───────────┐
                ▼                       ▼
┌──────────────────────┐  ┌──────────────────────┐
│   Reader 抓取服务     │  │    AI 处理服务        │
│  (@vakra-dev/reader) │  │    (Python)          │
│                      │  │                      │
│  ·多引擎级联抓取      │  │  ·内容分类            │
│   (HTTP→TLS→Browser) │  │  ·标签提取            │
│  ·正文提取+清洗       │  │  ·摘要生成            │
│  ·HTML→Markdown      │  │  ·要点提取            │
│  ·元数据提取          │  │  ·Prompt管理          │
│  ·Cloudflare绕过     │  │                      │
│  ·浏览器池管理        │  │  DeepSeek API          │
└──────────────────────┘  └──────────────────────┘
                │                       │
                ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                          数据层                                   │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│  │PostgreSQL│  │  Redis   │  │  S3/R2   │                     │
│  │          │  │          │  │ 对象存储  │                     │
│  │ ·用户表  │  │ ·任务队列│  │          │                     │
│  │ ·收藏表  │  │ ·限流计数│  │ ·文章图片│                     │
│  │ ·标签表  │  │ ·AI缓存 │  │ ·用户头像│                     │
│  │ ·分类表  │  │ ·会话   │  │          │                     │
│  └──────────┘  └──────────┘  └──────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 技术选型一览

| 层级 | 技术 | 版本 | 选择理由 |
|------|------|------|---------|
| iOS 客户端 | Swift + SwiftUI | Swift 5.9+ | 原生性能，Share Extension 深度集成 |
| iOS 数据存储 | SwiftData | iOS 17+ | Apple 官方 ORM，声明式数据建模 |
| iOS 全文搜索 | SQLite FTS5 | 内置 | 高性能本地全文搜索，支持中文分词 |
| iOS 同步 | CloudKit | iOS 17+ | iCloud 原生同步，用户无需额外账号 |
| API 网关 | Caddy | 2.7+ | 自动 HTTPS，配置简洁，性能好 |
| 后端 API | Go + chi | Go 1.24+ | 高性能，goroutine 并发模型天然适合异步任务编排，编译型语言部署简单 |
| 任务队列 | asynq (Redis) | 0.24+ | Go 原生异步任务框架，基于 Redis，API 类似 BullMQ |
| 抓取引擎 | @vakra-dev/reader | 0.1.2 | 多引擎级联抓取（HTTP→TLS→Browser），内置反爬突破、正文提取、Markdown 转换 |
| AI 服务 | Python + FastAPI | Python 3.12+ | AI 生态成熟，OpenAI SDK 兼容 DeepSeek |
| AI 模型 | DeepSeek API | deepseek-chat | 中文理解能力强，分类/摘要质量高，性价比优 |
| 数据库 | PostgreSQL + pgx | 16+ | 关系型数据，JSONB 支持好；pgx 是 Go 最高性能的 PG 驱动 |
| 缓存 | Redis + go-redis | 7+ | 限流计数、AI 结果缓存、任务队列后端 |
| 对象存储 | Cloudflare R2 | - | S3 兼容，免出站流量费，全球 CDN |
| 容器化 | Docker + Compose | 24+ | 标准化部署，环境一致 |

### 1.3 核心数据流

```
用户在微信/Twitter/浏览器中点击"分享"
                │
                ▼
┌───────────────────────────────┐
│  iOS Share Extension 接收 URL  │
│  ·展示快速预览界面              │
│  ·用户可选标签/分类（可选）      │
│  ·点击"保存"                   │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│  本地先行保存（离线优先）       │
│  ·SwiftData 写入 URL + 元数据  │
│  ·状态标记为 "pending"         │
│  ·即刻返回成功给用户            │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│  客户端内容提取（Share Extension）│
│  ·HTMLFetcher 获取 HTML        │
│  ·ReadabilityExtractor 提取正文│
│  ·HTMLToMarkdownConverter 转换 │
│  ·提取成功 → 状态 "clientReady"│
│  ·提取失败 → 保持 "pending"    │
│  ·超时限制 8 秒，内存限制 100MB │
└───────────────┬───────────────┘
                │ 有网络时
                ▼
┌───────────────────────────────┐
│  POST /api/v1/articles        │
│  ·发送 URL 到 Go 后端          │
│  ·Go 返回 task_id             │
│  ·asynq 入队抓取任务           │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│  Go Worker 处理抓取任务        │
│                               │
│  Step 1: 调用 Reader 服务      │
│  ·Reader 多引擎级联抓取        │
│  ·返回 Markdown + 元数据       │
│                               │
│  Step 2: 图片处理              │
│  ·解析 Markdown 中的图片 URL   │
│  ·下载并转存到 R2              │
│  ·替换 Markdown 中的图片链接   │
│                               │
│  Step 3: 调用 AI 服务          │
│  ·发送 Markdown 到 Python 服务 │
│  ·返回分类/标签/摘要/要点      │
│                               │
│  Step 4: 写入数据库            │
│  ·结果写入 PostgreSQL          │
│  ·状态标记为 "ready"           │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│  结果回传 iOS 客户端            │
│  ·轮询 或 静默推送通知          │
│  ·更新本地 SwiftData 记录       │
│  ·FTS5 索引更新                │
│  ·状态标记为 "ready"           │
└───────────────────────────────┘
```

---

## 二、iOS 客户端架构

### 2.1 应用架构模式：MVVM + Clean Architecture

```
┌──────────────────────────────────────────┐
│             Presentation Layer            │
│  ┌──────────────┐  ┌──────────────────┐  │
│  │    Views      │◀─│    ViewModels    │  │
│  │  (SwiftUI)   │  │ (ObservableObject)│  │
│  │              │  │                  │  │
│  │ ·HomeView    │  │ ·HomeViewModel   │  │
│  │  (含搜索)    │  │ ·SearchViewModel │  │
│  │ ·ReaderView  │  │ ·ReaderViewModel │  │
│  │ ·SettingsView│  │ ·AuthViewModel   │  │
│  │ ·Onboarding  │  │                  │  │
│  └──────────────┘  └────────┬─────────┘  │
└─────────────────────────────┼────────────┘
                              │
┌─────────────────────────────┼────────────┐
│             Domain Layer                  │
│  ┌──────────────────┐  ┌──────────────┐  │
│  │    Use Cases      │  │    Models    │  │
│  │  ·SaveArticle     │  │  ·Article    │  │
│  │  ·SearchArticles  │  │  ·Tag        │  │
│  │  ·SyncArticles    │  │  ·Category   │  │
│  │  ·ManageTags      │  │  ·UserQuota  │  │
│  │  ·ExportData      │  │  ·SyncState  │  │
│  └────────┬─────────┘  └──────────────┘  │
└───────────┼──────────────────────────────┘
            │
┌───────────┼──────────────────────────────┐
│             Data Layer                    │
│  ┌──────────────────┐  ┌──────────────┐  │
│  │   Repositories    │  │   Services   │  │
│  │  ·ArticleRepo     │  │  ·Network    │  │
│  │  ·TagRepo         │  │  ·SwiftData  │  │
│  │  ·CategoryRepo    │  │  ·FTS5Search │  │
│  │  ·SyncRepo        │  │  ·CloudKit   │  │
│  │  ·QuotaRepo       │  │  ·KeyChain   │  │
│  └──────────────────┘  └──────────────┘  │
└──────────────────────────────────────────┘
```

### 2.2 Share Extension 技术方案详细设计

Share Extension 是 Folio 最核心的入口，用户从任意 App 分享链接到 Folio 的体验必须极致流畅。

#### 2.2.1 技术约束

| 约束项 | 限制 | 应对策略 |
|--------|------|---------|
| 内存限制 | 120MB | 轻量化 UI，不加载主 App 完整依赖 |
| 执行时间 | 约 30 秒 | URL 存储 + 客户端内容提取（8 秒超时），服务端抓取异步后台执行 |
| 存储共享 | 需 App Group | 通过 App Group 共享 SwiftData 容器 |
| 网络请求 | 允许但受限 | 本地先行保存，网络请求放入后台队列 |

#### 2.2.2 Extension 架构

```
┌──────────────────────────────────────────────┐
│              Share Extension 进程              │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │       ShareViewController            │    │
│  │       (UIViewController)             │    │
│  │                                      │    │
│  │  ┌──────────────────────────────┐    │    │
│  │  │  CompactShareView (SwiftUI)  │    │    │
│  │  │  ·URL 预览（标题+favicon）    │    │    │
│  │  │  ·保存状态指示（含提取进度）   │    │    │
│  │  │  ·配额检查与警告              │    │    │
│  │  └──────────────┬───────────────┘    │    │
│  └─────────────────┼────────────────────┘    │
│                    │                          │
│  ┌─────────────────▼────────────────────┐    │
│  │    SharedDataManager                  │    │
│  │    (App Group 共享数据访问)            │    │
│  │                                      │    │
│  │  ┌──────────────┐ ┌──────────────┐   │    │
│  │  │  SwiftData   │ │  UserDefaults│   │    │
│  │  │  共享容器     │ │  (App Group) │   │    │
│  │  │              │ │  ·用量计数    │   │    │
│  │  │  写入Article │ │  ·用户偏好    │   │    │
│  │  │  status=     │ │              │   │    │
│  │  │  "pending"   │ │              │   │    │
│  │  └──────────────┘ └──────────────┘   │    │
│  └──────────────────────────────────────┘    │
│                    │                          │
│  ┌─────────────────▼────────────────────┐    │
│  │    ContentExtractor（客户端内容提取）   │    │
│  │    (Shared/Extraction/)              │    │
│  │                                      │    │
│  │  HTMLFetcher → ReadabilityExtractor  │    │
│  │  → HTMLToMarkdownConverter           │    │
│  │                                      │    │
│  │  ·8 秒超时，100MB 内存限制           │    │
│  │  ·提取成功 → status="clientReady"    │    │
│  │  ·提取失败 → 保持 "pending"          │    │
│  └──────────────────────────────────────┘    │
└──────────────────────────────────────────────┘
                    │
                    │ 主 App 被唤醒或下次打开时
                    ▼
┌──────────────────────────────────────────────┐
│              主 App 进程                       │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │    PendingArticleProcessor            │    │
│  │    ·扫描 status="pending" 的记录      │    │
│  │    ·逐条发送到后端抓取                 │    │
│  │    ·更新状态为 "processing"            │    │
│  │    ·轮询/推送获取结果                  │    │
│  │    ·结果写入 SwiftData + FTS5 索引     │    │
│  └──────────────────────────────────────┘    │
└──────────────────────────────────────────────┘
```

#### 2.2.3 Share Extension 核心代码结构

```swift
// ShareViewController.swift
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            close()
            return
        }

        // 支持 URL 和纯文本两种类型
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                if let url = item as? URL {
                    self?.presentShareUI(url: url)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                if let text = item as? String, let url = URL(string: text) {
                    self?.presentShareUI(url: url)
                }
            }
        }
    }

    private func presentShareUI(url: URL) {
        DispatchQueue.main.async {
            let shareView = CompactShareView(
                url: url,
                onSave: { [weak self] tags in
                    self?.saveArticle(url: url, tags: tags)
                },
                onCancel: { [weak self] in
                    self?.close()
                }
            )
            let hostingController = UIHostingController(rootView: shareView)
            self.addChild(hostingController)
            self.view.addSubview(hostingController.view)
            hostingController.view.frame = self.view.bounds
        }
    }

    private func saveArticle(url: URL, tags: [String]) {
        let manager = SharedDataManager()
        manager.savePendingArticle(url: url, tags: tags)
        close()
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
```

```swift
// SharedDataManager.swift — App Group 共享数据管理
import SwiftData
import Foundation

class SharedDataManager {
    private let container: ModelContainer
    private let appGroupID = "group.com.folio.app"

    init() {
        let config = ModelConfiguration(
            groupContainer: .identifier(appGroupID)
        )
        container = try! ModelContainer(
            for: Article.self, Tag.self, Category.self,
            configurations: config
        )
    }

    func savePendingArticle(url: URL, tags: [String]) {
        let context = ModelContext(container)
        let article = Article(
            url: url.absoluteString,
            status: .pending,
            createdAt: Date(),
            userTags: tags
        )
        context.insert(article)
        try? context.save()

        // 更新用量计数
        incrementMonthlyCount()
    }

    private func incrementMonthlyCount() {
        let defaults = UserDefaults(suiteName: appGroupID)
        let key = monthlyCountKey()
        let current = defaults?.integer(forKey: key) ?? 0
        defaults?.set(current + 1, forKey: key)
    }

    private func monthlyCountKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return "quota_\(formatter.string(from: Date()))"
    }
}
```

### 2.3 本地存储方案：SwiftData 数据模型

```swift
import SwiftData
import Foundation

// MARK: - 文章模型
@Model
final class Article {
    @Attribute(.unique) var id: UUID
    var url: String
    var title: String?
    var author: String?
    var siteName: String?
    var faviconURL: String?
    var coverImageURL: String?

    // 内容
    var markdownContent: String?       // Markdown 正文
    var summary: String?               // AI 一句话摘要
    var keyPoints: [String]            // AI 要点提取（3-5个）
    var wordCount: Int                 // 字数统计

    // 分类和标签
    var category: Category?            // AI 自动分类
    @Relationship(inverse: \Tag.articles)
    var tags: [Tag]                    // AI 标签 + 用户标签

    // 状态（通过 Raw String 存储，计算属性提供类型安全访问）
    var statusRaw: String              // pending/processing/ready/failed/clientReady
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var readProgress: Double = 0.0     // 阅读进度 0.0-1.0
    var aiConfidence: Double           // AI 分类置信度 0-1
    var fetchError: String?            // 抓取失败错误信息
    var retryCount: Int                // 重试次数
    var language: String?              // 检测到的语言 (zh/en)

    // 时间
    var createdAt: Date
    var updatedAt: Date
    var publishedAt: Date?             // 原文发布时间
    var lastReadAt: Date?

    // 来源
    var sourceTypeRaw: String          // web/wechat/twitter/weibo/zhihu/newsletter/youtube

    // 客户端内容提取
    var extractionSourceRaw: String    // none/client/server
    var clientExtractedAt: Date?       // 客户端提取完成时间

    // 同步
    var syncStateRaw: String           // pendingUpload/synced/pendingUpdate/conflict
    var serverID: String?              // 服务端 ID
}

enum ArticleStatus: String, Codable {
    case pending      // 等待抓取
    case processing   // 抓取/AI处理中
    case ready        // 处理完成
    case failed       // 处理失败
    case clientReady  // 客户端提取完成，等待服务端处理
}

enum ExtractionSource: String, Codable {
    case none     // 未提取
    case client   // 客户端提取
    case server   // 服务端提取
}

enum SourceType: String, Codable {
    case web        // 通用网页
    case wechat     // 微信公众号
    case twitter    // Twitter/X
    case weibo      // 微博
    case zhihu      // 知乎
    case newsletter // Newsletter
    case youtube    // YouTube

    var supportsClientExtraction: Bool {
        switch self {
        case .youtube: return false
        default: return true
        }
    }

    static func detect(from url: String) -> SourceType {
        if url.contains("mp.weixin.qq.com") { return .wechat }
        if url.contains("twitter.com") || url.contains("x.com") { return .twitter }
        if url.contains("weibo.com") || url.contains("weibo.cn") { return .weibo }
        if url.contains("zhihu.com") { return .zhihu }
        if url.contains("youtube.com") || url.contains("youtu.be") { return .youtube }
        return .web
    }
}

enum SyncState: String, Codable {
    case pendingUpload  // 待上传
    case synced         // 已同步
    case pendingUpdate  // 待更新
    case conflict       // 同步冲突
}

// MARK: - 标签模型
@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var isUserCreated: Bool            // 区分用户创建和 AI 生成
    var articleCount: Int = 0
    var articles: [Article]
    var createdAt: Date

    init(name: String, isUserCreated: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isUserCreated = isUserCreated
        self.articles = []
        self.createdAt = Date()
    }
}

// MARK: - 分类模型
@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String                   // 技术/商业/生活/科学/文化/...
    var icon: String                   // SF Symbol 名称
    var articleCount: Int = 0
    var createdAt: Date

    init(name: String, icon: String) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.createdAt = Date()
    }
}
```

### 2.4 SQLite FTS5 全文搜索方案

SwiftData 底层基于 SQLite，可以直接创建 FTS5 虚拟表实现高性能全文搜索。

#### 2.4.1 FTS5 架构

```
┌─────────────────────────────────────────────┐
│              搜索层                           │
│                                             │
│  ┌─────────────────┐  ┌─────────────────┐  │
│  │  SearchManager   │  │  FTS5Indexer    │  │
│  │                 │  │                 │  │
│  │  ·fullText()    │  │  ·addToIndex()  │  │
│  │  ·byTag()      │  │  ·removeIndex() │  │
│  │  ·byCategory() │  │  ·rebuildAll()  │  │
│  │  ·combined()   │  │  ·updateIndex() │  │
│  └────────┬────────┘  └────────┬────────┘  │
│           │                    │            │
│           ▼                    ▼            │
│  ┌─────────────────────────────────────┐   │
│  │         SQLite Database              │   │
│  │                                     │   │
│  │  ┌─────────────┐ ┌──────────────┐  │   │
│  │  │ SwiftData   │ │ FTS5 虚拟表   │  │   │
│  │  │ 主数据表     │ │ article_fts  │  │   │
│  │  │ (articles)  │◀│              │  │   │
│  │  │             │ │ ·title       │  │   │
│  │  │             │ │ ·content     │  │   │
│  │  │             │ │ ·summary     │  │   │
│  │  │             │ │ ·tags        │  │   │
│  │  └─────────────┘ └──────────────┘  │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

#### 2.4.2 FTS5 索引管理

```swift
import SQLite3

class FTS5SearchManager {
    private var db: OpaquePointer?

    init(databasePath: String) {
        sqlite3_open(databasePath, &db)
        createFTSTable()
    }

    /// 创建 FTS5 虚拟表，使用 simple 分词器支持中文
    private func createFTSTable() {
        let sql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS article_fts USING fts5(
            article_id UNINDEXED,
            title,
            content,
            summary,
            tags,
            author,
            site_name,
            tokenize='unicode61 remove_diacritics 2'
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// 添加文章到全文索引
    func indexArticle(_ article: Article) {
        let sql = """
        INSERT INTO article_fts(article_id, title, content, summary, tags, author, site_name)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, article.id.uuidString, -1, nil)
        sqlite3_bind_text(stmt, 2, article.title ?? "", -1, nil)
        sqlite3_bind_text(stmt, 3, article.markdownContent ?? "", -1, nil)
        sqlite3_bind_text(stmt, 4, article.summary ?? "", -1, nil)
        sqlite3_bind_text(stmt, 5, article.tags.map(\.name).joined(separator: " "), -1, nil)
        sqlite3_bind_text(stmt, 6, article.author ?? "", -1, nil)
        sqlite3_bind_text(stmt, 7, article.siteName ?? "", -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// 全文搜索，支持中文关键词
    func search(query: String, limit: Int = 50) -> [UUID] {
        // FTS5 MATCH 查询，bm25 排序
        let sql = """
        SELECT article_id, bm25(article_fts, 0, 10.0, 5.0, 3.0, 2.0, 1.0, 1.0) AS rank
        FROM article_fts
        WHERE article_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        var results: [UUID] = []
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        // 对搜索词进行处理，支持前缀匹配
        let processedQuery = query.split(separator: " ")
            .map { "\($0)*" }
            .joined(separator: " ")
        sqlite3_bind_text(stmt, 1, processedQuery, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0),
               let uuid = UUID(uuidString: String(cString: cString)) {
                results.append(uuid)
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    /// 搜索结果高亮
    func searchWithHighlight(query: String) -> [(UUID, String)] {
        let sql = """
        SELECT article_id,
               highlight(article_fts, 1, '<mark>', '</mark>') AS highlighted_title
        FROM article_fts
        WHERE article_fts MATCH ?
        ORDER BY bm25(article_fts)
        LIMIT 50;
        """
        // ... 执行查询并返回高亮结果
        return []
    }
}
```

### 2.5 离线处理和队列管理

```swift
import BackgroundTasks
import Network

/// 离线队列管理器 — 管理 Share Extension 保存但未处理的文章
class OfflineQueueManager: ObservableObject {
    @Published var pendingCount: Int = 0

    private let networkMonitor = NWPathMonitor()
    private let processingQueue = DispatchQueue(label: "com.folio.processing")
    private var isProcessing = false

    init() {
        startNetworkMonitoring()
        registerBackgroundTask()
    }

    /// 监控网络状态，恢复网络后自动处理队列
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.processQueue()
            }
        }
        networkMonitor.start(queue: processingQueue)
    }

    /// 注册后台任务，App 进入后台时继续处理
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.folio.article-processing",
            using: nil
        ) { task in
            self.handleBackgroundTask(task as! BGProcessingTask)
        }
    }

    /// 处理待办队列
    func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true

        Task {
            let context = ModelContext(SharedDataManager.shared.container)
            let descriptor = FetchDescriptor<Article>(
                predicate: #Predicate { $0.status == .pending },
                sortBy: [SortDescriptor(\.createdAt)]
            )

            guard let pendingArticles = try? context.fetch(descriptor) else {
                isProcessing = false
                return
            }

            for article in pendingArticles {
                do {
                    // 发送到后端处理
                    article.status = .processing
                    try context.save()

                    let result = try await APIClient.shared.submitArticle(
                        url: article.url
                    )
                    article.serverID = result.taskID
                    try context.save()

                    // 轮询结果
                    let processed = try await APIClient.shared.pollResult(
                        taskID: result.taskID,
                        maxRetries: 30,
                        interval: 2.0
                    )

                    // 更新本地数据
                    article.title = processed.title
                    article.markdownContent = processed.markdown
                    article.summary = processed.summary
                    article.keyPoints = processed.keyPoints
                    article.author = processed.author
                    article.publishedAt = processed.publishedAt
                    article.status = .ready
                    try context.save()

                    // 更新 FTS5 索引
                    FTS5SearchManager.shared.indexArticle(article)

                } catch {
                    article.status = .failed
                    try? context.save()
                }
            }

            isProcessing = false
            await MainActor.run {
                self.pendingCount = 0
            }
        }
    }
}
```

### 2.6 iCloud CloudKit 同步方案

CloudKit 同步为 Pro+ 付费功能，实现跨设备收藏同步。

#### 2.6.1 同步架构

```
┌──────────────────┐              ┌──────────────────┐
│    iPhone         │              │     iPad          │
│                  │              │                  │
│  ┌────────────┐  │              │  ┌────────────┐  │
│  │ SwiftData  │  │   CloudKit   │  │ SwiftData  │  │
│  │ 本地数据库  │◀──── Private ────▶│ 本地数据库  │  │
│  │            │  │   Database   │  │            │  │
│  └────────────┘  │              │  └────────────┘  │
│                  │              │                  │
│  ┌────────────┐  │              │  ┌────────────┐  │
│  │ FTS5 索引  │  │              │  │ FTS5 索引  │  │
│  │ (本地重建)  │  │              │  │ (本地重建)  │  │
│  └────────────┘  │              │  └────────────┘  │
└──────────────────┘              └──────────────────┘
```

#### 2.6.2 同步策略

```swift
/// CloudKit 同步配置
/// SwiftData 原生支持 CloudKit 同步，通过 ModelConfiguration 启用
class CloudSyncManager {

    static func createContainer(enableSync: Bool) -> ModelContainer {
        let schema = Schema([Article.self, Tag.self, Category.self])

        let config: ModelConfiguration
        if enableSync {
            // Pro+ 用户：启用 CloudKit 同步
            config = ModelConfiguration(
                schema: schema,
                groupContainer: .identifier("group.com.folio.app"),
                cloudKitDatabase: .private("iCloud.com.folio.app")
            )
        } else {
            // 免费/Pro 用户：仅本地存储
            config = ModelConfiguration(
                schema: schema,
                groupContainer: .identifier("group.com.folio.app"),
                cloudKitDatabase: .none
            )
        }

        return try! ModelContainer(for: schema, configurations: [config])
    }
}
```

**同步注意事项**：
- FTS5 虚拟表不通过 CloudKit 同步，在新设备上需要本地重建索引
- Markdown 正文体积较大，采用增量同步策略减少流量
- 同步冲突时采用"最后写入胜出"策略，保留两端变更记录
- 离线修改在恢复网络后自动合并

---

## 三、后端服务架构

### 3.1 架构概述

后端采用 **Go + Reader + Python** 三服务协作架构：

- **Go API 服务**：核心后端，处理 API 请求、任务编排、数据库读写
- **Reader 抓取服务**：基于 `@vakra-dev/reader`，提供 HTTP 接口供 Go 调用，负责网页抓取和 Markdown 转换
- **Python AI 服务**：负责 AI 分类/标签/摘要/要点提取

Go 服务通过 asynq（基于 Redis 的异步任务框架）编排抓取和 AI 处理流程，Reader 和 AI 服务作为内部微服务被 Go Worker 调用。

### 3.2 服务划分和目录结构

```
folio-server/
├── cmd/
│   └── server/
│       └── main.go               # Go 服务入口
│
├── internal/
│   ├── api/                      # HTTP API 层 (chi router)
│   │   ├── router.go             # 路由定义
│   │   ├── middleware/
│   │   │   ├── auth.go           # JWT 认证中间件
│   │   │   ├── ratelimit.go      # 限流中间件
│   │   │   └── cors.go           # CORS 中间件
│   │   └── handler/
│   │       ├── auth.go           # 登录/注册接口
│   │       ├── article.go        # 文章 CRUD 接口
│   │       ├── search.go         # 搜索接口
│   │       ├── tag.go            # 标签接口
│   │       ├── category.go       # 分类接口
│   │       ├── task.go           # 任务状态查询接口
│   │       └── subscription.go   # 订阅验证接口
│   │
│   ├── domain/                   # 领域模型
│   │   ├── article.go
│   │   ├── tag.go
│   │   ├── category.go
│   │   ├── user.go
│   │   └── task.go
│   │
│   ├── service/                  # 业务逻辑层
│   │   ├── article.go            # 文章业务逻辑
│   │   ├── auth.go               # 认证逻辑 (Apple ID)
│   │   ├── quota.go              # 配额管理
│   │   └── tag.go                # 标签业务逻辑
│   │
│   ├── repository/               # 数据访问层 (pgx)
│   │   ├── article.go
│   │   ├── tag.go
│   │   ├── category.go
│   │   ├── user.go
│   │   └── task.go
│   │
│   ├── worker/                   # 异步任务 Worker (asynq)
│   │   ├── server.go             # asynq Worker 服务器
│   │   ├── tasks.go              # 任务类型定义
│   │   ├── crawl_handler.go      # 抓取任务处理（调用 Reader）
│   │   ├── ai_handler.go         # AI 处理任务（调用 Python 服务）
│   │   └── image_handler.go      # 图片转存任务（下载到 R2）
│   │
│   ├── client/                   # 外部服务客户端
│   │   ├── reader.go             # Reader 服务 HTTP 客户端
│   │   ├── ai.go                 # AI 服务 HTTP 客户端
│   │   └── r2.go                 # Cloudflare R2 客户端 (S3 SDK)
│   │
│   └── config/
│       └── config.go             # 配置加载 (envconfig)
│
├── migrations/                   # PostgreSQL 数据库迁移
│   ├── 001_init.up.sql
│   └── 001_init.down.sql
│
├── reader-service/               # Reader 抓取服务（Node.js 薄包装）
│   ├── index.ts                  # Express HTTP 包装，暴露 POST /scrape
│   ├── package.json
│   └── Dockerfile
│
├── ai-service/                   # Python AI 处理服务
│   ├── app/
│   │   ├── main.py               # FastAPI 入口
│   │   ├── pipeline.py           # AI 处理 Pipeline
│   │   ├── prompts/              # Prompt 模板
│   │   │   ├── combined.py       # 合并 Prompt（分类+标签+摘要+要点）
│   │   │   ├── classify.py       # 分类 Prompt（备用）
│   │   │   ├── summarize.py      # 摘要 Prompt（备用）
│   │   │   └── extract_tags.py   # 标签提取 Prompt（备用）
│   │   ├── cache.py              # AI 结果缓存
│   │   └── models.py             # 数据模型
│   ├── requirements.txt
│   └── Dockerfile
│
├── docker-compose.yml
├── Caddyfile                     # Caddy 反向代理配置
├── Dockerfile                    # Go 服务 Dockerfile
├── go.mod
└── go.sum
```

### 3.3 Reader 抓取服务集成

#### 3.3.1 Reader 能力概述

Folio 的网页抓取能力基于 `@vakra-dev/reader`（独立开源项目），以 HTTP 微服务形式运行。Reader 提供：

| 能力 | 实现方式 |
|------|---------|
| 多引擎级联抓取 | HTTP Engine → TLS Client (got-scraping) → Hero (全功能浏览器)，自动降级 |
| 正文提取 | 自动去导航/侧边栏/广告/弹窗，仅保留主体内容 |
| HTML → Markdown | Rust 实现的 supermarkdown，高性能转换 |
| 元数据提取 | Open Graph / Twitter Card / SEO 元数据（标题、作者、封面图等） |
| 反爬突破 | Cloudflare 多信号检测+绕过、TLS 指纹模拟、WebRTC 遮蔽 |
| 浏览器池 | 预热 + 自动回收 + 健康监控，适合长期运行 |

#### 3.3.2 Reader 服务 HTTP 包装

Reader 本身是 Node.js 库，通过一个薄 HTTP 层暴露给 Go 后端调用：

```typescript
// reader-service/index.ts — Reader 的 HTTP 包装服务
import express from "express";
import { ReaderClient } from "@vakra-dev/reader";

const app = express();
app.use(express.json());

const reader = new ReaderClient({
  verbose: process.env.NODE_ENV !== "production",
});

// 单 URL 抓取
app.post("/scrape", async (req, res) => {
  const { url, timeout_ms } = req.body;

  if (!url) {
    return res.status(400).json({ error: "url is required" });
  }

  try {
    const result = await reader.scrape({
      urls: [url],
      formats: ["markdown"],
      onlyMainContent: true,
      removeAds: true,
      timeoutMs: timeout_ms || 30000,
      maxRetries: 2,
    });

    const page = result.data[0];
    if (!page || !page.markdown) {
      return res.status(422).json({ error: "failed to extract content" });
    }

    res.json({
      markdown: page.markdown,
      metadata: page.metadata?.website || {},
      duration_ms: page.metadata?.duration || 0,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 健康检查
app.get("/health", (_, res) => res.json({ status: "ok" }));

app.listen(3000, () => console.log("Reader service listening on :3000"));
```

Reader 返回的 metadata 结构包含：

```typescript
{
  metadata: {
    website: {
      title: string;         // 页面标题
      description: string;   // 页面描述 (meta description / OG description)
      author: string;        // 作者
      siteName: string;      // 站点名称 (OG site_name)
      favicon: string;       // favicon URL
      ogImage: string;       // Open Graph 封面图
      language: string;      // 页面语言
      charset: string;       // 字符编码
      canonical: string;     // canonical URL
    }
  }
}
```

#### 3.3.3 Go 调用 Reader 客户端

```go
// internal/client/reader.go — Reader 服务 HTTP 客户端
package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type ReaderClient struct {
	baseURL    string
	httpClient *http.Client
}

type ScrapeRequest struct {
	URL       string `json:"url"`
	TimeoutMs int    `json:"timeout_ms,omitempty"`
}

type ScrapeResponse struct {
	Markdown   string         `json:"markdown"`
	Metadata   ReaderMetadata `json:"metadata"`
	DurationMs int            `json:"duration_ms"`
}

type ReaderMetadata struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Author      string `json:"author"`
	SiteName    string `json:"siteName"`
	Favicon     string `json:"favicon"`
	OGImage     string `json:"ogImage"`
	Language    string `json:"language"`
	Canonical   string `json:"canonical"`
}

func NewReaderClient(baseURL string) *ReaderClient {
	return &ReaderClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 60 * time.Second, // Reader 内部有自己的超时，这里设一个宽松的外层超时
		},
	}
}

func (c *ReaderClient) Scrape(ctx context.Context, url string) (*ScrapeResponse, error) {
	body, _ := json.Marshal(ScrapeRequest{URL: url, TimeoutMs: 30000})

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/scrape", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("reader request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errResp struct{ Error string `json:"error"` }
		json.NewDecoder(resp.Body).Decode(&errResp)
		return nil, fmt.Errorf("reader error (status %d): %s", resp.StatusCode, errResp.Error)
	}

	var result ScrapeResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}
```

#### 3.3.4 内容源识别与特殊处理

Reader 已覆盖大部分通用网页的抓取。Folio 在 Go 层做内容源识别和后处理：

```go
// internal/service/source.go — 内容源识别
package service

import "strings"

type SourceType string

const (
	SourceWeb     SourceType = "web"
	SourceWechat  SourceType = "wechat"
	SourceTwitter SourceType = "twitter"
	SourceWeibo   SourceType = "weibo"
	SourceZhihu   SourceType = "zhihu"
)

func DetectSource(url string) SourceType {
	switch {
	case strings.Contains(url, "mp.weixin.qq.com"):
		return SourceWechat
	case strings.Contains(url, "twitter.com"), strings.Contains(url, "x.com"):
		return SourceTwitter
	case strings.Contains(url, "weibo.com"), strings.Contains(url, "weibo.cn"):
		return SourceWeibo
	case strings.Contains(url, "zhihu.com"):
		return SourceZhihu
	default:
		return SourceWeb
	}
}
```

**各内容源与 Reader 的配合策略**：

```
┌──────────────────────────────────────────────────────────────┐
│                  内容源抓取策略矩阵                             │
│                                                              │
│  内容源         Reader 负责           Go 后处理               │
│  ──────────   ──────────────────   ──────────────────────   │
│  通用网页      正文提取+Markdown     图片转存 R2              │
│  微信公众号    浏览器引擎抓取         防盗链图片代理下载+转存  │
│  Twitter/X     页面抓取               Thread 合并（后续优化） │
│  微博          浏览器引擎抓取         短链展开、图片转存       │
│  知乎          页面抓取               回答/文章区分处理        │
│                                                              │
│  Reader 抓取失败时的降级：                                     │
│  ·Reader 内部已有 3 级引擎降级（HTTP→TLS→Browser）            │
│  ·所有引擎均失败 → Go 保存原始 URL，标记 "fetch_failed"       │
│  ·asynq 自动重试（指数退避，最多 3 次）                        │
│  ·最终失败 → 通知用户"抓取失败，已保存链接"                    │
└──────────────────────────────────────────────────────────────┘
```

### 3.4 Go Worker 任务编排

Go 后端使用 asynq（基于 Redis 的异步任务框架）编排抓取和 AI 处理流程。

#### 3.4.1 任务定义

```go
// internal/worker/tasks.go — 任务类型定义
package worker

const (
	TypeCrawlArticle = "article:crawl"   // 抓取文章
	TypeAIProcess    = "article:ai"      // AI 处理
	TypeImageUpload  = "article:images"  // 图片转存
)

type CrawlPayload struct {
	ArticleID string `json:"article_id"`
	URL       string `json:"url"`
	UserID    string `json:"user_id"`
}

type AIProcessPayload struct {
	ArticleID string `json:"article_id"`
	Title     string `json:"title"`
	Markdown  string `json:"markdown"`
	Source    string `json:"source"`
	Author    string `json:"author"`
}

type ImageUploadPayload struct {
	ArticleID string   `json:"article_id"`
	ImageURLs []string `json:"image_urls"`
}
```

#### 3.4.2 抓取任务 Handler

```go
// internal/worker/crawl_handler.go — 抓取任务处理
package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/hibiken/asynq"
	"folio/internal/client"
	"folio/internal/repository"
)

type CrawlHandler struct {
	reader   *client.ReaderClient
	aiClient *client.AIClient
	repo     *repository.ArticleRepo
	queue    *asynq.Client
}

func (h *CrawlHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p CrawlPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal payload: %w", err)
	}

	slog.Info("crawl started", "article_id", p.ArticleID, "url", p.URL)

	// Step 1: 调用 Reader 抓取
	h.repo.UpdateStatus(ctx, p.ArticleID, "processing")

	result, err := h.reader.Scrape(ctx, p.URL)
	if err != nil {
		h.repo.UpdateStatus(ctx, p.ArticleID, "failed")
		h.repo.SetError(ctx, p.ArticleID, err.Error())
		return fmt.Errorf("reader scrape: %w", err)
	}

	// Step 2: 保存抓取结果
	h.repo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
		Title:       result.Metadata.Title,
		Author:      result.Metadata.Author,
		SiteName:    result.Metadata.SiteName,
		Markdown:    result.Markdown,
		CoverImage:  result.Metadata.OGImage,
		Language:    result.Metadata.Language,
		FaviconURL:  result.Metadata.Favicon,
	})

	// Step 3: 入队 AI 处理任务
	aiPayload, _ := json.Marshal(AIProcessPayload{
		ArticleID: p.ArticleID,
		Title:     result.Metadata.Title,
		Markdown:  result.Markdown,
		Source:    result.Metadata.SiteName,
		Author:    result.Metadata.Author,
	})
	_, err = h.queue.EnqueueContext(ctx, asynq.NewTask(TypeAIProcess, aiPayload))
	if err != nil {
		slog.Error("enqueue AI task failed", "err", err)
	}

	// Step 4: 入队图片转存任务（异步，不阻塞主流程）
	imageURLs := extractImageURLs(result.Markdown)
	if len(imageURLs) > 0 {
		imgPayload, _ := json.Marshal(ImageUploadPayload{
			ArticleID: p.ArticleID,
			ImageURLs: imageURLs,
		})
		h.queue.EnqueueContext(ctx, asynq.NewTask(TypeImageUpload, imgPayload))
	}

	slog.Info("crawl completed", "article_id", p.ArticleID, "title", result.Metadata.Title)
	return nil
}
```

#### 3.4.3 asynq Worker 启动

```go
// internal/worker/server.go — Worker 服务器
package worker

import (
	"log/slog"

	"github.com/hibiken/asynq"
)

func StartWorker(redisAddr string, handlers *Handlers) {
	srv := asynq.NewServer(
		asynq.RedisClientOpt{Addr: redisAddr},
		asynq.Config{
			Concurrency: 10,
			Queues: map[string]int{
				"critical": 6, // 抓取任务
				"default":  3, // AI 处理
				"low":      1, // 图片转存
			},
			ErrorHandler: asynq.ErrorHandlerFunc(func(ctx context.Context, task *asynq.Task, err error) {
				slog.Error("task failed", "type", task.Type(), "err", err)
			}),
		},
	)

	mux := asynq.NewServeMux()
	mux.HandleFunc(TypeCrawlArticle, handlers.Crawl.ProcessTask)
	mux.HandleFunc(TypeAIProcess, handlers.AI.ProcessTask)
	mux.HandleFunc(TypeImageUpload, handlers.Image.ProcessTask)

	if err := srv.Run(mux); err != nil {
		slog.Error("worker server failed", "err", err)
	}
}
```

#### 3.4.4 Go AI 服务客户端

```go
// internal/client/ai.go — AI 服务 HTTP 客户端
package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type AIClient struct {
	baseURL    string
	httpClient *http.Client
}

type AnalyzeRequest struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Source  string `json:"source"`
	Author  string `json:"author"`
}

type AnalyzeResponse struct {
	Category     string   `json:"category"`
	CategoryName string   `json:"category_name"`
	Confidence   float64  `json:"confidence"`
	Tags         []string `json:"tags"`
	Summary      string   `json:"summary"`
	KeyPoints    []string `json:"key_points"`
	Language     string   `json:"language"`
}

func NewAIClient(baseURL string) *AIClient {
	return &AIClient{
		baseURL:    baseURL,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

func (c *AIClient) Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error) {
	body, _ := json.Marshal(req)

	httpReq, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/analyze", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("ai request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ai service error: status %d", resp.StatusCode)
	}

	var result AnalyzeResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}
```

---

### 3.5 AI 处理 Pipeline 详细设计

#### 3.5.1 Pipeline 架构

Go Worker 通过 HTTP 调用 Python AI 服务，AI 服务内部完成预处理、调用 DeepSeek API、验证和缓存。

```
Go Worker（asynq 任务）
         │
         │ POST /api/analyze
         ▼
┌─────────────────────────────────────────┐
│      Python AI 服务 (FastAPI)            │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  Step 1: 内容预处理              │    │
│  │  ·截断超长内容（保留前 4000 字）  │    │
│  │  ·去除无意义格式字符             │    │
│  │  ·提取关键段落                   │    │
│  └──────────────┬──────────────────┘    │
│                 │                        │
│                 ▼                        │
│  ┌─────────────────────────────────┐    │
│  │  Step 2: 单次 AI 调用（合并）    │    │
│  │  ·分类 + 标签 + 摘要 + 要点      │    │
│  │  ·一次 API 调用完成所有任务       │    │
│  │  ·结构化 JSON 输出               │    │
│  └──────────────┬──────────────────┘    │
│                 │                        │
│                 ▼                        │
│  ┌─────────────────────────────────┐    │
│  │  Step 3: 结果验证与缓存          │    │
│  │  ·校验分类是否在预定义列表中      │    │
│  │  ·校验标签数量（3-5个）          │    │
│  │  ·校验摘要长度（<=100字）        │    │
│  │  ·缓存结果到 Redis（7天）        │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

#### 3.5.2 合并 Prompt 设计（核心）

为了降低 API 调用成本，将分类、标签、摘要、要点提取合并为单次调用：

```python
# ai-service/app/prompts/combined.py

COMBINED_ANALYSIS_SYSTEM_PROMPT = """你是一个专业的内容分析助手。你的任务是对给定的文章内容进行分析，输出结构化的 JSON 结果。

你需要完成以下四项分析任务：

## 任务 1: 内容分类
从以下预定义分类中选择最匹配的一个：
- 技术 (tech) — 编程、软件、互联网、AI、硬件
- 商业 (business) — 创业、投资、管理、市场、产品
- 科学 (science) — 自然科学、数学、医学、心理学
- 文化 (culture) — 文学、艺术、历史、哲学、音乐
- 生活 (lifestyle) — 健康、美食、旅行、育儿、家居
- 时事 (news) — 新闻、政策、社会事件、行业动态
- 学习 (education) — 学习方法、课程、语言、考试
- 设计 (design) — UI/UX、平面设计、建筑、工业设计
- 其他 (other) — 不属于以上任何分类

## 任务 2: 标签提取
提取 3-5 个最能概括文章核心主题的关键标签。要求：
- 标签应具体而非泛泛（例如用"React性能优化"而非"前端"）
- 标签长度 2-8 个字
- 优先使用中文，专有名词可用英文（如 "GPT-4", "SwiftUI"）

## 任务 3: 一句话摘要
用一句话概括文章的核心内容，不超过 100 个字。要求：
- 准确传达文章最重要的信息
- 简洁有力，避免空洞的形容词
- 使用与原文相同的语言

## 任务 4: 要点提取
提取 3-5 个文章的核心要点。要求：
- 每个要点一句话，不超过 50 字
- 要点之间不重复
- 按重要性排序

## 输出格式
请严格按以下 JSON 格式输出，不要包含任何其他内容：
```json
{
  "category": "tech",
  "category_name": "技术",
  "confidence": 0.95,
  "tags": ["标签1", "标签2", "标签3"],
  "summary": "一句话摘要内容",
  "key_points": [
    "要点1",
    "要点2",
    "要点3"
  ],
  "language": "zh"
}
```"""

COMBINED_ANALYSIS_USER_PROMPT = """请分析以下文章：

标题：{title}
来源：{source}
作者：{author}

正文内容：
{content}"""
```

#### 3.5.3 分类 Prompt 设计（独立版，备用）

```python
# ai-service/app/prompts/classify.py

CLASSIFY_SYSTEM_PROMPT = """你是一个内容分类专家。根据文章内容，从以下分类中选择最匹配的一个。

可选分类：
1. tech (技术) — 编程、软件、互联网、AI、硬件
2. business (商业) — 创业、投资、管理、市场、产品
3. science (科学) — 自然科学、数学、医学、心理学
4. culture (文化) — 文学、艺术、历史、哲学、音乐
5. lifestyle (生活) — 健康、美食、旅行、育儿、家居
6. news (时事) — 新闻、政策、社会事件
7. education (学习) — 学习方法、课程、语言
8. design (设计) — UI/UX、平面设计、建筑
9. other (其他)

仅输出 JSON：{"category": "分类ID", "category_name": "中文名", "confidence": 0.0-1.0}"""

CLASSIFY_USER_PROMPT = """文章标题：{title}
文章摘要（前500字）：{content_preview}"""
```

#### 3.5.4 摘要 Prompt 设计（独立版，备用）

```python
# ai-service/app/prompts/summarize.py

SUMMARIZE_SYSTEM_PROMPT = """你是一个专业的文章摘要生成器。请用一句话概括文章的核心内容。

要求：
- 不超过 100 个字
- 准确传达文章最重要的观点或信息
- 简洁有力，不使用"本文介绍了""本文讨论了"等开头
- 使用与原文相同的语言（中文或英文）
- 不添加原文中没有的观点

仅输出摘要文本，不要任何其他内容。"""

SUMMARIZE_USER_PROMPT = """标题：{title}
正文：{content}"""
```

#### 3.5.5 标签提取 Prompt 设计（独立版，备用）

```python
# ai-service/app/prompts/extract_tags.py

EXTRACT_TAGS_SYSTEM_PROMPT = """你是一个关键词提取专家。从文章中提取 3-5 个最能代表核心主题的标签。

要求：
- 标签数量：3-5 个
- 标签长度：2-8 个字
- 标签应具体、有区分度（例如用"React Hooks"而非"前端"）
- 优先使用中文，技术专有名词可用英文
- 按相关性从高到低排序
- 不重复、不冗余

仅输出 JSON 数组：["标签1", "标签2", "标签3"]"""

EXTRACT_TAGS_USER_PROMPT = """标题：{title}
正文：{content}"""
```

#### 3.5.6 AI Pipeline Python 实现

```python
# ai-service/app/pipeline.py

import json
import hashlib
from openai import AsyncOpenAI
from app.prompts.combined import (
    COMBINED_ANALYSIS_SYSTEM_PROMPT,
    COMBINED_ANALYSIS_USER_PROMPT,
)
from app.cache import RedisCache

client = AsyncOpenAI(
    api_key=os.getenv("DEEPSEEK_API_KEY"),
    base_url="https://api.deepseek.com",
)
cache = RedisCache()


class AIPipeline:
    """AI 内容分析 Pipeline"""

    MODEL = "deepseek-chat"
    MAX_CONTENT_LENGTH = 4000  # 最大输入字数
    CACHE_TTL = 7 * 24 * 3600  # 缓存 7 天

    async def process(self, article: dict) -> dict:
        """
        处理单篇文章，返回分析结果。

        参数:
            article: {
                "title": "文章标题",
                "content": "Markdown 正文",
                "source": "来源站点",
                "author": "作者"
            }
        返回:
            {
                "category": "tech",
                "category_name": "技术",
                "confidence": 0.95,
                "tags": ["标签1", "标签2", "标签3"],
                "summary": "一句话摘要",
                "key_points": ["要点1", "要点2", "要点3"],
                "language": "zh"
            }
        """
        # Step 1: 检查缓存
        cache_key = self._cache_key(article["content"])
        cached = await cache.get(cache_key)
        if cached:
            return json.loads(cached)

        # Step 2: 预处理内容
        processed_content = self._preprocess(article["content"])

        # Step 3: 调用 DeepSeek API（单次调用完成所有任务）
        user_message = COMBINED_ANALYSIS_USER_PROMPT.format(
            title=article.get("title", "无标题"),
            source=article.get("source", "未知来源"),
            author=article.get("author", "未知作者"),
            content=processed_content,
        )

        response = await client.chat.completions.create(
            model=self.MODEL,
            max_tokens=1024,
            temperature=0.3,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": COMBINED_ANALYSIS_SYSTEM_PROMPT},
                {"role": "user", "content": user_message},
            ],
        )

        # Step 4: 解析和验证结果
        result = self._parse_response(response.choices[0].message.content)
        validated = self._validate(result)

        # Step 5: 缓存结果
        await cache.set(cache_key, json.dumps(validated), ttl=self.CACHE_TTL)

        return validated

    def _preprocess(self, content: str) -> str:
        """预处理内容：截断、清理"""
        # 去除多余空行和格式字符
        lines = content.strip().split("\n")
        cleaned = "\n".join(line for line in lines if line.strip())
        # 截断到最大长度
        if len(cleaned) > self.MAX_CONTENT_LENGTH:
            cleaned = cleaned[: self.MAX_CONTENT_LENGTH] + "\n\n[内容已截断]"
        return cleaned

    def _parse_response(self, text: str) -> dict:
        """从 AI 响应中解析 JSON"""
        # 尝试直接解析
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass
        # 尝试提取 JSON 代码块
        import re
        json_match = re.search(r"```json\s*(.*?)\s*```", text, re.DOTALL)
        if json_match:
            return json.loads(json_match.group(1))
        raise ValueError(f"无法解析 AI 响应: {text[:200]}")

    def _validate(self, result: dict) -> dict:
        """验证 AI 输出的格式和内容"""
        valid_categories = [
            "tech", "business", "science", "culture",
            "lifestyle", "news", "education", "design", "other"
        ]

        # 验证分类
        if result.get("category") not in valid_categories:
            result["category"] = "other"
            result["category_name"] = "其他"

        # 验证标签数量
        tags = result.get("tags", [])
        if len(tags) > 5:
            result["tags"] = tags[:5]
        elif len(tags) < 1:
            result["tags"] = ["未分类"]

        # 验证摘要长度
        summary = result.get("summary", "")
        if len(summary) > 100:
            result["summary"] = summary[:97] + "..."

        # 验证要点
        key_points = result.get("key_points", [])
        if len(key_points) > 5:
            result["key_points"] = key_points[:5]

        return result

    def _cache_key(self, content: str) -> str:
        """生成内容哈希作为缓存 Key"""
        content_hash = hashlib.md5(content.encode()).hexdigest()
        return f"ai:analysis:{content_hash}"


class BatchProcessor:
    """批量处理器 — 用于处理积压的文章"""

    def __init__(self, pipeline: AIPipeline, concurrency: int = 3):
        self.pipeline = pipeline
        self.concurrency = concurrency  # 并发数，控制 API 调用速率

    async def process_batch(self, articles: list[dict]) -> list[dict]:
        """并发处理一批文章"""
        import asyncio

        semaphore = asyncio.Semaphore(self.concurrency)
        results = []

        async def process_one(article):
            async with semaphore:
                try:
                    result = await self.pipeline.process(article)
                    return {"article_id": article["id"], "status": "success", **result}
                except Exception as e:
                    return {"article_id": article["id"], "status": "error", "error": str(e)}

        tasks = [process_one(article) for article in articles]
        results = await asyncio.gather(*tasks)
        return results
```

#### 3.5.7 成本优化策略

```
┌──────────────────────────────────────────────────────────┐
│                   AI 成本优化策略                          │
│                                                          │
│  1. 合并调用（已实施）                                     │
│     ·分类+标签+摘要+要点 合并为单次 API 调用               │
│     ·相比 4 次独立调用，节省约 60% token 消耗              │
│                                                          │
│  2. 内容截断（已实施）                                     │
│     ·输入内容截断到 4000 字                                │
│     ·大部分文章前 4000 字足以完成分析                      │
│     ·减少 input token 消耗                                │
│                                                          │
│  3. 结果缓存（已实施）                                     │
│     ·相同内容 7 天内不重复调用                              │
│     ·使用内容 MD5 哈希作为缓存 Key                        │
│     ·对于重复收藏的热门文章效果显著                         │
│                                                          │
│  4. 模型选择策略                                          │
│     ·所有用户统一使用 DeepSeek Chat 模型                   │
│     ·DeepSeek 性价比极高，无需按用户等级区分模型            │
│                                                          │
│                                                          │
│  5. 成本估算（基于 DeepSeek Chat）                         │
│     ·每篇文章平均 token 消耗：                             │
│       - Input: ~2000 tokens（系统提示+文章内容）           │
│       - Output: ~300 tokens（JSON 结果）                  │
│     ·单篇成本：约 ¥0.02                                  │
│     ·1000 用户 × 30 篇/月 = 30000 篇/月                  │
│     ·月 AI 成本：约 ¥600                                  │
└──────────────────────────────────────────────────────────┘
```

---

## 四、数据模型设计

### 4.1 iOS 端 SwiftData 模型

（已在 2.3 节详细定义，此处补充关系图）

```
┌──────────────────┐
│     Article       │
│                  │
│  id (UUID, PK)   │       ┌──────────────┐
│  url             │       │     Tag       │
│  title           │  N:M  │              │
│  markdownContent │◀─────▶│  id (UUID)   │
│  summary         │       │  name        │
│  keyPoints       │       │  isUserCreated│
│  status          │       │  articleCount │
│  sourceType      │       └──────────────┘
│  isFavorite      │
│  readProgress    │       ┌──────────────┐
│  createdAt       │  N:1  │   Category   │
│  ...             │──────▶│              │
│                  │       │  id (UUID)   │
└──────────────────┘       │  name        │
                           │  icon        │
                           │  articleCount │
                           └──────────────┘
```

### 4.2 后端数据库表结构（PostgreSQL）

```sql
-- ============================================
-- Folio 后端数据库建表语句
-- PostgreSQL 16+
-- 创建日期：2026-02-20
-- ============================================

-- 启用必要扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- 用于模糊搜索

-- ============================================
-- 用户表
-- ============================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    apple_id        VARCHAR(255) UNIQUE,          -- Sign in with Apple
    email           VARCHAR(255),
    nickname        VARCHAR(100),
    avatar_url      VARCHAR(500),

    -- 订阅信息
    subscription    VARCHAR(20) DEFAULT 'free',   -- free / pro / pro_plus
    subscription_expires_at  TIMESTAMPTZ,

    -- 配额跟踪
    monthly_quota   INTEGER DEFAULT 30,           -- 每月收藏上限
    current_month_count INTEGER DEFAULT 0,        -- 当月已用
    quota_reset_at  TIMESTAMPTZ,                  -- 配额重置时间

    -- 偏好设置
    preferred_language VARCHAR(10) DEFAULT 'zh',  -- zh / en

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_apple_id ON users(apple_id);
CREATE INDEX idx_users_subscription ON users(subscription);

-- ============================================
-- 文章表（核心表）
-- ============================================
CREATE TABLE articles (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- 基本信息
    url             TEXT NOT NULL,
    title           VARCHAR(500),
    author          VARCHAR(200),
    site_name       VARCHAR(200),
    favicon_url     VARCHAR(500),
    cover_image_url VARCHAR(500),

    -- 内容
    markdown_content TEXT,                        -- Markdown 正文
    raw_html        TEXT,                          -- 原始 HTML（可选备份）
    word_count      INTEGER DEFAULT 0,
    language        VARCHAR(10),                   -- zh / en / mixed

    -- AI 分析结果
    category_id     UUID REFERENCES categories(id),
    summary         TEXT,                          -- AI 摘要（<=100字）
    key_points      JSONB DEFAULT '[]',           -- AI 要点 ["要点1", "要点2"]
    ai_confidence   DECIMAL(3,2),                  -- AI 分类置信度

    -- 状态
    status          VARCHAR(20) DEFAULT 'pending', -- pending/processing/ready/failed
    source_type     VARCHAR(20) DEFAULT 'web',     -- web/wechat/twitter/weibo/zhihu
    fetch_error     TEXT,                          -- 抓取失败原因
    retry_count     INTEGER DEFAULT 0,

    -- 用户操作
    is_favorite     BOOLEAN DEFAULT FALSE,
    is_archived     BOOLEAN DEFAULT FALSE,
    read_progress   DECIMAL(3,2) DEFAULT 0.00,    -- 0.00-1.00
    last_read_at    TIMESTAMPTZ,

    -- 原文时间
    published_at    TIMESTAMPTZ,

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_articles_user_id ON articles(user_id);
CREATE INDEX idx_articles_status ON articles(status);
CREATE INDEX idx_articles_category ON articles(category_id);
CREATE INDEX idx_articles_source_type ON articles(source_type);
CREATE INDEX idx_articles_is_favorite ON articles(user_id, is_favorite) WHERE is_favorite = TRUE;
CREATE INDEX idx_articles_created_at ON articles(user_id, created_at DESC);
-- URL 去重索引
CREATE UNIQUE INDEX idx_articles_user_url ON articles(user_id, url);
-- 全文搜索索引（PostgreSQL 端，用于后端搜索需求）
CREATE INDEX idx_articles_title_trgm ON articles USING gin(title gin_trgm_ops);

-- ============================================
-- 分类表
-- ============================================
CREATE TABLE categories (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug            VARCHAR(50) UNIQUE NOT NULL,   -- tech/business/science/...
    name_zh         VARCHAR(50) NOT NULL,          -- 中文名
    name_en         VARCHAR(50) NOT NULL,          -- 英文名
    icon            VARCHAR(50),                    -- SF Symbol 或 emoji
    sort_order      INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 预置分类数据
INSERT INTO categories (slug, name_zh, name_en, icon, sort_order) VALUES
    ('tech',       '技术',   'Technology', 'cpu',              1),
    ('business',   '商业',   'Business',   'chart.bar',        2),
    ('science',    '科学',   'Science',    'atom',             3),
    ('culture',    '文化',   'Culture',    'book',             4),
    ('lifestyle',  '生活',   'Lifestyle',  'heart',            5),
    ('news',       '时事',   'News',       'newspaper',        6),
    ('education',  '学习',   'Education',  'graduationcap',    7),
    ('design',     '设计',   'Design',     'paintbrush',       8),
    ('other',      '其他',   'Other',      'ellipsis.circle',  9);

-- ============================================
-- 标签表
-- ============================================
CREATE TABLE tags (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(50) NOT NULL,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    is_ai_generated BOOLEAN DEFAULT TRUE,
    article_count   INTEGER DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 同一用户下标签名唯一
CREATE UNIQUE INDEX idx_tags_user_name ON tags(user_id, name);
CREATE INDEX idx_tags_article_count ON tags(user_id, article_count DESC);

-- ============================================
-- 文章-标签关联表（多对多）
-- ============================================
CREATE TABLE article_tags (
    article_id      UUID REFERENCES articles(id) ON DELETE CASCADE,
    tag_id          UUID REFERENCES tags(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (article_id, tag_id)
);

CREATE INDEX idx_article_tags_tag ON article_tags(tag_id);

-- ============================================
-- 抓取任务表（用于异步任务跟踪）
-- ============================================
CREATE TABLE crawl_tasks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    article_id      UUID REFERENCES articles(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id),

    url             TEXT NOT NULL,
    source_type     VARCHAR(20),

    status          VARCHAR(20) DEFAULT 'queued',  -- queued/crawling/ai_processing/done/failed

    -- 处理结果
    crawl_started_at  TIMESTAMPTZ,
    crawl_finished_at TIMESTAMPTZ,
    ai_started_at     TIMESTAMPTZ,
    ai_finished_at    TIMESTAMPTZ,

    error_message   TEXT,
    retry_count     INTEGER DEFAULT 0,

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_crawl_tasks_status ON crawl_tasks(status);
CREATE INDEX idx_crawl_tasks_user ON crawl_tasks(user_id);

-- ============================================
-- 用户操作日志表（用于统计和调试）
-- ============================================
CREATE TABLE activity_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    action          VARCHAR(50) NOT NULL,          -- save/read/favorite/archive/delete
    article_id      UUID REFERENCES articles(id) ON DELETE SET NULL,
    metadata        JSONB DEFAULT '{}',
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_activity_logs_user ON activity_logs(user_id, created_at DESC);

-- ============================================
-- 更新时间自动触发器
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_articles_updated_at
    BEFORE UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER tr_crawl_tasks_updated_at
    BEFORE UPDATE ON crawl_tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### 4.3 数据同步模型

```
┌──────────────────────────────────────────────────────────┐
│                   数据同步架构                             │
│                                                          │
│   iOS 客户端（SwiftData）           后端（PostgreSQL）     │
│                                                          │
│   Article                          articles              │
│   ·id (UUID)      ◀─── 映射 ───▶  ·id (UUID)            │
│   ·markdownContent                 ·markdown_content     │
│   ·summary                         ·summary              │
│   ·tags            ◀─── 映射 ───▶  ·article_tags + tags  │
│   ·category        ◀─── 映射 ───▶  ·categories           │
│                                                          │
│   同步方向：后端 → iOS（单向）                              │
│   ·后端是"数据权威源"                                     │
│   ·iOS 端发起抓取请求，后端处理后返回结果                   │
│   ·iOS 端保存到本地 SwiftData                             │
│   ·本地修改（收藏、归档、阅读进度）双向同步                 │
│                                                          │
│   iCloud 同步（Pro+ 功能）：                               │
│   ·SwiftData ←→ CloudKit（Apple 托管）                    │
│   ·跨设备同步本地数据                                     │
│   ·与后端数据独立                                         │
└──────────────────────────────────────────────────────────┘
```

---

## 五、API 接口设计

### 5.1 完整 API 列表

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| POST | /api/v1/auth/apple | Apple ID 登录 | 否 |
| POST | /api/v1/auth/refresh | 刷新 Token | 是（Refresh Token） |
| GET | /api/v1/user/profile | 获取用户信息 | 是 |
| PUT | /api/v1/user/profile | 更新用户信息 | 是 |
| GET | /api/v1/user/quota | 获取当月用量 | 是 |
| POST | /api/v1/articles | 提交 URL 抓取 | 是 |
| GET | /api/v1/articles | 获取文章列表（分页） | 是 |
| GET | /api/v1/articles/:id | 获取文章详情 | 是 |
| PUT | /api/v1/articles/:id | 更新文章（收藏/归档/进度） | 是 |
| DELETE | /api/v1/articles/:id | 删除文章 | 是 |
| GET | /api/v1/articles/search | 搜索文章 | 是 |
| GET | /api/v1/tasks/:id | 查询抓取任务状态 | 是 |
| GET | /api/v1/categories | 获取分类列表 | 是 |
| GET | /api/v1/tags | 获取用户标签列表 | 是 |
| POST | /api/v1/tags | 创建自定义标签 | 是 |
| DELETE | /api/v1/tags/:id | 删除标签 | 是 |
| POST | /api/v1/subscription/verify | 验证 IAP 收据 | 是 |

### 5.2 核心接口请求/响应示例

#### 5.2.1 Apple ID 登录

```
POST /api/v1/auth/apple
Content-Type: application/json

请求：
{
  "identity_token": "eyJraWQiOiJXNldjT0...",
  "authorization_code": "c1234567890abcdef...",
  "user": {
    "name": {
      "firstName": "明",
      "lastName": "张"
    },
    "email": "zhangming@icloud.com"
  }
}

响应 (200)：
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2...",
  "expires_in": 7200,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "nickname": "张明",
    "subscription": "free",
    "monthly_quota": 30,
    "current_month_count": 0
  }
}
```

#### 5.2.2 提交 URL 抓取

```
POST /api/v1/articles
Content-Type: application/json
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

请求：
{
  "url": "https://mp.weixin.qq.com/s/abc123def456",
  "tags": ["AI", "产品思考"],
  "source": "wechat"
}

响应 (202 Accepted)：
{
  "article_id": "660e8400-e29b-41d4-a716-446655440001",
  "task_id": "770e8400-e29b-41d4-a716-446655440002",
  "status": "queued",
  "estimated_seconds": 15,
  "message": "文章已提交处理，请稍候"
}
```

#### 5.2.3 查询任务状态

```
GET /api/v1/tasks/770e8400-e29b-41d4-a716-446655440002
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

响应（处理中）(200)：
{
  "task_id": "770e8400-e29b-41d4-a716-446655440002",
  "status": "ai_processing",
  "progress": {
    "crawl": "done",
    "ai_analysis": "processing"
  },
  "estimated_seconds": 5
}

响应（处理完成）(200)：
{
  "task_id": "770e8400-e29b-41d4-a716-446655440002",
  "status": "done",
  "article_id": "660e8400-e29b-41d4-a716-446655440001"
}
```

#### 5.2.4 获取文章详情

```
GET /api/v1/articles/660e8400-e29b-41d4-a716-446655440001
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

响应 (200)：
{
  "id": "660e8400-e29b-41d4-a716-446655440001",
  "url": "https://mp.weixin.qq.com/s/abc123def456",
  "title": "为什么我认为 AI Agent 是下一个十年的机会",
  "author": "张一鸣的朋友",
  "site_name": "微信公众号",
  "favicon_url": "https://r2.folio.app/favicons/wechat.png",
  "cover_image_url": "https://r2.folio.app/images/article_660e_cover.jpg",
  "markdown_content": "# 为什么我认为 AI Agent 是下一个十年的机会\n\n在过去的一年里...",
  "summary": "作者从技术演进和商业模式两个维度分析了AI Agent将成为继移动互联网之后最大技术浪潮的原因，并预测了三个最有潜力的应用方向。",
  "key_points": [
    "AI Agent 的核心突破在于从被动响应到主动执行的范式转变",
    "个人助理、企业流程自动化、创意工具是三大落地方向",
    "2026-2028年将是 AI Agent 创业的黄金窗口期",
    "数据壁垒和用户习惯是最大的护城河"
  ],
  "category": {
    "slug": "tech",
    "name": "技术"
  },
  "tags": [
    {"id": "tag-uuid-1", "name": "AI Agent"},
    {"id": "tag-uuid-2", "name": "创业机会"},
    {"id": "tag-uuid-3", "name": "技术趋势"}
  ],
  "source_type": "wechat",
  "word_count": 3560,
  "language": "zh",
  "is_favorite": false,
  "is_archived": false,
  "read_progress": 0.0,
  "published_at": "2026-02-18T10:30:00Z",
  "created_at": "2026-02-20T08:15:30Z"
}
```

#### 5.2.5 获取文章列表（分页）

```
GET /api/v1/articles?page=1&per_page=20&category=tech&sort=created_at
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

响应 (200)：
{
  "data": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "title": "为什么我认为 AI Agent 是下一个十年的机会",
      "summary": "作者从技术演进和商业模式两个维度分析了...",
      "cover_image_url": "https://r2.folio.app/images/article_660e_cover.jpg",
      "site_name": "微信公众号",
      "source_type": "wechat",
      "category": {"slug": "tech", "name": "技术"},
      "tags": [{"name": "AI Agent"}, {"name": "创业机会"}],
      "is_favorite": false,
      "read_progress": 0.0,
      "word_count": 3560,
      "created_at": "2026-02-20T08:15:30Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 156,
    "total_pages": 8
  }
}
```

#### 5.2.6 搜索文章

```
GET /api/v1/articles/search?q=AI%20Agent&category=tech&page=1
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

响应 (200)：
{
  "data": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "title": "为什么我认为 <mark>AI Agent</mark> 是下一个十年的机会",
      "summary": "作者从技术演进和商业模式两个维度分析了<mark>AI Agent</mark>将成为...",
      "relevance_score": 0.95,
      "site_name": "微信公众号",
      "created_at": "2026-02-20T08:15:30Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 3,
    "total_pages": 1
  },
  "query": "AI Agent",
  "took_ms": 12
}
```

### 5.3 认证方案

```
┌──────────────────────────────────────────────────────────┐
│                      认证流程                             │
│                                                          │
│  iOS App                     后端服务                     │
│                                                          │
│  ┌──────────┐                                            │
│  │ Sign in  │  identity_token                            │
│  │ with     │────────────────▶ 验证 Apple JWT            │
│  │ Apple    │                  ·验证签名                  │
│  │          │  access_token    ·验证 audience             │
│  │          │◀──────────────── ·创建/查找用户             │
│  └──────────┘  refresh_token   ·颁发 JWT Token           │
│                                                          │
│  后续请求：                                               │
│  ┌──────────┐                                            │
│  │ API 请求  │  Authorization:                            │
│  │          │  Bearer {access_token}                     │
│  │          │────────────────▶ JWT 中间件验证             │
│  │          │                  ·验证签名和过期时间         │
│  │          │  200 / 401       ·提取 user_id             │
│  │          │◀──────────────── ·注入到请求上下文          │
│  └──────────┘                                            │
│                                                          │
│  Token 刷新：                                             │
│  ┌──────────┐                                            │
│  │ Access   │  POST /auth/refresh                        │
│  │ Token    │  {refresh_token}                           │
│  │ 过期     │────────────────▶ 验证 Refresh Token        │
│  │          │  new access_token ·颁发新 Access Token     │
│  │          │◀──────────────── ·Refresh Token 不变       │
│  └──────────┘                                            │
│                                                          │
│  Token 配置：                                             │
│  ·Access Token 有效期：2 小时                             │
│  ·Refresh Token 有效期：90 天                             │
│  ·JWT 签名算法：HS256                                    │
│  ·密钥存储：环境变量（生产环境用 Vault）                   │
└──────────────────────────────────────────────────────────┘
```

---

## 六、部署架构

### 6.1 MVP 阶段部署方案

MVP 阶段采用**单机 Docker Compose** 部署，控制成本的同时保持架构清晰。

```
┌─────────────────────────────────────────────────────────┐
│                    云服务器（VPS）                        │
│                   2核4G / Ubuntu 22.04                   │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              Docker Compose                        │  │
│  │                                                   │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  │  │
│  │  │   Caddy    │  │  Go API    │  │  Reader    │  │  │
│  │  │  反向代理   │  │  + Worker  │  │  抓取服务   │  │  │
│  │  │  自动HTTPS │  │  Port:8080 │  │  Port:3000 │  │  │
│  │  │  Port:443  │──▶            │──▶            │  │  │
│  │  │            │  │  ·chi      │  │  ·reader   │  │  │
│  │  │            │  │  ·asynq    │  │  ·hero     │  │  │
│  │  │            │  │  ·pgx      │  │  ·浏览器池  │  │  │
│  │  └────────────┘  └─────┬──────┘  └────────────┘  │  │
│  │                        │                          │  │
│  │  ┌────────────┐  ┌─────▼──────┐  ┌────────────┐  │  │
│  │  │ PostgreSQL │  │   Redis    │  │   Python   │  │  │
│  │  │   16       │  │    7       │  │  AI 服务    │  │  │
│  │  │ Port:5432  │  │ Port:6379  │  │  Port:8000 │  │  │
│  │  └────────────┘  └────────────┘  └────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              数据持久化 (Docker Volumes)            │  │
│  │  ·pg_data/    — PostgreSQL 数据                    │  │
│  │  ·redis_data/ — Redis 持久化                       │  │
│  │  ·caddy_data/ — Caddy 证书和配置                   │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
              │
              │ HTTPS
              ▼
┌─────────────────────────────────────────────────────────┐
│              Cloudflare                                   │
│                                                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────┐│
│  │    DNS     │  │    CDN     │  │       R2           ││
│  │  域名解析   │  │  静态加速   │  │  对象存储（图片）   ││
│  │            │  │  DDoS防护  │  │  S3 兼容 API       ││
│  └────────────┘  └────────────┘  └────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 6.2 Docker Compose 配置

```yaml
# docker-compose.yml
version: '3.8'

services:
  caddy:
    image: caddy:2.7-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - api
    restart: unless-stopped

  # Go 主服务（API + Worker 共进程，通过 goroutine 并行）
  api:
    build:
      context: .
      dockerfile: Dockerfile
    environment:
      - DATABASE_URL=postgresql://folio:${DB_PASSWORD}@postgres:5432/folio
      - REDIS_ADDR=redis:6379
      - READER_URL=http://reader:3000
      - AI_SERVICE_URL=http://ai:8000
      - R2_ENDPOINT=${R2_ENDPOINT}
      - R2_ACCESS_KEY=${R2_ACCESS_KEY}
      - R2_SECRET_KEY=${R2_SECRET_KEY}
      - JWT_SECRET=${JWT_SECRET}
    depends_on:
      - postgres
      - redis
      - reader
      - ai
    restart: unless-stopped

  # Reader 抓取服务（Node.js 薄包装）
  reader:
    build:
      context: ./reader-service
      dockerfile: Dockerfile
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
      - POOL_SIZE=2
    restart: unless-stopped

  # Python AI 服务
  ai:
    build: ./ai-service
    environment:
      - DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    restart: unless-stopped

  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=folio
      - POSTGRES_USER=folio
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./migrations/001_init.up.sql:/docker-entrypoint-initdb.d/init.sql
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  pg_data:
  redis_data:
  caddy_data:
  caddy_config:
```

**Go 服务 Dockerfile**：

```dockerfile
# Dockerfile — Go 多阶段构建
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /folio-server ./cmd/server

FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /folio-server /folio-server
EXPOSE 8080
CMD ["/folio-server"]
```

### 6.3 云服务选择和成本估算

选择 **Cloudflare + 海外 VPS** 方案的原因：
- Cloudflare R2 免出站流量费，CDN 全球覆盖
- 海外 VPS 方便访问 Twitter/X 等国外内容源
- 通过 Cloudflare CDN 优化国内访问速度

| 服务 | 规格 | 月成本 |
|------|------|--------|
| VPS 云服务器 | 2核4G（Hetzner/DigitalOcean） | ~$12 (¥85) |
| Cloudflare R2 | 10GB 存储（免费额度内） | $0 (¥0) |
| Cloudflare CDN | 免费计划 | $0 (¥0) |
| 域名 | .app 域名 | ~$14/年 (¥8/月) |
| DeepSeek API | 约 30000 篇/月 | ~¥600 |
| Apple Developer | 年费 | $99/年 (¥58/月) |
| **合计** | | **约 ¥750/月** |

**成本说明**：
- MVP 阶段最大开支是 DeepSeek API 调用费用
- DeepSeek Chat 模型性价比极高，成本远低于同类模型
- VPS 选择海外机房（如法兰克福），性价比极高
- Cloudflare R2 10GB 免费存储额度对 MVP 阶段绰绰有余
- Go 编译为单二进制，内存占用远低于 Node.js，2核4G 足以运行全部服务
- Reader 服务的浏览器池（Hero）是内存大户，POOL_SIZE=2 约占 200-400MB

---

## 七、安全设计

### 7.1 认证与授权

```
┌──────────────────────────────────────────────────────────┐
│                    安全架构总览                            │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  认证层                                          │     │
│  │  ·Sign in with Apple（唯一登录方式）              │     │
│  │  ·JWT Access Token（2小时有效）                   │     │
│  │  ·Refresh Token（90天，加密存储在 Keychain）      │     │
│  │  ·Token 黑名单（Redis，用于主动登出）             │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  授权层                                          │     │
│  │  ·资源隔离：用户只能访问自己的 articles/tags      │     │
│  │  ·每个 API 请求校验 user_id                      │     │
│  │  ·配额检查：Free 用户每月 30 篇限制              │     │
│  │  ·功能门控：AI 问答仅 Pro+ 用户可用              │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │  接口安全                                        │     │
│  │  ·全链路 HTTPS（Caddy 自动管理 Let's Encrypt）   │     │
│  │  ·API 限流：                                     │     │
│  │    - 登录接口：5 次/分钟                          │     │
│  │    - 抓取接口：10 次/分钟                         │     │
│  │    - 搜索接口：30 次/分钟                         │     │
│  │    - 通用接口：60 次/分钟                         │     │
│  │  ·CORS 白名单                                    │     │
│  │  ·请求体大小限制：1MB                             │     │
│  └─────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

### 7.2 数据安全

| 安全措施 | 实现方式 |
|---------|---------|
| 传输加密 | TLS 1.3，Caddy 自动 HTTPS |
| 密码哈希 | 不涉及（Sign in with Apple） |
| Token 存储 | iOS Keychain（硬件级加密） |
| 数据库连接 | SSL 加密连接 |
| 敏感配置 | 环境变量，生产环境使用 Docker Secrets |
| 对象存储 | R2 私有桶，通过签名 URL 访问图片 |
| SQL 注入 | pgx 参数化查询，全部使用 $1/$2 占位符 |
| XSS 防护 | Markdown 渲染前过滤危险 HTML |

### 7.3 隐私保护

```
┌──────────────────────────────────────────────────────────┐
│                    隐私保护设计                            │
│                                                          │
│  数据收集最小化原则：                                      │
│  ·仅收集提供服务必需的数据                                 │
│  ·Sign in with Apple 支持"隐藏邮箱"                       │
│  ·不收集设备指纹、位置信息等                               │
│  ·不追踪用户的阅读行为用于广告                             │
│                                                          │
│  用户数据控制：                                            │
│  ·用户可随时删除单篇收藏                                  │
│  ·用户可一键导出所有数据（Markdown 压缩包）                │
│  ·用户可注销账户，30天内物理删除所有数据                    │
│  ·删除操作不可逆，包括 R2 中的图片资源                     │
│                                                          │
│  AI 处理隐私：                                            │
│  ·仅将文章正文发送给 DeepSeek API（不含用户个人信息）       │
│  ·不将用户内容用于模型训练（DeepSeek API 使用条款保障）     │
│  ·AI 处理结果仅用于本用户的分类和摘要                      │
│                                                          │
│  合规要求：                                                │
│  ·App Store 隐私标签如实填写                               │
│  ·提供隐私政策页面（中英双语）                             │
│  ·遵守 Apple App Tracking Transparency 要求               │
└──────────────────────────────────────────────────────────┘
```

---

## 八、可扩展性设计

### 8.1 后续扩展方向预留

| 扩展方向 | 预留设计 | 预计阶段 |
|---------|---------|---------|
| AI 问答 | AI 服务独立进程，可添加新 endpoint；articles 表已有全文内容 | Phase 2 (Pro+) |
| 新内容源后处理 | Go 层 SourceType 识别 + 特殊后处理逻辑，Reader 负责通用抓取 | 持续迭代 |
| Android 客户端 | 后端 API 通用 RESTful，Android 开发只需客户端 | Phase 3 |
| Web 客户端 | API 已支持 CORS，可开发 Web 版 | Phase 3 |
| 智能推荐 | activity_logs 表记录用户行为，可训练推荐模型 | Phase 4 |
| 协作/分享 | 数据模型可扩展共享权限字段 | Phase 4 |
| Newsletter 订阅 | Reader 可扩展邮件 HTML 解析能力 | Phase 2 |
| YouTube 字幕 | Reader 抓取页面 + Go 层提取字幕文本 | Phase 2 |
| 批量导入 | API 支持批量提交 URL，asynq 队列已有批处理能力 | Phase 2 |
| 多模型支持 | AI Pipeline 的模型配置可切换，当前使用 DeepSeek Chat | 持续优化 |

### 8.2 架构演进路径

```
┌─────────────────────────────────────────────────────────────────┐
│                        架构演进路径                               │
│                                                                 │
│  Phase 1 (MVP)                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  单机 Docker Compose                                      │  │
│  │  ·1 台 VPS 跑 Go + Reader + AI + PG + Redis              │  │
│  │  ·Go 编译为单二进制，资源占用极低                           │  │
│  │  ·适用于 0-5000 用户                                      │  │
│  │  ·月成本 < ¥800                                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          │                                      │
│                          ▼                                      │
│  Phase 2 (增长期)                                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  服务拆分 + 数据库分离                                     │  │
│  │  ·Reader 服务独立部署（浏览器池吃内存）                     │  │
│  │  ·PostgreSQL 使用托管数据库                                │  │
│  │  ·Redis 使用托管服务                                      │  │
│  │  ·Go 服务可水平扩展（无状态，asynq 天然支持多 Worker）     │  │
│  │  ·适用于 5000-50000 用户                                  │  │
│  │  ·月成本 ¥2000-5000                                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                          │                                      │
│                          ▼                                      │
│  Phase 3 (规模化)                                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  容器编排 + 自动扩缩                                      │  │
│  │  ·Kubernetes 或 Fly.io 部署                               │  │
│  │  ·Reader 服务水平扩展（根据队列深度自动扩缩）               │  │
│  │  ·Go Worker 独立扩展（与 API 服务分离部署）                │  │
│  │  ·数据库读写分离                                          │  │
│  │  ·适用于 50000+ 用户                                      │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 8.3 内容源后处理扩展

抓取能力由 Reader 统一提供，Go 层通过后处理器接口扩展特定平台的内容处理逻辑：

```go
// internal/service/postprocess.go — 内容后处理扩展接口

// PostProcessor 对 Reader 返回的原始结果做特定平台的后处理
type PostProcessor interface {
	// Supports 判断此处理器是否适用于该 URL
	Supports(url string) bool

	// Process 对抓取结果做后处理（图片转存、格式修正等）
	Process(ctx context.Context, result *CrawlResult) error
}

// CrawlResult 统一的抓取结果
type CrawlResult struct {
	Markdown string
	Title    string
	Author   string
	SiteName string
	CoverURL string
	Language string
}

// 注册后处理器
var postProcessors = []PostProcessor{
	&WechatPostProcessor{},   // 微信防盗链图片处理
	&TwitterPostProcessor{},  // Thread 合并、引用推文
	&WeiboPostProcessor{},    // 短链展开、图片转存
}

// RunPostProcessors 执行匹配的后处理器
func RunPostProcessors(ctx context.Context, url string, result *CrawlResult) error {
	for _, p := range postProcessors {
		if p.Supports(url) {
			if err := p.Process(ctx, result); err != nil {
				slog.Warn("post-processor failed", "url", url, "err", err)
				// 后处理失败不阻塞主流程
			}
		}
	}
	return nil
}

// 示例：微信公众号后处理器
type WechatPostProcessor struct {
	r2 *R2Client
}

func (p *WechatPostProcessor) Supports(url string) bool {
	return strings.Contains(url, "mp.weixin.qq.com")
}

func (p *WechatPostProcessor) Process(ctx context.Context, result *CrawlResult) error {
	// 微信图片域名 mmbiz.qpic.cn 有防盗链
	// 提取所有微信图片 URL，下载后转存到 R2，替换 Markdown 中的链接
	re := regexp.MustCompile(`!\[([^\]]*)\]\((https?://mmbiz\.qpic\.cn[^)]+)\)`)
	matches := re.FindAllStringSubmatch(result.Markdown, -1)
	for _, m := range matches {
		originalURL := m[2]
		newURL, err := p.r2.ProxyUpload(ctx, originalURL, map[string]string{
			"Referer": "https://mp.weixin.qq.com/",
		})
		if err != nil {
			continue
		}
		result.Markdown = strings.Replace(result.Markdown, originalURL, newURL, 1)
	}
	return nil
}
```

---

## 更新记录

- 2026-02-20：创建系统架构设计 1.0（MVP 版本）
- 2026-02-20：更新至 1.1 — 后端改为 Go 语言，集成 @vakra-dev/reader 作为抓取引擎，Node.js 抓取服务改为 Reader HTTP 包装层
