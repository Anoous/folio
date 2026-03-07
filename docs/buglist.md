# Folio 待修复 Bug 清单

> 来源：2026-03-07 全栈深度 Code Review
> 状态标记：[ ] 待修复 / [x] 已修复

---

## P0 — Critical（必须立即修复）

### 安全漏洞

- [ ] **#1 Apple Sign In 缺少 audience 验证**
  - `server/internal/service/auth.go:237-243`
  - 只验证 issuer，未验证 `aud` claim。攻击者可用其他 app 的 Apple token 登录 Folio

- [ ] **#2 Reader Service SSRF**
  - `server/reader-service/src/index.ts:12-18`
  - 用户提交的 URL 无任何验证，可请求内网地址（`169.254.169.254`、`localhost:5432` 等）

- [ ] **#3 Go API 无 URL 验证**
  - `server/internal/api/handler/article.go:48-52`
  - 只检查非空，不验证 scheme/host，`file:///etc/passwd` 等均可提交

- [ ] **#4 Go API 无 Request Body 大小限制**
  - 所有 handler 未用 `http.MaxBytesReader`
  - 攻击者可发送 GB 级请求体耗尽内存（DoS）

- [ ] **#5 AI Service 异常信息泄露**
  - `server/ai-service/app/main.py:29`
  - `f"AI service error: {e}"` 可能泄露 API key、内部地址等敏感信息

### 严重 Bug

- [ ] **#6 缓存命中时 Task 卡在 "crawling"**
  - `server/internal/worker/crawl_handler.go:281`
  - `SetCrawlFinished()` 不设置 status，全量缓存命中后 task 永远显示 crawling

- [ ] **#7 缓存命中路径 DB 写入错误被吞**
  - `server/internal/worker/crawl_handler.go:252,263`
  - `UpdateCrawlResult`/`UpdateAIResult` 返回的 error 被完全忽略

- [ ] **#8 Dockerfile Go 版本不匹配**
  - `server/Dockerfile:1`
  - 使用 `golang:1.22-alpine`，但 go.mod 要求 1.24，构建会失败或产生错误二进制

### CLAUDE.md 关键违规

- [ ] **#9 硬编码 "com.folio.app"**
  - `ios/Folio/Data/KeyChain/KeyChainManager.swift:20`、`ios/Folio/Utils/FolioLogger.swift:4-7`
  - `AppConstants.keychainServiceName` 已存在但未引用

- [ ] **#10 硬编码 task status 字符串**
  - `ios/Folio/Data/Sync/SyncService.swift:93-103` — iOS 用 `"done"/"failed"` 字面量
  - `server/internal/repository/task.go:65-101` — Go 在 SQL 中用 `'ready'/'crawling'` 字面量

- [ ] **#11 硬编码 "free" 订阅检查**
  - `ios/Folio/App/FolioApp.swift:63`、`ios/Folio/Data/Sync/SyncService.swift:217`
  - 两个文件相同字符串，应为共享常量或枚举

---

## P1 — High（上线前必须修复）

### 安全

- [ ] **#12 Apple JWKS 获取无超时**
  - `server/internal/service/auth.go:286` — `http.Get` 无 timeout，Apple 慢响应阻塞登录

- [ ] **#13 Docker 容器全部以 root 运行**
  - 所有 3 个 Dockerfile

- [ ] **#14 R2 Client 下载图片无大小限制**
  - `server/internal/client/r2.go:76` — `io.ReadAll` 可被超大响应 OOM

- [ ] **#15 Reader `timeout_ms` 无上限**
  - `server/reader-service/src/index.ts:26` — 攻击者可设极大值长期占用连接

- [ ] **#16 AI Service 无内容大小限制**
  - `server/ai-service/app/main.py` — 可接收 GB 级文本

- [ ] **#17 Prompt injection 风险**
  - `server/ai-service/app/prompts/combined.py:55-67` — 用户内容直接插入 prompt

### Bug / 数据一致性

- [ ] **#18 `SubmitURL` TOCTOU 竞态**
  - `server/internal/service/article.go:59-64` — 并发提交同 URL 都通过存在性检查

- [ ] **#19 Quota 未回滚（task 创建/入队失败时）**
  - `server/internal/service/article.go:100-114` — 用户永久丢失配额

- [ ] **#20 `read_progress` 无范围验证**
  - `server/internal/api/handler/article.go:141-157` — 可设负数或 >1.0

- [ ] **#21 `json.Encoder.Encode` 错误被忽略**
  - `server/internal/api/handler/response.go:15` — 编码失败客户端收到空响应

- [ ] **#22 FTS5SearchManager 无线程安全保证**
  - `ios/Folio/Data/Search/FTS5SearchManager.swift` — 无 actor 隔离，并发访问可能崩溃

- [ ] **#23 ShareViewController 每次 save 创建新 ModelContainer**
  - `ios/ShareExtension/ShareViewController.swift:59-64` — 昂贵操作 + 潜在写冲突

### CLAUDE.md 违规

- [ ] **#24 `"already saved"` 字符串匹配替代状态码**
  - `ios/Folio/Data/Sync/SyncService.swift:59` — 应匹配 HTTP 409

- [ ] **#25 Navigation `"settings"` magic string**
  - `ios/Folio/Presentation/Home/HomeView.swift:47,157` — 应用类型安全的枚举路由

- [ ] **#26 分页默认值重复**
  - `server/internal/api/handler/article.go` 和 `handler/search.go` — page/perPage/maxPerPage 同值两处硬编码

---

## P2 — Medium（下个迭代修复）

### iOS

- [ ] **#27 `SharedDataManager.existsByURL` 缺少 `@MainActor`**
- [ ] **#28 三个 Repository 类均缺少 `@MainActor`**
- [ ] **#29 带 tag 过滤的分页结果不准确** — 先分页后过滤导致短页
- [ ] **#30 ContentExtractor 超时后子任务不检查取消** — ShareExtension 内存浪费
- [ ] **#31 `saveArticleFromText` 把非 URL 文本存为 URL**
- [ ] **#32 ReaderView `updateReadingProgress` 每帧保存磁盘** — 应节流
- [ ] **#33 MarkdownRenderer 在 body 中每次重新解析** — 无缓存
- [ ] **#34 大量使用 `AnyView` type erasure** — 阻碍 SwiftUI diff
- [ ] **#35 `@Query` + ViewModel 双数据源不一致**
- [ ] **#36 ISO8601DateFormatter 每次解码创建新实例** — 50 篇 = 500-1000 次分配
- [ ] **#37 ~~DailyDigestCard/InsightCard 生产代码含假数据~~** — N/A：这两个组件已在 Jobs 式重设计中删除（F10 改为洞察级摘要，F14 知识唤醒已砍掉）。如代码中仍有残留文件需清理
- [ ] **#38 多处 `try? context.save()` 静默吞错** — 21 处，磁盘满时静默丢数据
- [ ] **#39 `unsafeBitCast(-1)` 模拟 SQLITE_TRANSIENT** — 脆弱的 platform assumption

### Go Backend

- [ ] **#40 Task handler 泄露其他用户 task 存在性** — 403 vs 404 区分
- [ ] **#41 `countWords` CJK 严重不准** — 5000 字中文文章只计 ~50 "词"
- [ ] **#42 `DECIMAL(3,2)` 精度不够** — confidence 和 read_progress
- [ ] **#43 `json.Unmarshal` key_points 错误被忽略**
- [ ] **#44 `json.Marshal` nil→`null` 替代空数组** — 与 DB 默认 `'[]'` 不一致
- [ ] **#45 `AIHandler` 未用接口，难以测试**
- [ ] **#46 `DEEPSEEK_API_KEY` 缺失时 KeyError** — 应启动时快速失败

### 基础设施

- [ ] **#47 分类名中英不一致（`时事` vs `新闻`）** — AI service 和 migration SQL 对 "news" 用不同中文名
- [ ] **#48 Production docker-compose 无网络隔离**
- [ ] **#49 Production docker-compose 无 healthcheck**
- [ ] **#50 AI service requirements.txt 未固定版本** — 构建不可重现
- [ ] **#51 Caddyfile 只监听 HTTP** — 无 TLS 配置
- [ ] **#52 Mock AI Service 绑定 0.0.0.0** — 暴露到局域网

---

## P3 — Low（方便时修复）

- [ ] **#53 FTS5 搜索未过滤特殊语法关键字** — `-`/`+`/`NOT`/`NEAR` 等
- [ ] **#54 `UserIDFromContext` 空值时返回空字符串而非错误**
- [ ] **#55 ImageView/ImageViewerOverlay 4 个英文字符串未本地化**
- [ ] **#56 SettingsView 价格与 PRD 不符** — PRD 定价 Pro $9.99/yr、Pro+ $19.99/yr，需与 SettingsView 对齐
- [ ] **#57 无用变量** — `totalPages`(OnboardingView)、`hashlib`(AI service)
- [ ] **#58 Reader service 零测试覆盖**
- [ ] **#59 `SyncService.lastSyncedAt` 用 `.standard` 而非 AppGroup UserDefaults**
- [ ] **#60 `HTMLFetcher` 全部下载完后才检查大小**
- [ ] **#61 `TagRepository.fetchPopular` 加载全部 tag 到内存**
- [ ] **#62 `SearchViewModel.historyKey` 应移到 AppConstants**
- [ ] **#63 `CodeBlockView` 用 GCD 而非 Swift Concurrency**
- [ ] **#64 多处 accessibility label 缺失** — ImageViewerOverlay、DailyDigestCard、ReaderView toolbar 等
- [ ] **#65 `FolioButton` primary 用 `cardBackground` 作文字色** — 语义不对
- [ ] **#66 `Date+RelativeFormat` 手写而非用 `RelativeDateTimeFormatter`**
