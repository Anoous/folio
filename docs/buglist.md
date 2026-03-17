# Folio 待修复 Bug 清单

> 来源：2026-03-07 全栈深度 Code Review
> 状态标记：[ ] 待修复 / [x] 已修复

---

## P0 — Critical（必须立即修复）

### 安全漏洞

- [x] **#1 Apple Sign In 缺少 audience 验证**
  - `server/internal/service/auth.go` — 添加 `jwt.WithAudience("com.folio.app")`

- [x] **#2 Reader Service SSRF**
  - `server/reader-service/src/index.ts` — 添加 `isPrivateURL` 验证，拒绝内网/localhost/私有 IP

- [x] **#3 Go API 无 URL 验证**
  - `server/internal/api/handler/article.go` — 只允许 http/https scheme

- [x] **#4 Go API 无 Request Body 大小限制**
  - `server/internal/api/router.go` — 添加 1MB MaxBytesReader 中间件

- [x] **#5 AI Service 异常信息泄露**
  - `server/ai-service/app/main.py` — 错误信息改为 "internal failure"

### 严重 Bug

- [x] **#6 缓存命中时 Task 卡在 "crawling"**
  - `server/internal/worker/crawl_handler.go` — cache hit 路径改用 `SetAIFinished` + `UpdateStatus(ready)`

- [x] **#7 缓存命中路径 DB 写入错误被吞**
  - `server/internal/worker/crawl_handler.go` — 所有 cache hit 路径 DB 操作加 error 检查

- [x] **#8 Dockerfile Go 版本不匹配**
  - `server/Dockerfile` — `golang:1.22-alpine` → `golang:1.24-alpine`

### CLAUDE.md 关键违规

- [x] **#9 硬编码 "com.folio.app"**
  - `KeyChainManager` 和 `FolioLogger` 改为引用 `AppConstants.bundleIdentifier`

- [x] **#10 硬编码 task status 字符串**
  - iOS: 改用 `AppConstants.TaskStatus.*` 常量
  - Go: `task.go` 改用 `domain.TaskStatus*` 参数化查询

- [x] **#11 硬编码 "free" 订阅检查**
  - 改用 `AppConstants.subscriptionFree` 常量

---

## P1 — High（上线前必须修复）

### 安全

- [x] **#12 Apple JWKS 获取无超时**
  - `auth.go` — 改用带 10s timeout 的 `http.Client`

- [x] **#13 Docker 容器全部以 root 运行**
  - 3 个 Dockerfile 均添加非 root 用户

- [x] **#14 R2 Client 下载图片无大小限制**
  - `r2.go` — 添加 `io.LimitReader(resp.Body, 10MB)`

- [x] **#15 Reader `timeout_ms` 无上限**
  - `index.ts` — 添加 `MAX_TIMEOUT_MS = 120_000` 上限

- [x] **#16 AI Service 无内容大小限制**
  - `models.py` — 添加 pydantic validator 截断至 200KB

- [x] **#17 Prompt injection 风险**
  - `combined.py` — 添加 `_sanitize_field` 清理 role markers 和 backticks

### Bug / 数据一致性

- [x] **#18 `SubmitURL` TOCTOU 竞态**
  - 依赖 DB unique constraint (user_id, url) 作最终保护（已存在）

- [x] **#19 Quota 未回滚（task 创建/入队失败时）**
  - `article.go` — task 创建和 enqueue 失败时均调用 `DecrementQuota`

- [x] **#20 `read_progress` 无范围验证**
  - `article.go` handler — 添加 [0, 1] 范围检查

- [x] **#21 `json.Encoder.Encode` 错误被忽略**
  - `response.go` — 添加 error 日志

- [x] **#22 FTS5SearchManager 无线程安全保证**
  - 添加串行 `DispatchQueue` 保护所有 SQLite 操作

- [x] **#23 ShareViewController 每次 save 创建新 ModelContainer**
  - 已使用 `lazy var` 缓存，无需修复

### CLAUDE.md 违规

- [x] **#24 `"already saved"` 字符串匹配替代状态码**
  - 添加 `APIError.conflict`，409 直接匹配枚举 case

- [x] **#25 Navigation `"settings"` magic string**
  - 添加 `HomeDestination` 枚举替代字符串路由

- [x] **#26 分页默认值重复**
  - 提取 `defaultPage/defaultPerPage/maxPerPage` 共享常量

---

## P2 — Medium（下个迭代修复）

### iOS

- [x] **#27 `SharedDataManager.existsByURL` 缺少 `@MainActor`**
- [x] **#28 三个 Repository 类均缺少 `@MainActor`**
- [x] **#29 带 tag 过滤的分页结果不准确** — 先分页后过滤导致短页
- [x] **#30 ContentExtractor 超时后子任务不检查取消** — ShareExtension 内存浪费
- [x] **#31 `saveArticleFromText` 把非 URL 文本存为 URL**
- [x] **#32 ReaderView `updateReadingProgress` 每帧保存磁盘** — 添加节流
- [x] **#33 MarkdownRenderer 在 body 中每次重新解析** — 添加缓存
- [x] **#34 大量使用 `AnyView` type erasure** — 审查确认 AnyView 仅限 MarkdownRenderer（MarkupVisitor 模式需要异构类型数组，用法合理），其余代码无 AnyView
- [x] **#35 `@Query` + ViewModel 双数据源不一致** — 移除 HomeView 的 @Query，统一由 HomeViewModel 作为唯一数据源
- [x] **#36 ISO8601DateFormatter 每次解码创建新实例** — 改为静态共享实例
- [x] **#37 ~~DailyDigestCard/InsightCard 生产代码含假数据~~** — N/A：已删除
- [x] **#38 多处 `try? context.save()` 静默吞错** — 添加 `ModelContext.safeSave` helper
- [x] **#39 `unsafeBitCast(-1)` 模拟 SQLITE_TRANSIENT** — 提取为 `SQLITE_TRANSIENT_SWIFT` 常量

### Go Backend

- [x] **#40 Task handler 泄露其他用户 task 存在性** — 403 → 404
- [x] **#41 `countWords` CJK 严重不准** — 添加 CJK rune 计数
- [x] **#42 `DECIMAL(3,2)` 精度不够** — 新增 migration 改为 `NUMERIC(7,6)`
- [x] **#43 `json.Unmarshal` key_points 错误被忽略** — 添加 error 处理
- [x] **#44 `json.Marshal` nil→`null` 替代空数组** — 初始化为空 slice
- [x] **#45 `AIHandler` 未用接口，难以测试** — 提取 `aiAnalyzer` 接口
- [x] **#46 `DEEPSEEK_API_KEY` 缺失时 KeyError** — 添加启动时验证

### 基础设施

- [x] **#47 分类名中英不一致（`时事` vs `新闻`）** — 新增 migration 修正
- [x] **#48 Production docker-compose 无网络隔离** — 添加 frontend/backend 网络
- [x] **#49 Production docker-compose 无 healthcheck** — 所有服务添加 healthcheck
- [x] **#50 AI service requirements.txt 未固定版本** — 固定所有版本号
- [x] **#51 Caddyfile 只监听 HTTP** — 配置域名启用自动 HTTPS
- [x] **#52 Mock AI Service 绑定 0.0.0.0** — 改为 127.0.0.1

---

## P3 — Low（方便时修复）

- [x] **#53 FTS5 搜索未过滤特殊语法关键字** — 添加 `-`/`+`/`NOT`/`NEAR`/`AND`/`OR` 过滤
- [x] **#54 `UserIDFromContext` 空值时返回空字符串而非错误** — 添加日志
- [x] **#55 ImageView/ImageViewerOverlay 4 个英文字符串未本地化** — 已本地化
- [x] **#56 SettingsView 价格与 PRD 不符** — 已一致（Pro $9.99/yr）
- [x] **#57 无用变量** — 移除 `totalPages`(OnboardingView)、`hashlib`(mock AI)
- [x] **#58 Reader service 零测试覆盖** — 添加 17 个测试（health、验证、SSRF 拒绝私有 IP/localhost/非 http scheme、timeout 上限）
- [x] **#59 `SyncService.lastSyncedAt` 用 `.standard` 而非 AppGroup UserDefaults** — 改为 `.appGroup`
- [x] **#60 `HTMLFetcher` 全部下载完后才检查大小** — 添加 Content-Length 预检查
- [x] **#61 `TagRepository.fetchPopular` 加载全部 tag 到内存** — 改用 FetchDescriptor + sortBy + fetchLimit，在数据库层面限制
- [x] **#62 `SearchViewModel.historyKey` 应移到 AppConstants** — 已移至 `AppConstants.searchHistoryKey`
- [x] **#63 `CodeBlockView` 用 GCD 而非 Swift Concurrency** — `DispatchQueue.main.asyncAfter` 改为 `Task { try? await Task.sleep(for:) }`
- [x] **#64 多处 accessibility label 缺失** — ImageViewerOverlay 关闭按钮、ReaderView back/more/original/share/progress 均已补齐 accessibilityLabel
- [x] **#65 `FolioButton` primary 用 `cardBackground` 作文字色** — 改为 `.white`
- [x] **#66 `Date+RelativeFormat` 手写而非用 `RelativeDateTimeFormatter`** — 改用系统 formatter
