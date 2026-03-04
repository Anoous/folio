# Folio 系统架构文档

> 版本：1.0 | 更新日期：2026-03-03

---

## 目录

1. [系统概述](#1-系统概述)
2. [整体架构](#2-整体架构)
3. [iOS 客户端架构](#3-ios-客户端架构)
4. [Go 后端架构](#4-go-后端架构)
5. [Reader 服务](#5-reader-服务)
6. [AI 服务](#6-ai-服务)
7. [数据库设计](#7-数据库设计)
8. [基础设施与部署](#8-基础设施与部署)
9. [核心数据流](#9-核心数据流)
10. [安全设计](#10-安全设计)
11. [性能与可靠性](#11-性能与可靠性)
12. [测试策略](#12-测试策略)
13. [技术债与演进路径](#13-技术债与演进路径)

---

## 1. 系统概述

### 1.1 产品定位

Folio（页集）是一款本地优先（Local-First）的个人知识收藏 iOS 应用。核心价值主张：

- **零配置收藏**：从任意 App 分享链接，一键保存
- **智能整理**：AI 自动分类、打标签、生成摘要
- **本地存储**：内容存在设备上，全文检索，无需联网阅读
- **隐私优先**：用户内容不离开设备（仅 AI 分析时上传内容）

### 1.2 核心流程

```
收藏 → 整理 → 发现
(Collect → Organize → Find)
```

### 1.3 技术规格

| 维度 | 规格 |
|------|------|
| iOS 最低版本 | iOS 17.0 |
| Swift 版本 | 5.9+ |
| Xcode 版本 | 16.2 |
| Go 版本 | 1.24+ |
| Node.js | LTS (TypeScript) |
| Python | 3.12+ |
| 数据库 | PostgreSQL 16 |
| 消息队列 | Redis + asynq |

---

## 2. 整体架构

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────┐
│                      iOS 客户端                          │
│                                                         │
│  ┌─────────────┐    ┌──────────────────────────────┐   │
│  │ Share       │    │        Folio 主 App           │   │
│  │ Extension   │    │                              │   │
│  │             │    │  SwiftUI + SwiftData + FTS5   │   │
│  │ URLExtract  │    │  MVVM + Clean Architecture    │   │
│  │ + Save      │    │                              │   │
│  └──────┬──────┘    └──────────────┬───────────────┘   │
│         │           App Group       │                    │
│         └──── SharedDataManager ───┘                    │
└─────────────────────┬───────────────────────────────────┘
                      │ HTTPS
                      ▼
┌─────────────────────────────────────────────────────────┐
│                   Caddy 反向代理                          │
│              (TLS 终止 + 路由转发)                       │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│                 Go API 服务 (:8080)                      │
│                                                         │
│  chi Router → Middleware → Handler → Service → Repo     │
│                                │                        │
│                    asynq Task Queue                     │
│                    ┌───────────┴──────────────┐         │
│                    │         │                │         │
│               Crawl Task  AI Task     Image Task        │
└────────┬───────────┼──────────┼────────────────────────-┘
         │           │          │
         ▼           ▼          ▼
    ┌─────────┐ ┌─────────┐ ┌──────────────┐
    │  Redis  │ │Reader   │ │  AI Service  │
    │ (:6379) │ │Service  │ │  (:8000)     │
    │ (Queue) │ │ (:3000) │ │  Python/     │
    └─────────┘ │ Node.js │ │  FastAPI     │
                └─────────┘ └──────┬───────┘
         ┌──────────────────────────┘
         ▼
    ┌─────────┐
    │PostgreSQL│
    │  (:5432) │
    └─────────┘
```

### 2.2 四层服务架构

| 层级 | 职责 | 技术栈 |
|------|------|--------|
| iOS 客户端 | 用户界面、本地存储、离线优先 | Swift 5.9 / SwiftUI / SwiftData / SQLite FTS5 |
| Go API 服务 | 认证、业务逻辑、任务调度 | Go 1.24 / chi / asynq / pgx v5 |
| Reader 服务 | 网页抓取、内容提取、转 Markdown | Node.js / TypeScript / Express / @vakra-dev/reader |
| AI 服务 | 内容分类、标签生成、摘要提取 | Python 3.12 / FastAPI / DeepSeek API |

### 2.3 服务间通信协议

- **iOS ↔ Go API**：HTTPS REST（生产），HTTP（本地开发）
- **Go API ↔ Reader/AI**：HTTP（内网），不经过 Caddy
- **Go API ↔ Redis**：TCP（asynq 任务队列）
- **Go API ↔ PostgreSQL**：pgx v5 连接池（20 连接）
- **iOS 内部**：Swift Concurrency（async/await）+ SwiftData 事件通知

---

## 3. iOS 客户端架构

### 3.1 分层架构

```
┌────────────────────────────────────────────┐
│           Presentation Layer               │
│  HomeView / ReaderView / SearchView        │
│  SettingsView / OnboardingView             │
│  Components (设计系统)                     │
│              ↕ @Observable ViewModels      │
├────────────────────────────────────────────┤
│              Domain Layer                  │
│  Article / Tag / Category / User 模型      │
│  UseCases (业务逻辑抽象)                   │
│              ↕ Repository 协议             │
├────────────────────────────────────────────┤
│               Data Layer                  │
│  SwiftData | Network | Search | KeyChain  │
│  Sync | Repository 实现                   │
└────────────────────────────────────────────┘
```

### 3.2 目录结构

```
ios/Folio/
├── App/                           # 应用入口
│   ├── FolioApp.swift             # @main，容器初始化，生命周期
│   ├── MainTabView.swift          # 根 NavigationStack
│   └── AppDelegate.swift          # UIApplicationDelegateAdaptor
│
├── Domain/
│   ├── Models/
│   │   ├── Article.swift          # 核心模型，27 个属性
│   │   ├── Tag.swift              # 标签模型
│   │   ├── Category.swift         # 分类模型（9 个预置）
│   │   └── Models.swift           # 通用类型
│   └── UseCases/
│       └── UseCases.swift         # 业务逻辑接口
│
├── Data/
│   ├── SwiftData/
│   │   ├── DataManager.swift      # Schema + 分类预载
│   │   └── SharedDataManager.swift # App Group 容器（Share Extension 共享）
│   ├── Network/
│   │   ├── Network.swift          # APIClient + 所有 DTO（23KB）
│   │   ├── DTOMapping.swift       # DTO ↔ 领域模型映射
│   │   └── OfflineQueueManager.swift # 离线队列（NWPathMonitor）
│   ├── Search/
│   │   └── FTS5SearchManager.swift # SQLite FTS5 全文检索
│   ├── Repository/
│   │   ├── ArticleRepository.swift
│   │   ├── TagRepository.swift
│   │   └── CategoryRepository.swift
│   ├── KeyChain/
│   │   └── KeyChainManager.swift  # JWT Token 安全存储
│   └── Sync/
│       ├── SyncService.swift      # 服务端同步
│       └── ArticleMerger.swift    # 冲突合并
│
├── Presentation/
│   ├── Auth/                      # 认证流（Apple Sign-In + Dev）
│   ├── Home/                      # 主列表（文章卡片、分类筛选）
│   ├── Reader/                    # 阅读器（Markdown 渲染）
│   ├── Search/                    # 搜索（FTS5 + 历史记录）
│   ├── Settings/                  # 设置
│   ├── Onboarding/                # 引导页
│   └── Components/                # 设计系统组件
│
└── Utils/
    ├── MockDataFactory.swift
    └── Extensions/

ios/Shared/Extraction/             # App + Extension 共用
├── ContentExtractor.swift         # 提取主流程（8s 超时，100MB 内存限制）
├── HTMLFetcher.swift              # 网络请求 + 重定向
├── ReadabilityExtractor.swift     # DOM 解析、元数据提取
├── HTMLToMarkdownConverter.swift  # HTML → Markdown
└── ExtractionResult.swift         # 结果结构体

ios/ShareExtension/
├── ShareViewController.swift      # UIViewController，提取 URL、触发保存
└── CompactShareView.swift         # SwiftUI 弹窗 UI
```

### 3.3 导航架构

Folio 使用**单一 NavigationStack**，无 TabView：

```
FolioApp
  └── MainTabView（根 NavigationStack）
        ├── 未登录 → OnboardingView → AuthView
        └── 已登录 → HomeView
              ├── 内联 .searchable() → SearchResultsView
              ├── .navigationDestination → ReaderView
              └── toolbar gear → SettingsView
```

**设计选择**：选用 NavigationStack 而非 TabView，使全屏沉浸式阅读和搜索过渡动画更自然，无底部 Tab 干扰。

### 3.4 核心数据模型

#### Article（核心实体）

```swift
@Model class Article {
    // 标识
    var id: UUID
    var serverID: String?
    var url: String

    // 内容
    var title: String
    var author: String?
    var siteName: String?
    var markdownContent: String?
    var summary: String?
    var keyPoints: [String]
    var wordCount: Int
    var language: String?

    // AI 分析
    var category: Category?
    var tags: [Tag]
    var aiConfidence: Double

    // 媒体
    var faviconURL: String?
    var coverImageURL: String?

    // 状态
    var status: ArticleStatus          // pending|processing|ready|failed|clientReady
    var syncState: SyncState           // pendingUpload|synced|pendingUpdate|conflict
    var extractionSource: ExtractionSource  // none|client|server

    // 用户操作
    var isFavorite: Bool
    var isArchived: Bool
    var readProgress: Double           // 0.0 ~ 1.0

    // 时间
    var createdAt: Date
    var updatedAt: Date
    var clientExtractedAt: Date?
    var lastReadAt: Date?
}
```

#### 文章状态机

```
pending ──────────────────────────────────→ clientReady
   │         (客户端提取成功)                    │
   │                                           │
   ▼  (提交至服务端)                            ▼  (提交至服务端)
processing ──────────────────────────────→ processing
   │                                           │
   ▼  (AI 分析完成)                            ▼  (AI 分析完成)
 ready                                       ready

   │  (任意阶段失败)
   ▼
 failed
```

### 3.5 状态管理

采用 **@Observable**（iOS 17 新 API）替代 ObservableObject：

```swift
// FolioApp 顶层持有
@State var authViewModel: AuthViewModel
@State var offlineQueueManager: OfflineQueueManager
@State var syncService: SyncService?

// 各 View 本地持有
@State var homeViewModel: HomeViewModel
@State var readerViewModel: ReaderViewModel
@State var searchViewModel: SearchViewModel
```

**数据流向**：
```
SwiftData ModelContext
    ↓ (@Query 自动响应变化)
ViewModel（@Observable）
    ↓ (属性变更触发 View 更新)
SwiftUI View
    ↓ (用户操作)
ViewModel Method → Repository → ModelContext
```

### 3.6 网络层设计

#### APIClient 架构

```swift
class APIClient {
    static let shared: APIClient

    // 基础 URL：DEBUG → localhost:8080，RELEASE → api.folio.app
    var baseURL: URL

    // Token 管理
    private let keyChainManager: KeyChainManager

    // 核心请求方法
    private func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T

    // 自动 Token 刷新
    private func refreshTokenIfNeeded() async throws
}
```

**错误处理策略**：

| APIError | 处理方式 |
|----------|----------|
| `.unauthorized` | 尝试刷新 Token，失败则跳转登录 |
| `.quotaExceeded` | 显示升级 Pro 弹窗 |
| `.notFound` | 本地删除该条目 |
| `.networkError` | 加入离线队列，网络恢复后重试 |
| `.serverError(5xx)` | Toast 提示，不重试 |

### 3.7 离线优先设计

```
┌───────────────────────────────────────────┐
│              离线优先存储策略              │
│                                           │
│  Share Extension：                        │
│  1. 立即写入 SwiftData（App Group）        │
│  2. 客户端提取内容（8s timeout）           │
│  3. 不依赖网络连接                         │
│                                           │
│  主 App：                                 │
│  1. NWPathMonitor 监听网络状态             │
│  2. 网络可用时，处理 pending 文章          │
│  3. 轮询任务状态（5s 间隔，最多 10 次）    │
│  4. 合并服务端数据到本地模型               │
└───────────────────────────────────────────┘
```

**冲突解决策略**（ArticleMerger）：
- 时间戳冲突：取较新的 `updatedAt`
- 阅读进度冲突：取较大值（max）
- AI 结果：服务端数据优先

### 3.8 全文检索（FTS5）

```sql
-- 虚拟表结构
CREATE VIRTUAL TABLE articles_fts USING fts5(
    article_id UNINDEXED,
    title,
    content,        -- markdown 内容
    summary,
    tags,           -- 逗号分隔
    author,
    site_name,
    language UNINDEXED
);
```

**关键特性**：
- **200ms 防抖**：避免每次按键都触发查询
- **查询清洗**：过滤特殊字符防止 FTS5 语法错误
- **增量索引**：文章更新时同步更新索引
- **启动重建**：App 启动时重建完整索引确保一致性

### 3.9 客户端内容提取管道

```
ContentExtractor.extract(url)
        │
        ├─ 超时检查（8 秒）
        ├─ 内存检查（< 100MB）
        │
        ▼
HTMLFetcher.fetch(url)
  ├─ URLSession（30s 网络超时）
  ├─ 跟随重定向（最多 10 跳）
  └─ 返回 HTML 字符串
        │
        ▼
ReadabilityExtractor.extract(html)
  ├─ SwiftSoup DOM 解析
  ├─ 提取正文、标题、作者、站点名
  ├─ 过滤广告、导航等噪音元素
  └─ 返回清洗后的 HTML
        │
        ▼
HTMLToMarkdownConverter.convert(cleanedHTML)
  ├─ 标签映射（h1-h6, p, ul, ol, img, code 等）
  ├─ 保留代码块语言标注
  └─ 返回 Markdown 字符串
        │
        ▼
ExtractionResult { markdown, title, author, siteName, wordCount }
```

**不支持客户端提取的来源**（需服务端处理）：
- YouTube（需 oEmbed API）
- 付费墙内容

### 3.10 Share Extension 配额管理

```swift
// 存储在 UserDefaults（App Group 共享）
let quotaKey = "folio.quota.\(yearMonth)"   // e.g., "folio.quota.2026-03"
let planKey  = "folio.subscription.plan"    // free|pro|pro+

// 规则
- free:   每月 30 次
- pro:    无限制
- pro+:   无限制

// 超过 90% → 显示配额警告
// 超过 100% → 拒绝保存，显示升级提示
```

---

## 4. Go 后端架构

### 4.1 包结构

```
server/
├── cmd/server/
│   └── main.go              # 依赖注入，服务启动（API + Worker 同进程）
│
└── internal/
    ├── api/
    │   ├── router.go         # chi v5 路由定义
    │   ├── handler/          # HTTP 处理器（薄层，只做 IO）
    │   └── middleware/       # JWT 认证中间件
    │
    ├── service/              # 业务逻辑层
    │   ├── interfaces.go     # 依赖接口定义
    │   ├── errors.go         # 业务错误类型
    │   ├── auth.go           # Apple Sign-In + JWT
    │   ├── article.go        # 文章提交逻辑
    │   ├── quota.go          # 配额管理
    │   ├── tag.go            # 标签管理
    │   └── source.go         # URL 来源检测
    │
    ├── repository/           # 数据访问层（pgx v5）
    │   ├── db.go             # 连接池初始化
    │   ├── user.go
    │   ├── article.go
    │   ├── tag.go
    │   ├── category.go
    │   └── task.go
    │
    ├── worker/               # 异步任务处理（asynq）
    │   ├── server.go         # WorkerServer + Mux 注册
    │   ├── tasks.go          # 任务类型定义
    │   ├── crawl_handler.go  # 抓取任务处理
    │   ├── ai_handler.go     # AI 分析任务处理
    │   └── image_handler.go  # 图片托管任务
    │
    ├── client/               # 外部服务客户端
    │   ├── reader.go         # Reader 服务 HTTP 客户端
    │   ├── ai.go             # AI 服务 HTTP 客户端
    │   └── r2.go             # Cloudflare R2（图片托管）
    │
    ├── domain/               # 领域模型（纯数据结构）
    │   ├── user.go
    │   ├── article.go
    │   ├── tag.go
    │   ├── category.go
    │   └── task.go
    │
    └── config/
        └── config.go         # 环境变量加载与校验
```

### 4.2 请求处理分层

```
HTTP Request
     │
     ▼
chi Router（路由分发）
     │
     ▼
Middleware（JWT 验证 → userID 注入 Context）
     │
     ▼
Handler（解析请求 → 调用 Service → 序列化响应）
  * 只处理 HTTP 协议逻辑
  * 不含业务规则
     │
     ▼
Service（业务逻辑 + 错误映射）
  * 配额检查
  * 重复 URL 检查
  * 任务编排
     │
     ▼
Repository（数据库操作）
  * 参数化 SQL
  * 连接池复用
     │
     ▼
PostgreSQL
```

### 4.3 API 路由表

```
公开路由（无需认证）：
GET  /health
POST /api/v1/auth/apple          # Apple Sign-In
POST /api/v1/auth/refresh        # Token 刷新
POST /api/v1/auth/dev            # 开发登录（DEV_MODE=true）

受保护路由（需 Bearer Token）：
GET  /api/v1/articles/search?q=  # 全文搜索
POST /api/v1/articles            # 提交 URL
GET  /api/v1/articles            # 分页列表（可按分类/状态/收藏筛选）
GET  /api/v1/articles/{id}       # 文章详情
PUT  /api/v1/articles/{id}       # 更新（收藏、归档、阅读进度）
DEL  /api/v1/articles/{id}       # 删除

GET  /api/v1/tags                # 标签列表
POST /api/v1/tags                # 创建标签
DEL  /api/v1/tags/{id}          # 删除标签

GET  /api/v1/categories          # 分类列表

GET  /api/v1/tasks/{id}          # 轮询任务状态

POST /api/v1/subscription/verify # 验证订阅
```

### 4.4 异步任务架构

```
asynq（Redis backed）
├── critical 队列（文章抓取，最高优先级）
│   └── article:crawl
│       ├── 重试次数：3
│       ├── 超时：90 秒
│       └── 处理器：CrawlHandler
│
├── default 队列（AI 分析）
│   └── article:ai
│       ├── 重试次数：3
│       ├── 超时：60 秒
│       └── 处理器：AIHandler
│
└── low 队列（图片托管，可选）
    └── article:images
        ├── 重试次数：2
        ├── 超时：5 分钟
        └── 处理器：ImageHandler
```

**处理器逻辑（CrawlHandler）**：

```
1. 从 asynq 取出任务 payload（articleID, url, userID, sourceType）
2. 调用 ReaderClient.Scrape(url)（60s 超时）
3a. 成功：存储 markdown_content, title, author, favicon
    → 更新 article.status = "processing"
    → 入队 article:ai 任务
3b. 失败：检查是否有客户端提取的内容
    - 有：使用客户端内容，入队 article:ai
    - 无：更新 article.status = "failed"，记录错误
4. 更新 crawl_task 状态
```

**处理器逻辑（AIHandler）**：

```
1. 取出任务 payload（articleID, userID）
2. 读取 article（title, markdown_content, source_type, author）
3. 调用 AIClient.Analyze()（30s 超时）
4. 获得响应：category_slug, confidence, tags[], summary, key_points[], language
5. 查找 category_id（按 slug）
6. 为每个 tag 执行 UPSERT，关联到 article
7. 更新 article：category_id, summary, key_points, ai_confidence, language
8. article.status → "ready"
9. crawl_task.status → "done"
```

### 4.5 认证设计

#### Apple Sign-In 流程

```
iOS 端                              Go 服务端
  │                                    │
  │── ASAuthorizationAppleIDRequest ──→│
  │                                    │
  │←── identityToken (JWT) ────────────│
  │                                    │
  │── POST /auth/apple ──────────────→ │
  │   { identityToken }                │ 1. 获取 Apple JWKS（带缓存+mutex）
  │                                    │ 2. 验证 JWT 签名
  │                                    │ 3. 提取 apple_sub, email
  │                                    │ 4. Upsert user 记录
  │                                    │ 5. 生成 accessToken(15min) + refreshToken(7d)
  │←── { accessToken, refreshToken } ──│
  │                                    │
  │   存入 KeyChain                    │
```

#### JWT Token 策略

| Token | 有效期 | 用途 |
|-------|--------|------|
| accessToken | 15 分钟 | API 请求认证 |
| refreshToken | 7 天 | 刷新 accessToken |

**自动刷新**：iOS 端 APIClient 在收到 401 时，自动调用 `/auth/refresh`，成功后重试原请求。

### 4.6 来源检测

```go
// service/source.go
func DetectSource(rawURL string) SourceType {
    // 规则：URL host 匹配
    mp.weixin.com     → wechat
    x.com / twitter   → twitter
    weibo.com         → weibo
    zhihu.com         → zhihu
    youtube.com       → youtube
    substack.com 等   → newsletter
    其他               → web
}
```

---

## 5. Reader 服务

### 5.1 概述

Reader 服务是一个独立的 Node.js/TypeScript 微服务，职责是：
- 接受 URL，抓取网页内容
- 提取正文（过滤广告、导航等噪音）
- 转换为 Markdown 格式
- 返回结构化元数据

### 5.2 技术实现

```typescript
// server/reader-service/src/index.ts
Express + TypeScript

POST /scrape
  Input:  { url: string, timeout_ms?: number }
  Output: {
    markdown: string,
    metadata: {
      title, description, author, siteName,
      favicon, ogImage, language, canonical
    },
    duration_ms: number
  }

GET /health → { status: "ok" }
```

**核心依赖**：`@vakra-dev/reader`（本地 npm 包，路径：`/Users/mac/github/reader`）

**抓取配置**：
```typescript
reader.scrape({
    formats: ["markdown"],
    onlyMainContent: true,   // 只提取正文
    removeAds: true,         // 过滤广告
    timeoutMs: 30000,        // 30 秒超时
    maxRetries: 2,           // 失败重试 2 次
})
```

### 5.3 错误处理

| HTTP 状态码 | 含义 |
|-------------|------|
| 200 | 成功提取 |
| 400 | 请求缺少 url 参数 |
| 422 | 无法提取内容（反爬、付费墙等） |
| 500 | 服务内部错误 |

**降级策略**：Reader 失败时，Go 后端 CrawlHandler 会检查是否有 iOS 客户端预先提取的内容，若有则使用客户端内容继续 AI 分析流程。

---

## 6. AI 服务

### 6.1 概述

AI 服务是一个独立的 Python/FastAPI 微服务，基于 DeepSeek Chat 模型，一次调用同时完成：
- 内容分类（9 个类别）
- 标签生成（3-5 个）
- 摘要生成
- 关键点提取（3-5 条）
- 语言检测

### 6.2 API 接口

```python
POST /api/analyze
  Request: {
    title: str,
    content: str,       # Markdown 正文
    source: str,        # 来源类型（web/wechat/twitter 等）
    author: str
  }
  Response: {
    category: str,           # 类别 slug（tech/business/…）
    category_name: str,      # 显示名称
    confidence: float,       # 置信度 0.0-1.0
    tags: list[str],         # 3-5 个标签
    summary: str,            # 摘要
    key_points: list[str],   # 3-5 个关键点
    language: str            # "zh" 或 "en"
  }

GET /health → { status: "ok" }
```

### 6.3 处理管道

```python
# server/ai-service/app/pipeline.py

MODEL = "deepseek-chat"
TEMPERATURE = 0.3      # 低温度保证结构化输出稳定
MAX_TOKENS = 1024

analyze_article(request):
    1. 构造 Prompt（包含文章内容 + 分类指令）
    2. 调用 DeepSeek API（JSON 格式响应）
    3. _validate_response():
       - category 不在 9 个有效 slug 中 → 降级为 "other"，降低 confidence
       - confidence 钳制到 [0.0, 1.0]
       - tags 非列表 → 默认 ["untagged"]
       - key_points 非列表 → 默认 ["N/A"]
       - language 非 zh/en → 默认 "en"
    4. 返回 AnalyzeResponse
```

### 6.4 9 个内容分类

| slug | 中文名 | 英文名 |
|------|--------|--------|
| tech | 技术 | Technology |
| business | 商业 | Business |
| science | 科学 | Science |
| culture | 文化 | Culture |
| lifestyle | 生活 | Lifestyle |
| news | 新闻 | News |
| education | 教育 | Education |
| design | 设计 | Design |
| other | 其他 | Other |

---

## 7. 数据库设计

### 7.1 表结构总览

```
users ──────────────────────────────────────────────────────────┐
  id (PK)                                                        │
  apple_id (UNIQUE)                                             │
  subscription (free|pro|pro+)                                  │
  monthly_quota / current_month_count                           │
                                                                │
categories ─────────────────────────────────────────────────┐   │
  id (PK)                                                    │   │
  slug (UNIQUE)                                              │   │
  name_zh, name_en, icon, sort_order                        │   │
                                                             │   │
articles ──────────────────────────────────────────────┐    │   │
  id (PK)                                               │    │   │
  user_id (FK → users)  ──────────────────────────────────────┘ │
  url (TEXT)                  UNIQUE(user_id, url)         │    │ │
  status (pending|processing|ready|failed)                │    │ │
  source_type (web|wechat|twitter|weibo|zhihu|…)          │    │ │
  markdown_content, summary, key_points (JSONB)           │    │ │
  category_id (FK → categories)  ───────────────────────────────┘ │
  ai_confidence (DECIMAL 3,2)                             │      │
  is_favorite, is_archived                                │      │
  read_progress (DECIMAL 3,2)                             │      │
  word_count, language                                    │      │
  created_at, updated_at                                  │      │
                                                          │      │
tags ──────────────────────────────────────────────────┐  │      │
  id (PK)                                               │  │      │
  user_id (FK → users)  ──────────────────────────────────────────┘
  name (VARCHAR 50)            UNIQUE(user_id, name)   │  │
  is_ai_generated (BOOLEAN)                            │  │
  article_count                                        │  │
                                                        │  │
article_tags ──────────────────────────────────────────│──│──┐
  article_id (FK → articles)  ──────────────────────────┘  │  │
  tag_id (FK → tags)  ──────────────────────────────────────┘  │
  PK(article_id, tag_id)                                        │
                                                                │
crawl_tasks ─────────────────────────────────────────────────┐ │
  id (PK)                                                     │ │
  article_id (FK → articles)  ────────────────────────────────│─┘
  user_id (FK → users)                                        │
  status (queued|running|done|failed)                         │
  crawl/ai started_at/finished_at                             │
```

### 7.2 关键索引设计

```sql
-- 查询优化
CREATE INDEX idx_articles_user_id ON articles(user_id);
CREATE INDEX idx_articles_status ON articles(status);
CREATE INDEX idx_articles_category ON articles(category_id);
CREATE INDEX idx_articles_created_at ON articles(created_at DESC);

-- 收藏列表（部分索引，只索引收藏的文章）
CREATE INDEX idx_articles_is_favorite ON articles(user_id, created_at DESC)
    WHERE is_favorite = TRUE;

-- 唯一约束（防重复）
CREATE UNIQUE INDEX idx_articles_user_url ON articles(user_id, url);

-- 全文搜索（pg_trgm）
CREATE INDEX idx_articles_title_trgm ON articles
    USING gin(title gin_trgm_ops);
```

### 7.3 数据库扩展

| 扩展 | 用途 |
|------|------|
| uuid-ossp | UUID 主键生成 |
| pg_trgm | 服务端 Trigram 全文搜索 |

### 7.4 自动更新触发器

```sql
CREATE TRIGGER update_updated_at
BEFORE UPDATE ON articles
FOR EACH ROW EXECUTE PROCEDURE update_updated_at();
-- 同样作用于 users, crawl_tasks
```

---

## 8. 基础设施与部署

### 8.1 生产环境（docker-compose.yml）

```yaml
服务拓扑：
caddy          → 80/443，TLS 终止，反向代理
api            → :8080，Go 服务（HTTP + Worker 同进程）
reader         → :3000，Node.js 内容提取
ai             → :8000，Python AI 分析
postgres:16    → :5432，主数据库
redis:7        → :6379，任务队列 + 缓存

资源限制（Redis）：
  maxmemory: 256mb
  policy: allkeys-lru
```

### 8.2 开发环境（docker-compose.dev.yml）

```yaml
# 仅启动基础设施，业务服务本地运行
postgres:16 → :5432  (user: folio, password: folio)
redis:7     → :6380  ← 注意：映射到宿主机 6380，非标准端口
```

### 8.3 测试环境（docker-compose.test.yml）

```yaml
# 完全隔离的端口，E2E 测试专用
postgres:16 → :15432
redis:7     → :16379
api         → :18080
reader      → :13000
ai          → :18000
```

### 8.4 环境变量

```bash
# 必填
DATABASE_URL=postgresql://folio:folio@localhost:5432/folio
JWT_SECRET=<32+ 字符随机串>

# 选填（有默认值）
PORT=8080
REDIS_ADDR=localhost:6379
READER_URL=http://localhost:3000
AI_SERVICE_URL=http://localhost:8000
DEV_MODE=false

# 可选（R2 图片托管）
R2_ENDPOINT=
R2_ACCESS_KEY=
R2_SECRET_KEY=
R2_BUCKET_NAME=folio-images
R2_PUBLIC_URL=
```

### 8.5 iOS 构建配置

| 配置项 | DEBUG | RELEASE |
|--------|-------|---------|
| API Base URL | http://localhost:8080 | https://api.folio.app |
| Dev Login 按钮 | 显示 | 隐藏 |
| 日志级别 | 详细 | 错误 |

---

## 9. 核心数据流

### 9.1 Share Extension 保存流程

```
用户在微信/Safari 点击分享
         │
         ▼
ShareViewController.processInput()
  ├─ 从 NSItemProvider 提取 URL
  └─ 检查是否为有效 URL
         │
         ▼
SharedDataManager.saveArticle(url)
  ├─ 检查本地重复（SwiftData 查询）
  ├─ 检查月度配额（UserDefaults）
  ├─ 创建 Article（status: pending）
  └─ 写入 App Group ModelContext
         │
         ▼（如果来源支持客户端提取）
ContentExtractor.extract(url)  [8s 超时]
  ├─ HTMLFetcher.fetch()
  ├─ ReadabilityExtractor.extract()
  └─ HTMLToMarkdownConverter.convert()
         │
         ▼（成功）
SharedDataManager.updateWithExtraction()
  └─ Article status → clientReady
         │
         ▼
UI 反馈：已保存 ✓（已提取内容）
```

### 9.2 文章处理全流程

```
iOS 主 App 检测到 pending/clientReady 文章
         │
         ▼
SyncService.submitPendingArticles()
  └─ APIClient.submitArticle(url, title?, markdown?)
         │
         ▼
Go API: POST /api/v1/articles
  1. CheckDuplicate(user_id, url)
  2. QuotaService.CheckAndIncrement(user_id)
  3. ArticleRepo.Create(article{status: pending})
  4. TaskRepo.Create(crawl_task)
  5. asynq.Enqueue("article:crawl", payload)
  6. Return { articleId, taskId }
         │
         ▼（异步）
Worker: article:crawl
  └─ ReaderClient.Scrape(url)
       ├─ 成功: 存储 markdown, 入队 article:ai
       └─ 失败: 使用客户端内容（如有），入队 article:ai
            └─ 无内容: article.status = failed
         │
         ▼（异步）
Worker: article:ai
  └─ AIClient.Analyze(title, markdown, source, author)
       ├─ Upsert tags（3-5 个）
       ├─ 关联 category
       ├─ 更新 article（summary, key_points, confidence）
       └─ article.status = ready
         │
         ▼（iOS 轮询）
SyncService.pollTask(taskId)
  └─ GET /api/v1/tasks/{taskId}（每 5s，最多 10 次）
       └─ task.status = done
            └─ 获取 ArticleDTO，合并到本地 SwiftData
```

### 9.3 搜索流程

```
用户输入搜索词
         │
         ▼
SearchViewModel（200ms debounce）
         │
         ▼
FTS5SearchManager.search(sanitizedQuery)
  ├─ SQLite 虚拟表查询
  ├─ 搜索字段：title, content, summary, tags, author, site_name
  └─ 返回 [(articleID, rank)]
         │
         ▼
ArticleRepository.fetchByIDs(ids)
         │
         ▼
SearchResultRow 渲染（含关键词高亮）

* 全程本地，无网络请求
```

---

## 10. 安全设计

### 10.1 认证与授权

- **Apple Sign-In**：无密码，依赖 Apple 身份验证
- **JWT 短期令牌**：accessToken 15 分钟过期，减小泄露风险
- **JWKS 缓存**：Apple 公钥本地缓存，减少外部依赖，防止苹果 JWKS 端点不可用
- **Token 安全存储**：iOS 端使用 KeychainAccess 存储，非 UserDefaults

### 10.2 数据隔离

- 所有 API 接口强制携带 `userID`（来自 JWT Context）
- 数据库查询均带 `user_id = ?` 过滤条件
- 文章唯一约束 `(user_id, url)` 防跨用户污染

### 10.3 配额防护

```
Free 用户：30 次/月
- 服务端 QuotaService.CheckAndIncrement()（原子操作）
- 客户端 UserDefaults 本地计数（快速拒绝，Share Extension）
```

### 10.4 内容安全

- 图片 URL：可选通过 R2 再托管，防止直链外露用户行为
- 微信特殊处理：代理抓取 + 防外链图片再托管
- 不存储原始密码，不存储 Apple 完整 Token

---

## 11. 性能与可靠性

### 11.1 iOS 性能优化

| 场景 | 优化手段 |
|------|----------|
| 大量文章列表 | SwiftData lazy loading + 分页（每页 20 条） |
| 搜索响应 | FTS5 索引 + 200ms debounce |
| 图片加载 | Nuke 框架：磁盘缓存 + 内存缓存 + 渐进加载 |
| Share Extension 内存 | 120MB 内存限制；提取前检查内存 |
| 网络请求 | URLSession + NWPathMonitor（仅联网时发请求） |

### 11.2 后端性能优化

| 场景 | 优化手段 |
|------|----------|
| 数据库连接 | pgx v5 连接池（Min: 2, Max: 20） |
| 任务执行 | asynq 3 队列优先级分级（critical > default > low） |
| 搜索 | pg_trgm GIN 索引（比 LIKE 快 10-100 倍） |
| 并发 | Go goroutine + context 超时控制 |

### 11.3 容错设计

| 失败点 | 降级策略 |
|--------|----------|
| Reader 服务不可用 | 使用客户端提取内容继续 AI 分析 |
| AI 服务不可用 | 任务重试 3 次；最终标记 failed |
| 网络断开（iOS） | 离线队列，恢复后自动重试 |
| Apple JWKS 不可用 | 本地缓存（mutex 保护） |
| 服务端 5xx | iOS 客户端 Toast 提示，文章仍保存本地 |

### 11.4 任务重试策略

```
article:crawl（critical 队列）
  重试间隔：指数退避（asynq 默认）
  最大重试：3 次
  超时：90 秒

article:ai（default 队列）
  重试间隔：指数退避
  最大重试：3 次
  超时：60 秒
```

---

## 12. 测试策略

### 12.1 iOS 单元测试（35 个文件）

```
FolioTests/
├── ViewModels/     HomeViewModel / ReaderViewModel / SearchViewModel 逻辑
├── Repository/     Article / Tag / Category 数据访问
├── Network/        APIClient / DTOMapping / OfflineQueueManager
├── Search/         FTS5 索引与查询
├── Data/           DataManager / SharedDataManager / SyncService
├── Extraction/     ContentExtractor / HTMLFetcher / Converter
├── Models/         Article 状态机
├── DesignSystem/   Color / Spacing / Typography
├── Components/     UI 组件快照
├── Extensions/     Date 格式化
└── Utils/          Mock 数据工厂
```

**运行命令**：
```bash
xcodebuild test \
  -project ios/Folio.xcodeproj \
  -scheme Folio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### 12.2 Go 单元测试（5 个文件）

覆盖 Handler、Service、Worker 核心逻辑。

### 12.3 E2E 测试（Python pytest，14 个文件）

```bash
cd server && ./scripts/run_e2e.sh
```

使用完全隔离的 docker-compose.test.yml（独立端口），覆盖：
- 认证流（Apple Sign-In，Dev Login）
- 文章 CRUD + 处理流水线
- 搜索接口
- 标签管理
- 配额逻辑
- 订阅验证

### 12.4 本地开发烟测

```bash
cd server && ./scripts/smoke_api_e2e.sh
```

快速验证 API 基本可用（健康检查 + 核心接口）。

---

## 13. 技术债与演进路径

### 13.1 现存技术债

| 问题 | 影响 | 建议 |
|------|------|------|
| APIClient 是 23KB 单文件 | 可维护性差 | 按业务拆分（AuthAPI, ArticleAPI 等） |
| Reader 服务依赖本地 npm 包 | 部署耦合 | 发布到 npm registry 或内部 registry |
| AI 服务无响应缓存 | 重复内容浪费 API 调用 | 按 URL hash 缓存 24h |
| 服务端搜索基于 pg_trgm | 中文分词效果一般 | 引入 Elasticsearch 或 pg_jieba |
| Worker 与 API 同进程 | 扩容困难 | 分离为独立进程/容器 |
| 无 OpenAPI/Swagger 文档 | 前后端对齐成本高 | 生成并维护 API 规范 |

### 13.2 中期演进方向

1. **搜索增强**：向量嵌入（Embedding）+ 语义搜索
2. **内容处理**：多模态内容（视频转录、图片 OCR）
3. **订阅系统**：App Store 订阅 IAP 完整实现
4. **跨设备同步**：iCloud 同步层（CloudKit）
5. **Web 端**：浏览器插件 + Web Viewer

### 13.3 扩展性考量

当 DAU 超过 10K 时，建议：
- 将 Worker 拆分为独立服务，独立扩容
- 引入 CDN 缓存 Reader 服务结果（按 URL 缓存）
- PostgreSQL 读副本分离 OLAP 查询
- Redis Cluster 替换单节点

---

*本文档基于 2026-03-03 代码库状态撰写，源代码为最终参考依据。*
