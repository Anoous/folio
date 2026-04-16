# CLAUDE.md

本文件为 Claude Code / Opus / Codex 等仓库内代理提供 Folio 仓库的长期上下文。

最后人工更新：2026-04-16

## 项目概述

Folio（页集）是一款本地优先的个人知识收藏与理解 iOS 应用。用户从微信、Safari、Twitter/X、博客等任意 App 分享链接，Folio 会尽快将内容保存到本地，随后完成正文提取、AI 分析、全文索引与跨端同步。

一句话定位：

> 分享链接，知识留住。

当前更准确的产品目标不是“玩具收藏夹”或“炫技 AI demo”，而是：

> 一个安静、简约、默认好用的个人 AI 知识伙伴。

当前核心闭环：

`保存 -> 同步 -> 阅读 -> 搜索找回 -> AI 理解`

## 当前状态（2026-04-16 基线）

项目已经不再是早期 MVP，而是 `advanced MVP / pre-production alpha`。最近几轮 hardening 已完成并写入代码：

- `reader-service` SSRF 防护已升级，抓取错误有结构化契约。
- 公共认证接口已改为代理感知限流。
- refresh token 已从无状态 JWT 升级为可撤销、可 rotation 的服务端 session，支持 `/api/v1/auth/logout`。
- iOS 已补齐后台补偿同步、启动时订阅补偿、搜索索引一致性、截图/语音失败重试语义。
- API 契约已硬化，非法 UUID 路径参数统一返回 `400`，软删除文章不会再被直接读取。
- pipeline 已落地 typed error + 结构化日志。
- 默认 E2E 已稳定，`run_e2e.sh` 会做真实 cleanup，不应残留测试端口、后台进程或 Docker 容器。

已经存在但还未完全打磨成最终产品差异化体验的能力：

- RAG 问答已经存在
- Echo / Highlight / Related / Stats 已存在
- 更完整的“自动从整库选上下文”的 Ask / Spark / Learn 体验仍是下一阶段产品重点

## 仓库快照（2026-04-16）

以下规模是当前基线，后续会继续增长：

- `ios/Folio/`：97 个 Swift 文件
- `ios/ShareExtension/`：2 个 Swift 文件
- `ios/Shared/`：9 个 Swift 文件
- `ios/FolioTests/`：42 个 Swift 测试文件
- `server/internal/`：98 个 Go 文件
- `server/migrations/`：`001` 到 `016`，另有升级辅助 SQL
- `server/tests/e2e/`：16 个顶层 pytest suite
- `docs/architecture/`：`hardening-sprint-01` 到 `hardening-sprint-08`

仓库主结构：

```text
folio/
├── CLAUDE.md
├── docs/
│   ├── design/prd.md
│   ├── interaction/core-flows.md
│   ├── architecture/
│   │   ├── system-design.md
│   │   ├── api-contract.md
│   │   └── hardening-sprint-01..08.md
│   ├── ios-mvp-plan.md
│   └── local-deploy.md
├── ios/
│   ├── project.yml
│   ├── Folio.xcodeproj/
│   ├── Folio/
│   ├── ShareExtension/
│   ├── Shared/
│   └── FolioTests/
└── server/
    ├── cmd/server/main.go
    ├── internal/
    ├── migrations/
    ├── reader-service/
    ├── scripts/
    ├── tests/e2e/
    ├── docker-compose*.yml
    └── Caddyfile
```

## 产品与体验原则

所有代理在做产品和架构决策时，都必须守住这些原则：

1. `收藏零摩擦`
   用户把内容交给 Folio 时，保存确认必须很快，不要引入新的人工配置步骤。

2. `整理零负担`
   不让用户做 AI 可以自动完成的事情。能自动分类、摘要、关联、检索的，就不要要求用户先手工组织。

3. `找到零等待`
   新保存内容必须能被快速找回，本地搜索和服务端状态不能长期漂移。

4. `本地优先、同步可靠`
   Share Extension、本地 SwiftData、后台补偿同步、启动补偿、失败重试必须形成闭环。

5. `安静、克制、默认好用`
   不堆配置面板，不引入 NotebookLM 式“先选几篇文章再聊”的重流程，尤其是 AI 功能应尽量自动选择上下文。

6. `AI 输出必须可追溯`
   问答、灵感、学习辅助都必须能回到具体文章、高亮或原文片段；证据不足时必须明确说不知道。

如果产品方向发生冲突，优先级按这个顺序判断：

1. 保存成功率
2. 阅读质量
3. 搜索找回
4. 同步一致性
5. AI 放大价值

## 关键设计文档

做大改动前，优先阅读这些文档：

- `/Users/mac/github/folio/docs/design/prd.md`
- `/Users/mac/github/folio/docs/interaction/core-flows.md`
- `/Users/mac/github/folio/docs/architecture/system-design.md`
- `/Users/mac/github/folio/docs/architecture/api-contract.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-01.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-02-ios-background-sync.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-03-ios-data-closure.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-04-auth-sessions.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-05-ios-auth-session-bridge.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-06-e2e-stability.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-07-api-contracts.md`
- `/Users/mac/github/folio/docs/architecture/hardening-sprint-08-pipeline-observability.md`

## iOS 客户端

### 技术栈

- Swift 5.9+
- SwiftUI
- SwiftData
- SQLite FTS5
- Nuke / NukeUI
- KeychainAccess
- SwiftSoup
- iOS 17.0+
- Xcode 16.2
- XcodeGen（`ios/project.yml`）

### Targets

- `Folio`：主应用
- `ShareExtension`：系统分享入口
- `FolioTests`：单元测试

### 关键标识符

有两套需要区分的标识：

- Xcode 工程中的主应用 Bundle ID：`com.7WSH9CR7KS.folio.app`
- Share Extension Bundle ID：`com.7WSH9CR7KS.folio.app.share-extension`
- App Group：`group.com.7WSH9CR7KS.folio.app`

同时，运行时常量里仍然使用：

- `AppConstants.bundleIdentifier = "com.folio.app"`
- StoreKit product id：`com.folio.app.pro.yearly` / `com.folio.app.pro.monthly`

修改 bundle、entitlement、keychain、订阅产品 id 时要注意这两套值不要混淆。

### 网络环境

`APIClient.defaultBaseURL` 当前行为：

- DEBUG + Simulator：`http://localhost:8080`
- DEBUG + 真机：`https://api.echolore.ai`
- RELEASE：`https://api.folio.app`

### iOS 架构要点

- 主体架构仍是 `MVVM + Clean-ish layering`
- `FolioApp` 创建共享 `ModelContainer`，注入 `AuthViewModel`、`OfflineQueueManager`、`SyncService`、`SubscriptionManager`
- `AppStartupCoordinator` 在启动时负责产品拉取、entitlement 校验、待补偿订阅校验重放、交易监听
- `BackgroundSyncCoordinator` + `OfflineQueueManager` 负责后台补偿上传与 BG task
- `SearchIndexCoordinator` 负责保存、提取、同步、删除后的 FTS5 索引一致性
- `ContentSaveService` 负责 URL / 手动内容 / 截图 / 语音等内容写入与统一保存路径
- `SharedDataManager` / `DataManager` 负责主 App 与 Share Extension 共享容器
- `SyncService` 负责与服务端增量/全量同步
- `KeyChainManager` 保存 access token / refresh token
- `AuthViewModel` 已接入新的 session 语义，登出会 best-effort 调后端 `/auth/logout`

### Share Extension 现状

- Share Extension 已不是“只写本地假闭环”
- 它会把记录写入 App Group 容器
- 主 App 启动、回前台、网络恢复、后台补偿时会继续把待同步内容真正上传到服务端

### iOS 关键路径

- `/Users/mac/github/folio/ios/Folio/App/`
- `/Users/mac/github/folio/ios/Folio/Data/`
- `/Users/mac/github/folio/ios/Folio/Presentation/`
- `/Users/mac/github/folio/ios/Folio/Domain/Models/`
- `/Users/mac/github/folio/ios/ShareExtension/`
- `/Users/mac/github/folio/ios/Shared/`

最值得优先阅读的文件：

- `/Users/mac/github/folio/ios/Folio/App/FolioApp.swift`
- `/Users/mac/github/folio/ios/Folio/App/AppStartupCoordinator.swift`
- `/Users/mac/github/folio/ios/Folio/Data/ContentSaveService.swift`
- `/Users/mac/github/folio/ios/Folio/Data/Sync/SyncService.swift`
- `/Users/mac/github/folio/ios/Folio/Data/Sync/BackgroundSyncCoordinator.swift`
- `/Users/mac/github/folio/ios/Folio/Data/Network/OfflineQueueManager.swift`
- `/Users/mac/github/folio/ios/Folio/Data/Search/SearchIndexCoordinator.swift`
- `/Users/mac/github/folio/ios/Folio/Data/Network/APIClient.swift`

## Go 后端

### 技术栈

- Go 1.24+
- chi v5
- asynq + Redis
- pgx v5 + PostgreSQL
- slog
- JWT access token + DB-backed refresh session

### 运行模式

`server/cmd/server/main.go` 支持：

- `APP_MODE=api`
- `APP_MODE=worker`
- `APP_MODE=all`（默认）

`all` 模式下 HTTP + worker 同进程运行，并带 push scheduler。

### 中间件与边界

- `Logger`
- `Recoverer`
- `RequestID`
- 请求体上限 `1 MB`
- JWT 鉴权
- 公共认证接口限流

### 当前 API 路由概览

公开接口：

- `GET /health`
- `POST /api/v1/auth/apple`
- `POST /api/v1/auth/email/code`
- `POST /api/v1/auth/email/verify`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `POST /api/v1/webhook/apple`

受保护接口：

- 文章：`/articles`、`/articles/manual`、`/articles/search`、`/articles/{id}`、`/articles/{id}/retry`、`/articles/{id}/related`
- 标签 / 分类：`/tags`、`/categories`
- 任务：`/tasks/{id}`
- 订阅：`/subscription/verify`
- 高亮：`/articles/{id}/highlights`、`/highlights/{id}`
- Echo：`/echo/today`、`/echo/{id}/review`
- RAG：`/rag/query`、`/rag/query/stream`
- 设备：`/devices`
- 统计：`/stats/monthly`、`/stats/echo`

### Worker 任务

当前 worker 不止 crawl + ai：

- `article:crawl`
- `article:ai`
- `article:images`
- `echo:*`
- `push:*`
- `relate:*`

关键实现目录：

- `/Users/mac/github/folio/server/internal/worker/`
- `/Users/mac/github/folio/server/internal/service/`
- `/Users/mac/github/folio/server/internal/repository/`
- `/Users/mac/github/folio/server/internal/api/handler/`
- `/Users/mac/github/folio/server/internal/client/`

### 认证现状

当前认证不是早期的“长效 refresh JWT”模式，而是：

- access token：JWT，短期有效，带 `sid`
- refresh token：opaque token，格式 `<session_id>.<secret>`
- 服务端只存 `sha256(secret)`
- refresh 会 rotation
- stale token 重放会撤销 session
- `/auth/logout` 会撤销 session

不要把它退回无状态 refresh JWT。

### pipeline 与外部依赖

当前文章处理链路：

`submit -> task -> reader -> fallback jina -> ai analyze -> relation / echo / stats 等后续能力`

现有外部客户端包括：

- `reader.go`
- `jina.go`
- `ai.go`
- `ai_analyze.go`
- `ai_rag.go`
- `apple.go`
- `apns.go`
- `resend.go`
- `r2.go`

现在 client / worker 之间已经有 typed pipeline error + 结构化日志，不要再回到靠字符串判断错误类型。

## Reader Service

### 技术栈

- Node.js
- TypeScript
- Express
- `@vakra-dev/reader`

位置：

- `/Users/mac/github/folio/server/reader-service/`

### 本地依赖

`@vakra-dev/reader` 当前仍通过本地文件依赖：

`file:../../../reader`

这意味着如果 `/Users/mac/github/reader` 更新，需要先在 reader 仓库构建，再回到 `server/reader-service` 安装依赖。

### 端点

- `GET /health`
- `POST /scrape`

### `/scrape` 契约

返回成功时包含：

- `markdown`
- `metadata`
- `duration_ms`

失败时返回结构化错误体：

```json
{
  "error": "reader request timed out",
  "code": "timeout",
  "provider": "reader",
  "retryable": true
}
```

当前错误码语义：

- `400`：`invalid_request` / `blocked_target`
- `422`：`empty_content`
- `502`：`network` / `internal`
- `504`：`timeout`

### 安全基线

- 有 SSRF 防护
- 会拦截不安全目标
- 会做 URL 校验与解析
- 允许公开 hostname 在代理环境下解析到特殊地址，但仍阻止直接提交危险 literal IP
- `timeout_ms` 上限为 `120000`

## 数据与存储

### iOS 侧

- SwiftData：主本地存储
- SQLite FTS5：本地全文搜索
- App Group container：主 App 与 Share Extension 共享数据、图片、标记
- Keychain：access / refresh token

### 服务端

- PostgreSQL：主数据
- Redis：asynq、验证码、部分短期状态
- R2：可选图片转存

### 迁移现状

当前迁移不再只有 `001_init`。主要里程碑包括：

- `001`：初始表结构
- `002`：content cache / soft delete
- `003`：sync epoch
- `006`：manual content
- `007`：client id
- `008`：v3 upgrade
- `009`：highlights
- `010`：subscription transaction
- `011`：devices
- `012`：smart retrieval
- `013`：auth / stats bugfix
- `014`：article field versions
- `015`：refresh sessions
- `016`：crawl task failure metadata

升级辅助脚本：

- `/Users/mac/github/folio/server/migrations/upgrade_008_012.sql`

## 不能回退的生产化基线

后续改动不能破坏这些已经补好的约束：

1. `reader-service` SSRF 防护与结构化抓取错误契约
2. 公共 auth 接口的代理感知限流
3. refresh session 的 rotation / revocation / logout 语义
4. iOS 后台补偿同步、启动补偿、FTS 索引一致性
5. 手动内容、截图、语音的统一保存与重试语义
6. 非法 UUID 路径参数返回 `400`
7. 软删除文章不能直接 GET 成功
8. pipeline failure metadata 与结构化日志
9. 默认 E2E 运行后 cleanup 必须收尾干净

如果你修改这些区域，必须显式验证没有回归。

## 默认开发命令

### 后端本地开发

```bash
cd /Users/mac/github/folio/server && ./scripts/dev-start.sh
```

### API 容器重建

```bash
cd /Users/mac/github/folio/server && docker compose -f docker-compose.local.yml up --build -d app
```

### 全栈重建

```bash
cd /Users/mac/github/folio/server && ./scripts/deploy-local.sh rebuild
```

### Go 本地构建

```bash
cd /Users/mac/github/folio/server && go build -o folio-server ./cmd/server
```

### Reader 构建

```bash
cd /Users/mac/github/folio/server/reader-service && npm run build
```

### iOS 打开工程

```bash
open /Users/mac/github/folio/ios/Folio.xcodeproj
```

### XcodeGen 重新生成

```bash
cd /Users/mac/github/folio/ios && xcodegen generate
```

### 数据库访问

宿主机通常不直接装 `psql`，优先通过 Docker 进入：

```bash
cd /Users/mac/github/folio/server && docker compose -f docker-compose.local.yml exec postgres psql -U folio -d folio
```

## 默认测试与验收门槛

后端默认回归：

```bash
cd /Users/mac/github/folio/server && go test ./...
```

Reader 默认回归：

```bash
cd /Users/mac/github/folio/server/reader-service && npm test
```

默认 E2E：

```bash
cd /Users/mac/github/folio/server && ./scripts/run_e2e.sh
```

iOS 单测：

```bash
xcodebuild test -project /Users/mac/github/folio/ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

如果改了 E2E 脚本、测试基础设施、后台服务启动逻辑，还要额外验证：

- `docker ps` 不残留测试容器
- 端口 `13000` / `18080` 无残留监听
- 无残留 `run_e2e.sh` / API / reader-service 进程

注意：

- `jina_integration_test.go` 已被移出默认 `go test ./...` 路径
- 如果 E2E 失败，优先检查 `server/tests/e2e/reports/` 和 `reports/logs/`

## 针对代理的工作建议

1. 先读代码，不要凭印象下结论。
2. 大改动前优先读 PRD、interaction、system-design 与 hardening sprint 文档。
3. 改产品体验时，先问“这是不是让用户多做了一步本该由系统完成的事？”
4. 改 AI 体验时，优先做自动收敛上下文，而不是要求用户先手动选文章。
5. 改同步、搜索、保存链路时，必须从 Share Extension、本地 SwiftData、后台任务、服务端任务、索引更新整个闭环一起看。
6. 改认证时，必须同时看 iOS `AuthViewModel` / `KeyChainManager` / `APIClient` 和后端 `AuthService` / `RefreshSessionRepo`。
7. 改 pipeline 时，必须同时看 reader、jina、ai client、worker、task failure metadata、pipeline log。

## 当前最值得继续投入的方向

如果目标是继续把产品从“高级 MVP”推进到“真正有差异化的个人知识系统”，优先级建议是：

1. 守住保存、同步、阅读、搜索找回四个基础闭环
2. 继续提升阅读页质量与找回能力
3. 基于整库自动选上下文的 AI 问答
4. 灵感提取与知识连接
5. 学习辅助与长期复盘

避免把产品做成复杂 AI 控制台；更接近正确方向的是：

- `Ask Folio`：直接问，系统自动选上下文，回答带引用
- `Spark`：基于收藏自动发现连接与灵感
- `Learn`：基于收藏生成总结、概念与复习内容

这些能力都必须保持 Folio 的产品气质：

`安静、克制、默认好用、功能强大但不复杂`

## 语言与文档

- 仓库内设计与开发文档以中文为主
- 产品面向全球用户，中英双语支持
- 做文档更新时，优先保证“对当前真实代码负责”，不要继续复制早期 MVP 表述
