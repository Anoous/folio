# Folio（页集）— 抓取管道优化与分布式扩展方案

> 版本：1.2
> 创建日期：2026-02-22
> 最后更新：2026-02-22
> 关联文档：[系统架构](system-design.md) | [API 契约](api-contract.md) | [PRD](../design/prd.md)

---

## 一、背景与目标

### 1.1 现状

MVP 版本的抓取流程完全依赖服务端：用户分享 URL → 服务端 Reader 服务下载 HTML 并提取正文 → AI 分析。这带来两类问题：

**架构瓶颈**：

| 指标 | 当前值 | 瓶颈原因 |
|------|--------|---------|
| 抓取并发 | 6 任务 | Worker 池硬编码 `Concurrency: 10`，Critical 队列权重 6 |
| Reader 吞吐 | ~3-5 req/s | 单进程 Node.js，DOM 解析阻塞事件循环 |
| HTTP 连接复用 | 2/host | Go `http.Client` 未配置 `Transport`，默认 `MaxIdleConnsPerHost=2` |
| DB 连接上限 | 20 | 硬编码 `MaxConns=20`，多实例部署会打爆 PG |
| Redis 内存 | 256MB | `allkeys-lru` 策略会丢弃未处理的任务 |
| 1000 任务消化时间 | 3-8 小时 | 上述瓶颈叠加 |

**业务痛点**：

| 问题 | 影响 |
|------|------|
| 服务端 IP 被反爬 | 微信公众号、部分博客无法抓取 |
| 内容抓取延迟 | 用户分享后需等 30-90 秒才能阅读 |
| Reader 服务是扩展瓶颈 | 单实例上限 3-5 req/s，水平扩展成本高 |
| 微信文章特殊处理 | 防盗链、Cookie 校验，服务端难以绕过 |

### 1.2 核心洞察

抓取瓶颈的根本解法不是扩展 Reader 服务，而是 **将抓取下沉到客户端**：

- 用户的设备天然拥有分散的 IP，不存在反爬问题
- 用户在微信/浏览器中分享文章时，设备上就有完整的页面上下文
- Pocket、Instapaper、Safari Reading List 都采用客户端抓取，是已被验证的行业标准
- 服务端只需做 AI 分析，计算量降一个数量级

### 1.3 目标

| 目标 | 指标 |
|------|------|
| 内容即刻可读 | 分享后 2-5 秒本地可阅读 |
| 服务端零抓取（常规场景） | 90%+ 文章由客户端完成抓取 |
| 分布式部署 | 跨机器部署，无进程内状态依赖 |
| AI 处理吞吐 | 30-50 篇/秒（服务端只剩 AI） |

---

## 二、客户端抓取方案（Phase 1 — 最高优先级）

### 2.1 设计原则

- **Share Extension 不变** — 保持 < 2 秒完成，只存 URL（120MB 内存限制不可冒险）
- **主 App 负责抓取** — 内存上限 ~1GB+，不受 Extension 生命周期限制
- **服务端 Reader 降级为兜底** — 客户端失败时由服务端补抓
- **App Store 合规** — 仅处理用户主动分享的 URL，使用公开 API（URLSession），与 Pocket/Instapaper 模式一致

### 2.2 App Store 合规性分析

| 审核条款 | 内容 | Folio 是否合规 |
|---------|------|---------------|
| **4.5.1** | 禁止抓取 Apple 自有网站 | 合规 — 只处理用户分享的第三方 URL |
| **5.2.3** | 禁止下载第三方音视频 | 合规 — 仅处理文本/文章 |
| **2.5.1** | 只能使用公开 API | 合规 — URLSession 是公开 API |
| **2.5.4** | 后台服务限指定用途 | 合规 — BGTaskScheduler 的 task completion 是批准的用途 |
| **4.2.2** | 不能是纯内容聚合器 | 合规 — 有 AI 分类、全文搜索、原生阅读器等实质功能 |
| **5.1.1(vii)** | SafariViewController 不可隐藏 | 合规 — 方案使用 URLSession，不涉及任何 WebView |
| **5.2.2** | 需遵守第三方服务条款 | 合规 — 用户主动分享，与 Pocket/Instapaper 模式相同 |

**行业先例**：Pocket（15 年+上架）、Instapaper（16 年+上架）、Readwise Reader、GoodLinks 均采用客户端抓取模式。Safari Reading List 是 Apple 自己的同类功能。

### 2.3 架构设计

```
┌──────────────────────────────────────────────────────────┐
│                     Share Extension                       │
│  收到 URL → 存 SwiftData → 1.5s 关闭（保持不变）            │
└───────────────────────┬──────────────────────────────────┘
                        │ App Group 共享数据
                        ▼
┌──────────────────────────────────────────────────────────┐
│                       Main App                            │
│                                                          │
│  OfflineQueueManager 检测到 pending 文章                    │
│       │                                                  │
│       ▼                                                  │
│  ┌────────────────────────────────────────────┐          │
│  │ ClientScraper（新组件，~200 行 Swift）        │          │
│  │                                            │          │
│  │ 1. URLSession 下载 HTML（用户 IP + Cookie）  │          │
│  │ 2. 提取元数据（OG tags / meta / title）      │          │
│  │ 3. 正文提取（移除 nav/footer/ads/script）    │          │
│  │ 4. HTML → Markdown 转换                     │          │
│  │ 5. 存入 SwiftData → 立刻可读                 │          │
│  └─────────────────────┬──────────────────────┘          │
│                        │                                  │
│                        ▼                                  │
│  ┌────────────────────────────────────────────┐          │
│  │ SyncService                                 │          │
│  │                                            │          │
│  │ POST /api/v1/articles                       │          │
│  │ { url, content: { title, markdown, ... } }  │          │
│  │                                            │          │
│  │ 服务端检测到 content 已有：                     │          │
│  │   → 跳过 Reader 服务                         │          │
│  │   → 直接进入 AI 分析                          │          │
│  └────────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────────┘
```

### 2.4 客户端实现

#### 技术选型

| 方案 | 内存 | 质量 | 复杂度 | 推荐 |
|------|------|------|--------|------|
| **A. URLSession + SwiftSoup** | ~15MB | 中 | 低 | 主力方案 |
| B. WKWebView + JS 注入 | ~60MB | 高 | 中 | 备选（SPA 页面） |
| **C. Safari 页面数据直传** | ~0MB | 最高 | 最低 | 快速通道 |

**推荐组合：A 为主 + C 作为快速通道**。不使用 WKWebView，审核风险最低。

#### 方案 A — URLSession + SwiftSoup（主力）

新增 `ios/Folio/Data/Scraper/ClientScraper.swift`：

```swift
import Foundation

struct ScrapeResult {
    let title: String?
    let author: String?
    let siteName: String?
    let favicon: String?
    let ogImage: String?
    let language: String?
    let markdown: String
}

class ClientScraper {

    func scrape(url: String) async throws -> ScrapeResult {
        guard let requestURL = URL(string: url) else {
            throw ScrapeError.invalidURL
        }

        // 1. 下载 HTML（用户 IP，自动携带系统 Cookie）
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data, encoding: .utf8)
                   ?? String(data: data, encoding: .ascii) ?? ""

        // 2. 解析 HTML，提取元数据
        let doc = try SwiftSoup.parse(html)
        let metadata = extractMetadata(doc)

        // 3. 提取正文（移除非内容元素）
        try doc.select("nav, header, footer, script, style, noscript").remove()
        try doc.select(".sidebar, .comment, .ad, .social-share, #comments").remove()

        let article = try doc.select("article").first()
                      ?? doc.select("[role=main]").first()
                      ?? doc.body()

        // 4. HTML → Markdown
        let markdown = try convertToMarkdown(article)

        return ScrapeResult(
            title: metadata.title,
            author: metadata.author,
            siteName: metadata.siteName,
            favicon: metadata.favicon,
            ogImage: metadata.ogImage,
            language: metadata.language,
            markdown: markdown
        )
    }

    private func extractMetadata(_ doc: Document) -> Metadata {
        // OG tags 优先，fallback 到标准 meta / <title>
        Metadata(
            title: meta(doc, property: "og:title") ?? doc.title(),
            author: meta(doc, name: "author"),
            siteName: meta(doc, property: "og:site_name"),
            favicon: doc.select("link[rel~=icon]").first()?.absUrl("href"),
            ogImage: meta(doc, property: "og:image"),
            language: doc.select("html").first()?.attr("lang")
        )
    }

    private func meta(_ doc: Document, property: String) -> String? {
        try? doc.select("meta[property=\(property)]").first()?.attr("content")
    }

    private func meta(_ doc: Document, name: String) -> String? {
        try? doc.select("meta[name=\(name)]").first()?.attr("content")
    }

    private func convertToMarkdown(_ element: Element?) throws -> String {
        // 递归遍历 DOM 节点，转换为 Markdown
        // h1-h6 → # 标题
        // p → 段落
        // a → [text](href)
        // img → ![alt](src)
        // ul/ol → 列表
        // pre/code → 代码块
        // blockquote → > 引用
        // 其他 → 纯文本
        // ...
    }
}
```

#### 方案 C — Safari 页面数据直传（快速通道）

从 Safari 分享时，系统通过 `NSItemProvider` 提供页面元数据，可在 Share Extension 中零网络请求获取标题：

```swift
// ShareViewController.swift — 增强 Safari 分享场景
if provider.hasItemConformingToTypeIdentifier("com.apple.property-list") {
    provider.loadItem(forTypeIdentifier: "com.apple.property-list") { item, _ in
        if let dict = item as? [String: Any],
           let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
            let title = results["title"] as? String
            let selectedText = results["selection"] as? String
            // 保存时直接附带标题，主 App 减少一次解析
        }
    }
}
```

### 2.5 抓取流程与降级策略

```
用户分享 URL
     │
     ▼
Share Extension 存 URL 到 SwiftData（status: pending）
     │
     ▼
主 App OfflineQueueManager 检测到 pending 文章
     │
     ▼
┌─── ClientScraper.scrape(url) ───┐
│                                  │
│  成功（~90% 场景）        失败     │
│  ├─ 存 markdown 到本地     │      │
│  ├─ status → .localReady   │      │
│  ├─ 用户立刻可阅读         │      │
│  │                         │      │
│  ▼                         ▼      │
│  POST /articles            POST /articles
│  { url,                    { url }       ← 不带 content
│    content: {              │
│      title, markdown, ...  │
│    }                       │
│  }                         │
│  │                         │
│  ▼                         ▼
│  服务端跳过 Reader         服务端调用 Reader（兜底）
│  直接 AI 分析              Reader → AI 分析
└──────────────┬───────────────┘
               │
               ▼
         AI 结果回写
  （分类、标签、摘要、要点）
```

**新增文章状态**：

| 状态 | 含义 |
|------|------|
| `pending` | 刚保存，等待处理 |
| `scraping` | 客户端正在抓取 |
| `localReady` | 客户端抓取完成，本地可读，等待上传+AI |
| `processing` | 已提交服务端，AI 处理中 |
| `ready` | 全部完成（内容 + AI 分析） |
| `failed` | 失败 |

### 2.6 服务端配合改动

#### API 变更 — `POST /api/v1/articles` 接受可选内容

```go
type SubmitArticleRequest struct {
    URL      string         `json:"url"`
    TagIDs   []string       `json:"tag_ids,omitempty"`
    Content  *ClientContent `json:"content,omitempty"`   // 新增
}

type ClientContent struct {
    Title    string `json:"title,omitempty"`
    Author   string `json:"author,omitempty"`
    Markdown string `json:"markdown,omitempty"`
    SiteName string `json:"site_name,omitempty"`
    Language string `json:"language,omitempty"`
    Favicon  string `json:"favicon,omitempty"`
    OGImage  string `json:"og_image,omitempty"`
}
```

#### Worker 判断逻辑 — `crawl_handler.go`

```go
func (h *CrawlHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
    var p CrawlPayload
    json.Unmarshal(t.Payload(), &p)

    h.taskRepo.SetCrawlStarted(ctx, p.TaskID)

    // 检查客户端是否已提供内容
    article, _ := h.articleRepo.GetByID(ctx, p.ArticleID)

    if article.MarkdownContent != nil && *article.MarkdownContent != "" {
        // 客户端已完成抓取 → 跳过 Reader
        h.taskRepo.SetCrawlFinished(ctx, p.TaskID)
    } else {
        // 降级 → 服务端抓取
        result, err := h.readerClient.Scrape(ctx, p.URL)
        if err != nil {
            h.taskRepo.SetFailed(ctx, p.TaskID, err.Error())
            h.articleRepo.SetError(ctx, p.ArticleID, err.Error())
            return fmt.Errorf("scrape failed: %w", err)
        }
        h.articleRepo.UpdateCrawlResult(ctx, p.ArticleID, repository.CrawlResult{
            Title: result.Metadata.Title, Author: result.Metadata.Author,
            Markdown: result.Markdown, /* ... */
        })
        h.taskRepo.SetCrawlFinished(ctx, p.TaskID)
    }

    // 无论谁抓的，都走 AI 分析
    aiTask := NewAIProcessTask(p.ArticleID, p.TaskID, p.UserID)
    h.asynqClient.EnqueueContext(ctx, aiTask)
    return nil
}
```

### 2.7 iOS 新增依赖

| 依赖 | 用途 | 内存开销 |
|------|------|---------|
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML 解析 + DOM 操作 | ~5MB |

SwiftSoup 是纯 Swift 实现的 HTML 解析器（类似 Java 的 Jsoup），无 C 依赖，轻量，App Store 上广泛使用。仅添加到主 App target，不添加到 Share Extension。

### 2.8 影响评估

| 维度 | 变化 |
|------|------|
| **用户体验** | 分享后 2-5 秒本地可读（原来 30-90 秒） |
| **服务端 Reader** | 从核心组件降级为兜底，流量降 90%+ |
| **服务端成本** | Reader 实例可缩减到 1 个（仅处理客户端失败的 ~10%） |
| **反爬** | 彻底解决 — 每个用户用自己的 IP 和 Cookie |
| **微信文章** | 可抓取 — 用户设备有微信的网络上下文 |
| **离线体验** | 内容本地可读，AI 标签/摘要后续补全 |

---

## 三、当前架构问题（Phase 2 — 服务端正确性修复）

### 3.1 分布式部署阻碍（必须修复才能多实例）

#### P0-1：Apple JWKS 缓存在进程内存

**位置**：`server/internal/service/auth.go:52-56`

```go
var (
    appleJWKS      *AppleJWKSResponse   // 进程级全局变量
    appleJWKSMu    sync.RWMutex         // 只在本进程内有效
    appleJWKSFetch time.Time            // 24h TTL
)
```

**问题**：多实例部署时，Apple 轮换密钥后，部分实例使用旧缓存导致用户登录随机失败。`sync.RWMutex` 只保护单进程内的并发安全，跨进程无效。

**方案**：JWKS 缓存迁移到 Redis（TTL 24h），所有实例共享同一份缓存。

#### P0-2：配额检查存在 TOCTOU 竞态条件

**位置**：`server/internal/service/quota.go:24-49`

```
时序（两台机器同时处理同一用户请求）：
  机器A: SELECT count=29
  机器B: SELECT count=29    ← 两台都读到 29
  机器A: count < 30? ✓ → UPDATE count=30
  机器B: count < 30? ✓ → UPDATE count=30  ← 应该拒绝，实际放行
```

**问题**：`GetByID` → 判断 → `IncrementMonthCount` 是三步非原子操作。并发场景下用户可突破月度配额。月份重置逻辑也有同样的竞态。

**方案**：用一条原子 SQL 完成检查+重置+递增：

```sql
UPDATE users
SET
  current_month_count = CASE
    WHEN EXTRACT(MONTH FROM quota_reset_at) != EXTRACT(MONTH FROM NOW())
    THEN 1
    ELSE current_month_count + 1
  END,
  quota_reset_at = CASE
    WHEN EXTRACT(MONTH FROM quota_reset_at) != EXTRACT(MONTH FROM NOW())
    THEN NOW()
    ELSE quota_reset_at
  END
WHERE id = $1
  AND (CASE
    WHEN EXTRACT(MONTH FROM quota_reset_at) != EXTRACT(MONTH FROM NOW())
    THEN 0
    ELSE current_month_count
  END) < monthly_quota
RETURNING current_month_count;
```

`affected rows = 0` 即配额用尽，无需应用层判断。

#### P0-3：AI 任务 payload 包含完整文章正文

**位置**：`server/internal/worker/tasks.go:27-35`，`server/internal/worker/ai_handler.go:50-55`

```go
type AIProcessPayload struct {
    Markdown  string `json:"markdown"`   // 完整 markdown，可达 500KB-1MB
}
```

**问题**：
- 长文 500KB × 队列积压 1000 篇 = 500MB，超出 Redis 256MB 上限
- `allkeys-lru` 策略会丢弃排队中的任务，静默丢失数据
- 跨机器拉取任务时带宽浪费严重
- Crawl 阶段已将 markdown 存入 `articles.markdown_content`，payload 中是冗余副本

**方案**：payload 只存 ID 引用，处理时从 DB 按需读取：

```go
type AIProcessPayload struct {
    ArticleID string `json:"article_id"`
    TaskID    string `json:"task_id"`
    UserID    string `json:"user_id"`
    // 去掉 Title、Markdown、Source、Author
}
```

#### P0-4：Tag 计数器非原子更新

**位置**：`server/internal/repository/tag.go:64-74`

```go
r.pool.Exec(ctx, `INSERT INTO article_tags ... ON CONFLICT DO NOTHING`, ...)
r.pool.Exec(ctx, `UPDATE tags SET article_count = article_count + 1 ...`, tagID)
```

**问题**：`ON CONFLICT DO NOTHING` 未插入新行时，UPDATE 仍会执行，导致 `article_count` 越来越大于实际关联数。多实例并发时问题加剧。

**方案**：用 `RETURNING` 判断是否真正插入：

```go
var inserted bool
err := r.pool.QueryRow(ctx, `
    INSERT INTO article_tags (article_id, tag_id) VALUES ($1, $2)
    ON CONFLICT DO NOTHING
    RETURNING true
`, articleID, tagID).Scan(&inserted)

if inserted {
    r.pool.Exec(ctx, `UPDATE tags SET article_count = article_count + 1 WHERE id = $1`, tagID)
}
```

### 3.2 性能瓶颈（影响吞吐量）

#### P1-1：Worker 并发数硬编码

**位置**：`server/internal/worker/server.go:16`

```go
Concurrency: 10  // 写死，无法按实例资源调整
```

**方案**：从环境变量读取，并接受外部传入：

```go
func NewWorkerServer(redisAddr string, concurrency int, ...) *WorkerServer {
    srv := asynq.NewServer(
        asynq.RedisClientOpt{Addr: redisAddr},
        asynq.Config{
            Concurrency: concurrency,
            Queues: map[string]int{
                QueueCritical: 6,
                QueueDefault:  3,
                QueueLow:      1,
            },
            RetryDelayFunc: exponentialBackoff,  // 新增指数退避
        },
    )
}
```

#### P1-2：HTTP 客户端无连接池配置

**位置**：`server/internal/client/reader.go:42-44`，`ai.go:34-38`

```go
httpClient: &http.Client{Timeout: 60 * time.Second}
// 默认 MaxIdleConnsPerHost=2，高并发下大量 TCP 新建开销
```

**方案**：配置 `http.Transport`：

```go
httpClient: &http.Client{
    Timeout: 60 * time.Second,
    Transport: &http.Transport{
        MaxConnsPerHost:     20,
        MaxIdleConnsPerHost: 10,
        IdleConnTimeout:     90 * time.Second,
    },
}
```

#### P1-3：Reader 服务单线程（客户端抓取后优先级降低）

**位置**：`server/reader-service/src/index.ts`

Express.js 单进程运行，DOM 解析为 CPU 密集型操作，阻塞事件循环。

> **注意**：Phase 1 实施客户端抓取后，Reader 服务流量降至 ~10%（仅处理客户端失败的降级请求），此项优先级从 P1 降为 P2。

**方案**：Node.js cluster 模式 + Docker 多实例：

```typescript
import cluster from "node:cluster";

const POOL_SIZE = parseInt(process.env.POOL_SIZE || "4", 10);

if (cluster.isPrimary) {
  for (let i = 0; i < POOL_SIZE; i++) cluster.fork();
  cluster.on("exit", () => cluster.fork());
} else {
  app.listen(port);
}
```

#### P1-4：数据库连接池不足

**位置**：`server/internal/repository/db.go:16-17`

```go
config.MaxConns = 20  // 3 API + 5 Worker = 160 连接，PG 默认上限 100
config.MinConns = 2
```

**方案**：配置化 + 生产环境加 PgBouncer：

```go
maxConns := getEnvInt("DB_MAX_CONNS", 20)
minConns := getEnvInt("DB_MIN_CONNS", 2)
```

```
Client ×8 (MaxConns=10) → PgBouncer (transaction pooling) → PostgreSQL (max 50)
```

#### P1-5：无反压/限流机制

当前 API 端可瞬间提交大量 URL，全部直接进 Redis 队列，无任何保护。

**方案**：三层防护：

| 层级 | 机制 | 阈值 |
|------|------|------|
| API 入口 | per-user 令牌桶限流 | 10 req/s |
| 任务入队 | 队列深度检查 | > 1000 → 返回 429 |
| Worker 侧 | Reader 熔断器 | 连续失败 3 次 → 熔断 30s |

### 3.3 次要问题

| 问题 | 位置 | 描述 | 方案 |
|------|------|------|------|
| AI tag 创建 N+1 | `worker/ai_handler.go:74-80` | 5 个 tag = 15 次 DB 调用 | 批量 INSERT + 批量 UPDATE |
| asynq 无退避策略 | `worker/tasks.go:49-53` | 失败后约 60s 就重试，对端故障时反复冲击 | 添加 `RetryDelayFunc` 指数退避 |
| AI 客户端每次新建 | `ai-service/app/pipeline.py` | `AsyncOpenAI` 不复用 | 全局单例 |
| 大文档正则扫描 | `worker/crawl_handler.go:99-110` | 10MB markdown 的图片 URL 提取耗时高 | 限制 markdown 大小 / 流式处理 |
| Redis 内存不足 | `docker-compose.yml:67` | 256MB + LRU 会丢任务 | 生产环境提至 2GB，启用持久化 |

---

## 四、目标架构

### 4.1 进程分离

当前 API 和 Worker 在同一进程（`cmd/server/main.go:109-114`），无法独立扩展。

**方案**：通过环境变量 `SERVER_MODE` 控制启动角色：

```go
mode := envOrDefault("SERVER_MODE", "all")  // "api" | "worker" | "all"

if mode == "api" || mode == "all" {
    go httpServer.ListenAndServe()
}
if mode == "worker" || mode == "all" {
    go workerServer.Run()
}
```

- `all`：开发模式，单进程跑全部（保持现有行为）
- `api`：只启动 HTTP 服务器
- `worker`：只启动 asynq Worker

asynq 天然支持多 Worker 进程连同一个 Redis，自动竞争消费任务，零额外协调。

### 4.2 架构全景（客户端抓取 + 服务端降级）

```
┌─────────────────────────────────────────────────────────────┐
│                        iOS 客户端                            │
│                                                             │
│  ┌───────────────┐   ┌──────────────────────────────────┐  │
│  │Share Extension │   │           Main App                │  │
│  │               │   │                                  │  │
│  │ 存 URL        │──▶│ ClientScraper ──▶ 本地可读        │  │
│  │ 1.5s 关闭     │   │       │                          │  │
│  └───────────────┘   │       ▼                          │  │
│                      │ SyncService ──▶ POST /articles    │  │
│                      │ { url, content? }                 │  │
│                      └────────────────┬─────────────────┘  │
└───────────────────────────────────────┼─────────────────────┘
                                        │
                                        ▼
┌───────────────────────────────────────────────────────────────┐
│                         服务端                                 │
│                                                               │
│  ┌────────┐     ┌───────┐     ┌──────────────────────────┐   │
│  │ API ×N │────▶│ Redis │◀────│ Worker ×M                │   │
│  └────────┘     └───────┘     │                          │   │
│                               │ content 已有? ──┐         │   │
│                               │    │      YES   │ NO      │   │
│                               │    ▼            ▼         │   │
│                               │  跳过     Reader 服务      │   │
│                               │  Reader   (降级兜底)       │   │
│                               │    │            │         │   │
│                               │    └─────┬──────┘         │   │
│                               │          ▼                │   │
│                               │      AI 分析              │   │
│                               │  (分类/标签/摘要)          │   │
│                               └──────────────────────────┘   │
│                                                               │
│  ┌──────────┐  ┌────────────┐  ┌───────┐  ┌──────────────┐  │
│  │PostgreSQL│  │  PgBouncer │  │ Redis │  │Reader (兜底) │  │
│  └──────────┘  └────────────┘  └───────┘  └──────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

### 4.3 各组件扩展方式

| 组件 | 是否无状态 | 扩展方式 | 需要改动 |
|------|-----------|---------|---------|
| iOS 客户端（抓取） | — | 天然分布式（每用户一个实例） | Phase 1 新增 ClientScraper |
| API Server | 改后是（JWKS → Redis） | `replicas: N`，Caddy/Nginx LB | P0-1 |
| Worker | 天然无状态 | `replicas: M`，asynq 自动竞争消费 | P1-1 进程分离 |
| Reader | 天然无状态 | 保持 1 实例即可（仅兜底） | 客户端抓取后大幅降负 |
| AI Service | 天然无状态 | `replicas: L` + LB | 无需改动 |
| PostgreSQL | 有状态 | PgBouncer 连接收敛 + 只读副本 | P1-4 |
| Redis | 有状态 | Sentinel（高可用）/ Cluster（分片） | 配置层面 |

### 4.4 Docker Compose 生产配置示例

```yaml
services:
  api:
    build: .
    environment:
      - SERVER_MODE=api
      - DB_MAX_CONNS=10
    deploy:
      replicas: 2

  worker:
    build: .
    environment:
      - SERVER_MODE=worker
      - WORKER_CONCURRENCY=20
      - DB_MAX_CONNS=10
    deploy:
      replicas: 3   # 客户端抓取后，Worker 主要处理 AI 任务，需求量降低

  reader:
    build: ./reader-service
    environment:
      - POOL_SIZE=2
    deploy:
      replicas: 1   # 仅兜底，1 实例足够

  ai:
    build: ./ai-service
    deploy:
      replicas: 2

  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 2gb --maxmemory-policy noeviction --appendonly yes

  pgbouncer:
    image: edoburu/pgbouncer
    environment:
      - DATABASE_URL=postgresql://folio:${DB_PASSWORD}@postgres:5432/folio
      - MAX_CLIENT_CONN=200
      - DEFAULT_POOL_SIZE=30
      - POOL_MODE=transaction
```

---

## 五、新增配置项

### 服务端 — `server/internal/config/config.go`

| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `SERVER_MODE` | `all` | 进程角色：`api` / `worker` / `all` |
| `WORKER_CONCURRENCY` | `10` | 单实例 Worker 并发数 |
| `DB_MAX_CONNS` | `20` | 数据库连接池上限 |
| `DB_MIN_CONNS` | `2` | 数据库连接池下限 |
| `RATE_LIMIT_PER_USER` | `10` | 每用户每秒请求上限 |
| `QUEUE_MAX_DEPTH` | `1000` | 任务队列深度上限，超出返回 429 |

### iOS 客户端

| 配置 | 位置 | 默认值 | 说明 |
|------|------|--------|------|
| 抓取超时 | `ClientScraper` | 15 秒 | URLSession 超时 |
| 最大重试 | `ClientScraper` | 1 次 | 客户端抓取失败后重试次数 |
| 最大正文大小 | `ClientScraper` | 2MB | 超出则跳过客户端抓取，交由服务端 |
| 并发抓取数 | `OfflineQueueManager` | 3 | 同时抓取的文章数量上限 |

---

## 六、实施计划

### Phase 1 — 客户端抓取（最高优先级）

**目标**：将抓取从服务端转移到客户端，90%+ 文章由客户端完成，用户分享后 2-5 秒即可阅读。

| 编号 | 任务 | 改动位置 | 预估行数 |
|------|------|---------|---------|
| C-1 | 新增 SwiftSoup 依赖 | `ios/project.yml` | ~3 |
| C-2 | 实现 ClientScraper（HTML 下载+解析+Markdown 转换） | `ios/Folio/Data/Scraper/ClientScraper.swift` | ~200 |
| C-3 | OfflineQueueManager 集成客户端抓取 | `ios/Folio/Data/Network/OfflineQueueManager.swift` | ~40 |
| C-4 | Article model 新增 `localReady` 状态 | `ios/Folio/Domain/Models/Article.swift` | ~5 |
| C-5 | SyncService 上传时附带 content 字段 | `ios/Folio/Data/Sync/SyncService.swift`，`Network.swift` | ~20 |
| C-6 | 服务端 API 接受可选 content | `server/internal/api/handler/article.go`，`service/article.go` | ~25 |
| C-7 | CrawlHandler 跳过已有内容的文章 | `server/internal/worker/crawl_handler.go` | ~10 |
| C-8 | ClientScraper 单元测试 | `ios/FolioTests/Scraper/ClientScraperTests.swift` | ~100 |

**Phase 1 总改动：iOS ~370 行，服务端 ~35 行。完成后用户体验质变。**

### Phase 2 — 服务端正确性修复（消除多实例部署阻碍）

| 编号 | 任务 | 改动文件 | 预估行数 |
|------|------|---------|---------|
| P0-1 | Apple JWKS 缓存迁移到 Redis | `service/auth.go` | ~30 |
| P0-2 | 配额检查改为原子 SQL | `service/quota.go`，`repository/user.go` | ~15 |
| P0-3 | AI 任务 payload 瘦身（去掉 Markdown） | `worker/tasks.go`，`worker/ai_handler.go` | ~20 |
| P0-4 | Tag 计数器条件更新 | `repository/tag.go` | ~10 |

**Phase 2 总改动：~75 行。完成后可安全多实例部署。**

### Phase 3 — 服务端水平扩展（按需实施）

> 客户端抓取实施后，服务端抓取压力降至 ~10%，以下优化可按实际负载按需实施。

| 编号 | 任务 | 改动文件 | 预估行数 | 优先级变化 |
|------|------|---------|---------|-----------|
| P1-1 | Worker 并发数配置化 + 进程分离开关 | `config`，`main.go`，`worker/server.go` | ~40 | 不变 |
| P1-2 | HTTP 客户端连接池配置 | `client/reader.go`，`ai.go`，`r2.go` | ~20 | 不变 |
| P1-3 | Reader 服务 cluster 模式 | `reader-service/src/index.ts` | ~15 | 降为 P2（流量降 90%） |
| P1-4 | DB 连接池配置化 | `repository/db.go`，`config/config.go` | ~10 | 不变 |
| P1-5 | API 限流 + 队列深度检查 | `api/middleware/`，`service/article.go` | ~60 | 不变 |

### Phase 4 — 生产加固

| 编号 | 任务 | 说明 |
|------|------|------|
| P2-1 | AI tag 批量创建 | 减少 N+1 DB 调用 |
| P2-2 | asynq 指数退避策略 | 防止故障时反复冲击下游 |
| P2-3 | Redis 持久化 + 内存扩容 | 防任务丢失 |
| P2-4 | PgBouncer 部署 | 连接收敛 |
| P2-5 | 可观测性（Prometheus metrics） | 队列深度、Worker 利用率、响应时间 |
| P2-6 | 优雅停机增强 | Worker drain 等待 + 超时控制 |

---

## 七、预期效果

| 指标 | MVP（当前） | Phase 1 完成 | Phase 2+3 完成 |
|------|------------|-------------|---------------|
| 内容可读时间 | 30-90 秒 | **2-5 秒**（本地即读） | 2-5 秒 |
| 服务端抓取量 | 100% | ~10%（仅降级） | ~10% |
| Reader 实例需求 | 需扩展 | 1 个足够 | 1 个足够 |
| 反爬问题 | 频繁被封 IP | **彻底解决** | 彻底解决 |
| 微信文章 | 难以抓取 | **正常抓取** | 正常抓取 |
| 多实例部署 | 不支持 | 不支持 | 支持 |
| AI 处理吞吐 | ~3-5 篇/秒 | ~3-5 篇/秒 | 30-50 篇/秒 |
| 扩容方式 | 改代码重部署 | — | `--scale` 热扩 |
| 总代码改动 | — | iOS ~370 行 + 服务端 ~35 行 | 累计 ~540 行 |
