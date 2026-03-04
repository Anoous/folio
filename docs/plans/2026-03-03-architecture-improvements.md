# Architecture Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 3 个真实 bug 并降低 2 个部署风险，不引入不必要的复杂度。

**Architecture:** 分三个阶段：(1) 数据一致性 bug 修复 (2) 部署可靠性改进 (3) 可观测性基础建设。每个阶段独立可发布。

**Tech Stack:** Swift / SwiftUI / SwiftData (iOS)，Go / chi / asynq (后端)，Node.js / TypeScript (Reader)，Docker Compose

---

## 背景：要解决的问题

| # | 问题 | 风险级别 | 影响 |
|---|------|----------|------|
| 1 | 配额双写不一致（UserDefaults vs DB） | **P0** | 用户卸载重装后配额显示错误，Share Extension 不拦截 |
| 2 | Worker 与 API 同进程运行 | **P1** | AI 任务高峰影响 API 响应；无法独立扩容 |
| 3 | Reader npm 依赖绑定本地绝对路径 | **P1** | 其他机器无法构建；CI/CD 依赖特定路径 |
| 4 | 搜索边界未明确（无 UI 反馈） | **P2** | 用户误认为全量搜索，实际只搜本地已同步 |
| 5 | 无结构化日志 | **P2** | 生产问题排查困难 |

---

## Phase 1：数据一致性修复

### Task 1：配额以服务端为准（iOS）

**背景**：`SharedDataManager.canSave(isPro:)` 读取 `UserDefaults.appGroup` 的本地计数。用户卸载重装后本地计数归零，但服务端记录了真实用量，Share Extension 会错误地放行超配额请求。

**根本原因**：每次成功登录/刷新 Token，服务端已通过 `AuthResponse.user.currentMonthCount` 返回了真实配额，但 iOS 从未将其写入 `UserDefaults`。

**Files:**
- Modify: `ios/Folio/App/FolioApp.swift`
- Modify: `ios/Folio/Data/SwiftData/SharedDataManager.swift`
- Test: `ios/FolioTests/Data/SharedDataManagerTests.swift`

---

**Step 1: 在 SharedDataManager 中增加服务端配额同步方法**

打开 `ios/Folio/Data/SwiftData/SharedDataManager.swift`，在 `// MARK: - Quota` 段末尾（第 115 行后）添加：

```swift
/// 将服务端配额写入 UserDefaults，供 Share Extension 读取。
/// 只在服务端计数 > 本地计数时覆盖，避免本地乐观计数被回退。
static func syncQuotaFromServer(
    monthlyQuota: Int,
    currentMonthCount: Int,
    isPro: Bool,
    userDefaults: UserDefaults = .appGroup
) {
    let key = quotaKey()
    let localCount = userDefaults.integer(forKey: key)
    if currentMonthCount > localCount {
        userDefaults.set(currentMonthCount, forKey: key)
    }
    userDefaults.set(monthlyQuota, forKey: "folio.monthlyQuota")
    userDefaults.set(isPro, forKey: "folio.isPro")
}
```

同时，将 `canSave(isPro:)` 改为读取服务端同步的配额上限（不再硬编码 30）：

旧代码（第 112-115 行）：
```swift
static func canSave(isPro: Bool, userDefaults: UserDefaults = .appGroup) -> Bool {
    if isPro { return true }
    return currentMonthCount(userDefaults: userDefaults) < freeMonthlyQuota
}
```

新代码：
```swift
static func canSave(isPro: Bool, userDefaults: UserDefaults = .appGroup) -> Bool {
    if isPro { return true }
    let quota = userDefaults.integer(forKey: "folio.monthlyQuota")
    let effectiveQuota = quota > 0 ? quota : freeMonthlyQuota
    return currentMonthCount(userDefaults: userDefaults) < effectiveQuota
}
```

---

**Step 2: 在 FolioApp 中，认证成功后同步配额**

打开 `ios/Folio/App/FolioApp.swift`，在 `onChange(of: authViewModel.authState)` 的 `if newValue == .signedIn` 分支开头添加配额同步：

旧代码（第 52 行起）：
```swift
if newValue == .signedIn, let manager = offlineQueueManager {
    let sync = SyncService(context: container.mainContext)
```

新代码：
```swift
if newValue == .signedIn, let manager = offlineQueueManager {
    // 将服务端配额同步到 UserDefaults，Share Extension 依赖此值
    if let user = authViewModel.currentUser {
        let isPro = user.subscription != "free"
        SharedDataManager.syncQuotaFromServer(
            monthlyQuota: user.monthlyQuota,
            currentMonthCount: user.currentMonthCount,
            isPro: isPro
        )
    }
    let sync = SyncService(context: container.mainContext)
```

---

**Step 3: 在 SyncService.performFullSync 中也刷新配额**

`performFullSync()` 在登录后和每次前台激活时调用。给 `SyncService` 增加配额刷新能力（不需要新 API，复用现有的 refreshAuth）。

打开 `ios/Folio/Data/Sync/SyncService.swift`，在 `performFullSync()` 方法（第 183 行）中添加：

```swift
func performFullSync() async {
    await syncCategories()
    await syncTags()
    await syncArticles()
    await syncUserQuota()    // ← 新增
}

// MARK: - Quota Sync

private func syncUserQuota() async {
    do {
        let response = try await apiClient.refreshAuth()
        let user = response.user
        let isPro = user.subscription != "free"
        SharedDataManager.syncQuotaFromServer(
            monthlyQuota: user.monthlyQuota,
            currentMonthCount: user.currentMonthCount,
            isPro: isPro
        )
    } catch {
        // 非关键操作，失败时保留本地计数
    }
}
```

注意：`refreshAuth()` 已在 `checkExistingAuth()` 中调用，这里复用它刷新配额。如果担心双重刷新，可以改为直接从 `authViewModel.currentUser` 传入参数而非调用 API（但 SyncService 目前不持有 authViewModel 引用，故复用 refreshAuth 是最简路径）。

---

**Step 4: 编写测试**

打开 `ios/FolioTests/Data/SharedDataManagerTests.swift`，添加测试用例：

```swift
func testSyncQuotaFromServer_updatesWhenServerCountIsHigher() {
    let defaults = UserDefaults(suiteName: "test.quota.\(UUID())")!
    let key = SharedDataManager.quotaKey()

    // 本地计数 5，服务端 12 → 应更新为 12
    defaults.set(5, forKey: key)
    SharedDataManager.syncQuotaFromServer(
        monthlyQuota: 30,
        currentMonthCount: 12,
        isPro: false,
        userDefaults: defaults
    )
    XCTAssertEqual(defaults.integer(forKey: key), 12)
}

func testSyncQuotaFromServer_doesNotDecreaseLocalCount() {
    let defaults = UserDefaults(suiteName: "test.quota.\(UUID())")!
    let key = SharedDataManager.quotaKey()

    // 本地计数 15（用户刚保存了几篇），服务端 10（未同步）→ 不应回退
    defaults.set(15, forKey: key)
    SharedDataManager.syncQuotaFromServer(
        monthlyQuota: 30,
        currentMonthCount: 10,
        isPro: false,
        userDefaults: defaults
    )
    XCTAssertEqual(defaults.integer(forKey: key), 15)
}

func testCanSave_usesServerQuotaWhenAvailable() {
    let defaults = UserDefaults(suiteName: "test.quota.\(UUID())")!
    let key = SharedDataManager.quotaKey()

    // 服务端配额 50（Pro+），本地计数 35
    defaults.set(35, forKey: key)
    defaults.set(50, forKey: "folio.monthlyQuota")
    XCTAssertTrue(SharedDataManager.canSave(isPro: false, userDefaults: defaults))

    // 计数超过服务端配额
    defaults.set(51, forKey: key)
    XCTAssertFalse(SharedDataManager.canSave(isPro: false, userDefaults: defaults))
}
```

**Step 5: 运行测试验证**

```bash
xcodebuild test \
  -project ios/Folio.xcodeproj \
  -scheme Folio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing FolioTests/SharedDataManagerTests \
  2>&1 | grep -E "(PASS|FAIL|error:)"
```

预期：所有新增测试 PASS。

**Step 6: Commit**

```bash
git add ios/Folio/App/FolioApp.swift \
        ios/Folio/Data/SwiftData/SharedDataManager.swift \
        ios/Folio/Data/Sync/SyncService.swift \
        ios/FolioTests/Data/SharedDataManagerTests.swift
git commit -m "fix: sync quota from server to UserDefaults on sign-in

Fixes a bug where reinstalling the app cleared local quota count
while the server still tracked usage. Share Extension now reads
server-authoritative count synced on every successful auth/refresh."
```

---

### Task 2：明确搜索边界，添加 UI 提示

**背景**：iOS 搜索仅查询本地 FTS5 索引（已同步的文章），但用户不知道这一限制。如果用户有 100 篇文章只同步了 50 篇，搜索结果可能遗漏内容。

**决策**：搜索范围 = 本地已同步文章（保持现有实现），但 UI 需要告知用户已同步数量。

**Files:**
- Modify: `ios/Folio/Presentation/Search/SearchViewModel.swift`
- Modify: 找到 SearchView 文件（通过搜索确认路径）

**Step 1: 确认 SearchView 的实际文件位置**

```bash
find ios/Folio/Presentation/Search -name "*.swift" | sort
```

**Step 2: 在 SearchViewModel 中暴露已同步文章数**

打开 `ios/Folio/Presentation/Search/SearchViewModel.swift`，添加属性：

```swift
var syncedArticleCount: Int = 0

func refreshSyncedCount(context: ModelContext) {
    let descriptor = FetchDescriptor<Article>(
        predicate: #Predicate { $0.status == .ready || $0.status == .clientReady }
    )
    syncedArticleCount = (try? context.fetchCount(descriptor)) ?? 0
}
```

**Step 3: 在 SearchView 搜索框下方添加提示文字**

在搜索结果列表为空时的 empty state，以及搜索框下方添加副标题：

```swift
// 在 searchable 视图的 prompt 或结果页顶部
Text("搜索 \(viewModel.syncedArticleCount) 篇已同步文章")
    .font(.caption)
    .foregroundStyle(.secondary)
```

**Step 4: Commit**

```bash
git add ios/Folio/Presentation/Search/
git commit -m "ux: show synced article count in search to clarify search scope"
```

---

## Phase 2：部署可靠性

### Task 3：Worker 与 API 进程分离

**背景**：当前 `main.go` 在同一进程中启动 HTTP 服务和 asynq Worker。AI 任务（CPU 密集）会与 HTTP 请求竞争资源；一个任务 panic 可能拖垮整个 API 服务。

**方案**：添加 `APP_MODE` 环境变量（`api` | `worker` | `all`），在 docker-compose.yml 中拆分为两个服务（复用同一镜像）。

**Files:**
- Modify: `server/cmd/server/main.go`
- Modify: `server/internal/config/config.go`
- Modify: `server/docker-compose.yml`
- Test: 手动验证（见 Step 4）

---

**Step 1: 在 config 中增加 AppMode**

打开 `server/internal/config/config.go`，在 `Config` 结构体中添加字段，并在 `Load()` 中读取：

```go
type Config struct {
    // ... 现有字段 ...
    AppMode string // "api" | "worker" | "all"（默认 "all"）
}

// 在 Load() 函数中添加：
cfg.AppMode = os.Getenv("APP_MODE")
if cfg.AppMode == "" {
    cfg.AppMode = "all"
}
if cfg.AppMode != "api" && cfg.AppMode != "worker" && cfg.AppMode != "all" {
    return nil, fmt.Errorf("invalid APP_MODE %q: must be api, worker, or all", cfg.AppMode)
}
```

**Step 2: 在 main.go 中按 AppMode 启动不同角色**

打开 `server/cmd/server/main.go`，将 Worker 和 HTTP Server 的启动逻辑包裹在条件判断中。

找到第 108 行（`// Start worker in background`），将 Worker 启动和 HTTP 启动部分替换为：

```go
// 按 AppMode 启动角色
switch cfg.AppMode {
case "worker":
    log.Println("Starting in WORKER mode...")
    if err := workerServer.Run(); err != nil {
        log.Fatalf("worker server error: %v", err)
    }

case "api":
    log.Println("Starting in API mode...")
    runHTTPServer(httpServer, cfg.Port)

default: // "all"
    log.Println("Starting in ALL mode (API + Worker)...")
    go func() {
        log.Println("Starting worker server...")
        if err := workerServer.Run(); err != nil {
            log.Fatalf("worker server error: %v", err)
        }
    }()
    runHTTPServer(httpServer, cfg.Port)
}
```

在 `main()` 函数外添加辅助函数：

```go
func runHTTPServer(server *http.Server, port string) {
    done := make(chan os.Signal, 1)
    signal.Notify(done, os.Interrupt, syscall.SIGTERM)

    go func() {
        fmt.Printf("Folio server listening on :%s\n", port)
        if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("server failed: %v", err)
        }
    }()

    <-done
    log.Println("Shutting down HTTP server...")
    shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    if err := server.Shutdown(shutdownCtx); err != nil {
        log.Printf("HTTP server shutdown error: %v", err)
    }
}
```

注意：原来的 graceful shutdown 逻辑（第 126-147 行）需要删除，由 `runHTTPServer` 内部处理。`workerServer.Shutdown()` 调用放到 `case "all"` 分支中：

```go
default: // "all"
    log.Println("Starting in ALL mode (API + Worker)...")
    go func() {
        if err := workerServer.Run(); err != nil {
            log.Fatalf("worker server error: %v", err)
        }
    }()
    runHTTPServer(httpServer, cfg.Port)
    workerServer.Shutdown()
```

**Step 3: 在 docker-compose.yml 中拆分 worker 服务**

打开 `server/docker-compose.yml`，修改 `api` 服务并添加 `worker` 服务：

在 `api` 服务的 `environment` 中添加：
```yaml
  api:
    environment:
      - APP_MODE=api          # ← 新增
      - DATABASE_URL=...
      # 其余不变
```

在 `api` 服务之后添加 `worker` 服务：
```yaml
  worker:
    build:
      context: .
      dockerfile: Dockerfile
    environment:
      - APP_MODE=worker
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
```

**Step 4: 验证构建和行为**

```bash
cd server

# 验证 Go 编译通过
go build ./cmd/server

# 单独测试 worker 模式（后台运行 2 秒后关闭）
APP_MODE=worker \
DATABASE_URL=postgresql://folio:folio@localhost:5432/folio \
JWT_SECRET=test-secret-for-local-32chars-min \
REDIS_ADDR=localhost:6380 \
timeout 2 ./folio-server || true

# 验证输出包含 "Starting in WORKER mode"
```

预期输出：`Starting in WORKER mode...`，然后正常退出（无 panic）。

**Step 5: Commit**

```bash
git add server/cmd/server/main.go \
        server/internal/config/config.go \
        server/docker-compose.yml
git commit -m "feat: add APP_MODE env var to separate API and Worker processes

Allows deploying API and Worker as separate containers using the same
image, enabling independent scaling and fault isolation. Default 'all'
preserves existing single-process behavior for local development."
```

---

### Task 4：Reader npm 依赖改为可复现构建

**背景**：`package.json` 中 `"@vakra-dev/reader": "file:/Users/mac/github/reader"` 绑定了本地绝对路径，导致其他机器或 CI/CD 无法构建 Docker 镜像。

**方案**：将 reader 库打包为 npm tarball，提交到仓库的 `vendor/` 目录，修改 `package.json` 引用。

**Files:**
- Create: `server/reader-service/vendor/` 目录
- Modify: `server/reader-service/package.json`
- Modify: `server/reader-service/Dockerfile`（确认构建路径）

**Step 1: 打包 reader 库**

```bash
# 确认 reader 库已构建
ls /Users/mac/github/reader/dist/

# 打包为 tarball
cd /Users/mac/github/reader
npm pack
# 输出文件名，例如：vakra-dev-reader-1.0.0.tgz

# 创建 vendor 目录并移入
mkdir -p /Users/mac/github/folio/server/reader-service/vendor
mv vakra-dev-reader-*.tgz /Users/mac/github/folio/server/reader-service/vendor/

# 记录实际文件名
ls /Users/mac/github/folio/server/reader-service/vendor/
```

**Step 2: 更新 package.json**

打开 `server/reader-service/package.json`，将依赖路径从绝对路径改为相对 vendor 路径：

旧代码：
```json
"@vakra-dev/reader": "file:/Users/mac/github/reader"
```

新代码（文件名根据 Step 1 实际输出填入）：
```json
"@vakra-dev/reader": "file:./vendor/vakra-dev-reader-1.0.0.tgz"
```

**Step 3: 重新安装依赖验证**

```bash
cd server/reader-service
rm -rf node_modules/@vakra-dev
npm install
# 验证：node_modules/@vakra-dev/reader 存在
ls node_modules/@vakra-dev/reader/dist/
```

**Step 4: 验证服务启动**

```bash
npm run dev &
sleep 3
curl -s http://localhost:3000/health
# 预期：{"status":"ok"}
kill %1
```

**Step 5: 在 .gitignore 中确认 tarball 不被忽略**

```bash
# 检查是否被忽略
cd /Users/mac/github/folio
git check-ignore -v server/reader-service/vendor/vakra-dev-reader-*.tgz
# 若有输出则需要修改 .gitignore，添加例外：
# !server/reader-service/vendor/*.tgz
```

**Step 6: Commit**

```bash
cd /Users/mac/github/folio
git add server/reader-service/vendor/
git add server/reader-service/package.json
git add server/reader-service/package-lock.json
git commit -m "fix: vendor reader npm package to enable reproducible builds

Replaces absolute local path dependency with a committed tarball in
vendor/, allowing the Docker image to be built on any machine without
requiring the reader library to be installed at a specific local path."
```

---

## Phase 3：可观测性基础建设

### Task 5：Go 服务添加结构化日志

**背景**：当前使用 `log.Printf`（非结构化）。生产环境排查问题需要按字段（userID、articleID、duration）过滤日志，纯文本日志做不到。Go 1.21+ 内置 `log/slog`，无需引入依赖。

**改造范围**：仅改造最高价值的日志点 — Handler 请求日志、Worker 任务日志、错误日志。不改 chi 的内置 Logger 中间件（已够用）。

**Files:**
- Create: `server/internal/logger/logger.go`
- Modify: `server/cmd/server/main.go`
- Modify: `server/internal/worker/crawl_handler.go`
- Modify: `server/internal/worker/ai_handler.go`

---

**Step 1: 创建全局 logger 初始化**

创建 `server/internal/logger/logger.go`：

```go
package logger

import (
    "log/slog"
    "os"
)

// Init 初始化全局 slog logger。
// 生产环境（LOG_FORMAT=json）输出 JSON，开发环境输出文本。
func Init() {
    format := os.Getenv("LOG_FORMAT")
    level := slog.LevelInfo

    var handler slog.Handler
    if format == "json" {
        handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})
    } else {
        handler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level})
    }
    slog.SetDefault(slog.New(handler))
}
```

**Step 2: 在 main.go 中初始化**

打开 `server/cmd/server/main.go`，在 `main()` 函数第一行添加：

```go
import "folio-server/internal/logger"

func main() {
    logger.Init()
    // ... 其余不变
```

同时将 `main.go` 中现有的 `log.Println` / `log.Fatalf` 替换为 `slog.Info` / `slog.Error`：

```go
// 替换前
log.Fatalf("failed to load config: %v", err)

// 替换后
slog.Error("failed to load config", "error", err)
os.Exit(1)
```

```go
// 替换前
log.Println("Starting worker server...")
log.Fatalf("worker server error: %v", err)

// 替换后
slog.Info("starting worker server")
slog.Error("worker server error", "error", err)
os.Exit(1)
```

**Step 3: Worker 日志添加结构化字段**

打开 `server/internal/worker/crawl_handler.go`，将任务处理的关键日志改为结构化：

```go
// 替换前（找到类似语句）
log.Printf("crawl task failed for article %s: %v", articleID, err)

// 替换后
slog.Error("crawl task failed",
    "article_id", articleID,
    "error", err,
    "retry_count", retryCount,
)
```

在任务成功时添加耗时日志：

```go
start := time.Now()
// ... 处理逻辑 ...
slog.Info("crawl task completed",
    "article_id", articleID,
    "duration_ms", time.Since(start).Milliseconds(),
    "source_type", sourceType,
)
```

同样处理 `server/internal/worker/ai_handler.go`。

**Step 4: 在 docker-compose.yml 中添加 LOG_FORMAT**

在生产环境的 `api` 和 `worker` 服务中添加：

```yaml
environment:
  - LOG_FORMAT=json    # ← 新增，生产输出 JSON 便于日志系统解析
```

**Step 5: 验证日志输出**

```bash
cd server

# 验证编译
go build ./cmd/server

# 测试文本格式（开发默认）
APP_MODE=api \
DATABASE_URL=postgresql://folio:folio@localhost:5432/folio \
JWT_SECRET=test-secret-for-local-32chars-minimum \
REDIS_ADDR=localhost:6380 \
timeout 1 ./folio-server 2>&1 | head -5

# 测试 JSON 格式
LOG_FORMAT=json APP_MODE=api ... timeout 1 ./folio-server 2>&1 | head -3 | python3 -m json.tool
```

预期：JSON 格式输出有效的 JSON 对象，包含 `time`、`level`、`msg` 字段。

**Step 6: Commit**

```bash
git add server/internal/logger/ \
        server/cmd/server/main.go \
        server/internal/worker/crawl_handler.go \
        server/internal/worker/ai_handler.go \
        server/docker-compose.yml
git commit -m "feat: add structured logging with log/slog

Replaces log.Printf with slog for structured JSON output in production.
Worker logs now include article_id, duration_ms, and error fields for
easier filtering in log aggregation systems."
```

---

## 验收标准

| 任务 | 验收条件 |
|------|----------|
| Task 1 (配额同步) | 卸载重装 App → 登录 → Share Extension 显示正确剩余配额，与服务端一致 |
| Task 2 (搜索提示) | 搜索页显示"搜索 X 篇已同步文章"，X 与本地 ready/clientReady 文章数一致 |
| Task 3 (Worker 分离) | `APP_MODE=api` 启动不运行 Worker；`APP_MODE=worker` 不监听 HTTP 端口；`APP_MODE=all` 行为与原来一致 |
| Task 4 (npm 依赖) | 在新机器上仅 clone 仓库，不需要 `/Users/mac/github/reader`，Reader Docker 镜像可正常构建并响应 `/health` |
| Task 5 (结构化日志) | `LOG_FORMAT=json` 时所有日志输出有效 JSON；错误日志包含 `article_id` 字段 |

---

## 不做的事（有意识的取舍）

- **不拆分 APIClient**：23KB 单文件可维护性稍差，但当前无多人协作冲突，等文件超 500 行频繁 PR 冲突时再拆。
- **不引入 Elasticsearch**：pg_trgm 对当前数据量（单用户 < 10K 文章）完全够用，中文搜索问题影响面有限。
- **不加 /api/v1/me 端点**：复用 refreshAuth 已满足配额同步需求，无需增加新接口。
- **不做 SwiftData/SQLite 边界重构**：现有"SwiftData 写入、FTS5 查询"的分工已经清晰，不需要统一层。
