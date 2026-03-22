# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 提供本仓库的开发指引。

## 项目概述

Folio（页集）是一款本地优先的个人知识策展 iOS 应用。用户从任意 App（微信、Twitter、浏览器）分享链接，Folio 自动提取内容、分类、打标签、AI 摘要，并在设备本地存储，支持全文搜索。

**核心流程**：收集 → 整理 → 查找（零配置）

**当前状态**：MVP 实现完成 — iOS 应用（58 源文件 + 5 共享文件）、Go 后端（含内置 AI 分析）、Reader 服务、E2E 测试套件（14 个测试文件）、iOS 单元测试（35 个测试文件）。

## 仓库结构

```
folio/
├── CLAUDE.md
├── docs/
│   ├── design/prd.md              # PRD：9 个功能（F1-F9）、订阅等级
│   ├── architecture/
│   │   ├── system-design.md       # 系统架构、数据模型
│   │   └── api-contract.md        # API 契约
│   ├── interaction/core-flows.md  # UI/UX 流程、界面原型
│   ├── ios-mvp-plan.md            # MVP 任务拆解（50 iOS + 22 后端任务）
│   └── local-deploy.md            # 本地部署指南
├── ios/                           # iOS 应用
│   ├── project.yml                # XcodeGen 项目定义
│   ├── Folio.xcodeproj/
│   ├── Folio/                     # 主 App Target（58 个 Swift 文件）
│   ├── ShareExtension/            # Share Extension Target（2 个 Swift 文件）
│   ├── FolioTests/                # 单元测试（35 个 Swift 文件）
│   └── Shared/                    # App 与 Extension 共享代码（5 个 Swift 文件）
└── server/
    ├── cmd/server/main.go         # Go API + Worker 入口
    ├── internal/                   # Go 包（api, service, repository, worker, client, config, domain）
    ├── migrations/                 # PostgreSQL 迁移（001_init.up.sql）
    ├── reader-service/             # Node.js 内容抓取（TypeScript + Express）
    ├── tests/e2e/                  # E2E 测试套件（Python pytest，14 个测试文件）
    ├── scripts/
    │   ├── dev-start.sh            # 一键本地开发启动
    │   ├── run_e2e.sh              # 完整 E2E 测试运行器
    │   └── smoke_api_e2e.sh        # 快速 API 冒烟测试
    ├── docker-compose.yml          # 生产环境（Caddy + API + Reader + PG + Redis）
    ├── docker-compose.local.yml     # 开发环境（全栈容器：API + Reader + PG + Redis）
    ├── docker-compose.test.yml     # E2E 测试（隔离端口 15432/16379）
    ├── Dockerfile                  # 多阶段 Go API 构建
    ├── Caddyfile                   # 反向代理配置
    └── .env.example                # 环境变量模板
```

## 架构

三层系统：

### 1. iOS 客户端

- **技术栈**：Swift 5.9+ / SwiftUI / SwiftData / SQLite FTS5
- **架构模式**：MVVM + Clean Architecture（Presentation → Domain → Data）
- **部署目标**：iOS 17.0
- **Xcode**：16.2，通过 XcodeGen 生成项目（`ios/project.yml`）
- **Bundle IDs**：`com.folio.app`（主应用）、`com.folio.app.share-extension`
- **App Group**：`group.com.folio.app`（主应用与 Extension 共享数据）

**Targets**：
- `Folio` — 主应用（SwiftUI 生命周期，AppDelegate 适配器）
- `ShareExtension` — 分享面板入口（120MB 内存限制）
- `FolioTests` — 单元测试

**依赖**（Swift Package Manager）：
- `apple/swift-markdown` ≥ 0.5.0 — Markdown 渲染
- `kean/Nuke` ≥ 12.8.0 — 图片加载（Nuke + NukeUI）
- `kishikawakatsumi/KeychainAccess` ≥ 4.2.2 — 安全凭证存储
- `scinfu/SwiftSoup` ≥ 2.7.0 — HTML 解析，用于客户端内容提取

**应用结构**：
- 单 NavigationStack（无 TabView）：HomeView 内联 `.searchable()` 搜索，SettingsView 通过工具栏齿轮图标进入
- 引导流程（4 页 + PermissionView）→ DEBUG 构建下可用 Dev Login 按钮
- `APIClient.defaultBaseURL` = DEBUG 下 `http://localhost:8080`，RELEASE 下 `https://api.folio.app`
- OfflineQueueManager 管理待处理文章，SyncService 负责服务器同步

**iOS 关键源码路径**：
- `ios/Folio/App/` — FolioApp.swift（入口）、MainTabView.swift（NavigationStack 根）、AppDelegate.swift
- `ios/Folio/Presentation/` — Auth/、Home/、Reader/、Search/、Settings/、Onboarding/、Components/
- `ios/Folio/Domain/Models/` — Article、Tag、Category、User 值类型
- `ios/Folio/Data/SwiftData/` — DataManager.swift、SharedDataManager.swift
- `ios/Folio/Data/Network/` — Network.swift（APIClient + 全部 DTO）、OfflineQueueManager.swift
- `ios/Folio/Data/Search/` — SQLite FTS5 全文搜索
- `ios/Folio/Data/Repository/` — Repository 模式抽象层
- `ios/Folio/Data/KeyChain/` — KeyChainManager（Token 存储）
- `ios/Folio/Data/Sync/` — SyncService（CloudKit + 后端同步）
- `ios/Shared/Extraction/` — ContentExtractor、HTMLFetcher、ReadabilityExtractor、HTMLToMarkdownConverter、ExtractionResult（App 与 Share Extension 共享）

### 2. Go 后端

- **技术栈**：Go 1.24+ / chi v5 路由 / asynq 任务队列 / pgx v5 / JWT
- **入口**：`server/cmd/server/main.go` — 单进程启动 HTTP 服务器 + Worker 服务器
- **架构模式**：Handler → Service → Repository → Domain

**API 路由**（chi 路由，`server/internal/api/router.go`）：
- `GET /health` — 健康检查
- `POST /api/v1/auth/apple` — Apple 登录
- `POST /api/v1/auth/email/code` — 发送邮箱验证码（打印到日志）
- `POST /api/v1/auth/email/verify` — 验证码登录/注册（邮箱不存在则创建）
- `POST /api/v1/auth/refresh` — 刷新 Token
- `GET /api/v1/articles` — 列表（分页，可按分类/状态/收藏筛选）
- `POST /api/v1/articles` — 提交 URL → 创建文章 + 抓取任务
- `GET /api/v1/articles/{id}` — 详情
- `PUT /api/v1/articles/{id}` — 更新（收藏、归档、阅读进度）
- `DELETE /api/v1/articles/{id}` — 删除
- `GET /api/v1/articles/search?q=` — 全文搜索
- `GET /api/v1/tags` — 标签列表
- `POST /api/v1/tags` — 创建标签
- `DELETE /api/v1/tags/{id}` — 删除标签
- `GET /api/v1/categories` — 分类列表
- `GET /api/v1/tasks/{id}` — 轮询任务状态
- `POST /api/v1/subscription/verify` — 验证订阅

**中间件**：JWT 认证（`server/internal/api/middleware/auth.go`）— 从请求上下文中提取 userID。

**Worker 任务**（asynq，Redis 支撑，`server/internal/worker/`）：
1. `article:crawl` — 调用 Reader 服务，存储 markdown，入队 AI 任务；Reader 失败时回退到客户端提取的内容（Critical 队列，3 次重试，90 秒超时）
2. `article:ai` — 调用 DeepSeek API 进行 AI 分析（无 API Key 时使用内置 mock），存储分类/标签/摘要（Default 队列，3 次重试，60 秒超时）
3. `article:images` — 将图片转存到 R2（Low 队列，2 次重试，5 分钟超时）

**外部客户端**（`server/internal/client/`）：
- `reader.go` — Reader 服务 HTTP 客户端
- `ai.go` — DeepSeek API 客户端（实现 Analyzer 接口，直接调用 DeepSeek Chat API）
- `ai_mock.go` — Mock AI 分析器（DEEPSEEK_API_KEY 为空时自动启用，基于 URL 模式返回确定性结果）
- `r2.go` — Cloudflare R2 S3 兼容客户端（可选）

**配置**（`server/internal/config/config.go`）：

| 环境变量 | 必需 | 默认值 | 说明 |
|---------|------|--------|------|
| `DATABASE_URL` | 是 | — | PostgreSQL 连接字符串 |
| `JWT_SECRET` | 是 | — | JWT 签名密钥 |
| `PORT` | 否 | 8080 | HTTP 端口 |
| `REDIS_ADDR` | 否 | localhost:6379 | Redis 地址（容器内默认 redis:6379） |
| `READER_URL` | 否 | http://localhost:3000 | Reader 服务 URL |
| `DEEPSEEK_API_KEY` | 否 | —（空=mock） | DeepSeek API 密钥，为空时使用内置 mock 分析器 |
| `DEEPSEEK_BASE_URL` | 否 | https://api.deepseek.com | DeepSeek API 基础 URL |
| `APPLE_BUNDLE_ID` | 否 | com.7WSH9CR7KS.folio.app | Apple 登录 audience 验证 |
| `R2_ENDPOINT` | 否 | — | Cloudflare R2 端点 |
| `R2_ACCESS_KEY` | 否 | — | R2 访问密钥 |
| `R2_SECRET_KEY` | 否 | — | R2 秘密密钥 |
| `R2_BUCKET_NAME` | 否 | folio-images | R2 存储桶名称 |
| `R2_PUBLIC_URL` | 否 | — | R2 公开 URL 前缀 |

### 3. Reader 服务

- **技术栈**：Node.js / TypeScript / Express / `@vakra-dev/reader`
- **位置**：`server/reader-service/`
- **端点**：`POST /scrape`（url → markdown + 元数据）、`GET /health`
- **本地依赖**：`@vakra-dev/reader` 通过 `file:../../../reader` 链接（需要 `/Users/mac/github/reader` 存在且 `dist/` 已构建）
- **更新 reader**：当 `/Users/mac/github/reader` 的 reader 库更新后，运行 `cd /Users/mac/github/reader && npm run build` 重新构建，然后 `cd server/reader-service && rm -rf node_modules/@vakra-dev && npm install` 拉取新版本，并重启 reader 服务。
- **开发命令**：`npm run dev`（使用 tsx），**构建**：`npm run build`（tsc → dist/）

**AI 分析**（内置于 Go 后端）：
- 通过 DeepSeek Chat API（`deepseek-chat` 模型，temperature=0.3，max_tokens=1024，JSON 输出）直接进行文章分析
- 9 个分类：tech、business、science、culture、lifestyle、news、education、design、other
- 单次调用返回：category（slug + name）、confidence（0-1）、tags（3-5 个）、summary、key_points（3-5 条）、language（zh/en）
- 无 API Key 时自动使用 mock 分析器（基于 URL 模式的确定性响应）

## 数据库

PostgreSQL 16，迁移文件位于 `server/migrations/001_init.up.sql`。

**表**：users、categories（预插入 9 条）、articles、tags、article_tags、crawl_tasks、activity_logs

**扩展**：uuid-ossp、pg_trgm（三元组全文搜索）

**关键约束**：
- articles：unique (user_id, url) — 每用户不允许重复 URL
- tags：unique (user_id, name)
- articles.status：pending → processing → ready | failed
- crawl_tasks.status：queued → running → done | failed
- users.subscription：free | pro | pro+，monthly_quota 默认 30

## 本地开发

**全容器模式**：所有后端服务运行在 Docker 容器内（`docker-compose.local.yml`），宿主机只需要安装 Docker。

**一键启动**：

```bash
cd server && ./scripts/dev-start.sh
```

自动完成：检查 `.env` 配置、打包 reader 本地依赖、构建并启动全栈容器（Go API + Reader + PostgreSQL + Redis）、打开 Xcode。

**宿主机暴露端口**：
- Go API：8080（唯一对外端口，iOS App 连接此地址）

Reader、PostgreSQL、Redis 仅在容器网络内通信，不暴露到宿主机。

**数据库访问**：宿主机上**未安装** `psql`，通过 `docker compose exec` 访问：
```bash
# 开发数据库
cd server && docker compose -f docker-compose.local.yml exec postgres psql -U folio -d folio -c "YOUR SQL HERE"

# E2E 测试数据库（docker-compose.test.yml）
docker exec $(docker ps --filter "publish=15432" -q) psql -U folio -d folio -c "YOUR SQL HERE"
```

**Redis 访问**：
```bash
cd server && docker compose -f docker-compose.local.yml exec redis redis-cli
```

**查看日志**：
```bash
# 所有容器日志
cd server && docker compose -f docker-compose.local.yml logs -f

# 只看 API 日志
cd server && docker compose -f docker-compose.local.yml logs -f app

# 搜索特定日志（如邮箱验证码）
cd server && docker compose -f docker-compose.local.yml logs app | grep 'verification code' | tail -5

# 搜索文章抓取结果
cd server && docker compose -f docker-compose.local.yml logs app | grep 'crawl task completed' | tail -10
```

**代码改动后重启**：
```bash
# 重新构建并重启 API 容器（Reader/DB/Redis 不受影响）
cd server && docker compose -f docker-compose.local.yml up --build -d app

# 全栈重建（含 Reader）
cd server && ./scripts/deploy-local.sh rebuild
```

**停止服务**：在 dev-start.sh 终端按 Ctrl+C，或手动执行：
```bash
cd server && docker compose -f docker-compose.local.yml down
# 加 -v 清除数据卷：docker compose -f docker-compose.local.yml down -v
```

**iOS 模拟器调试**：在 Xcode 中 Cmd+R → 点击 "Dev Login" 按钮（仅 DEBUG 构建可用）→ 测试功能。

**iOS 真机部署**（当 Xcode 显示设备为 unknown 时使用命令行）：
```bash
# 1. 编译（真机 Device ID: 00008130-000A61483EC0001C）
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio \
  -destination 'id=00008130-000A61483EC0001C' -allowProvisioningUpdates

# 2. 安装
xcrun devicectl device install app --device 00008130-000A61483EC0001C \
  /Users/mac/Library/Developer/Xcode/DerivedData/Folio-doibwjteeqeddrcbskywtleokllf/Build/Products/Debug-iphoneos/Folio.app

# 3. 启动
xcrun devicectl device process launch --device 00008130-000A61483EC0001C com.7WSH9CR7KS.folio.app
```

详见 `docs/local-deploy.md`。

## 测试

**iOS 单元测试**（35 个文件，位于 `ios/FolioTests/`）：
```bash
xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**E2E 测试**（14 个测试文件，位于 `server/tests/e2e/`，Python pytest）：
```bash
cd server && ./scripts/run_e2e.sh
```
使用隔离的 docker-compose.test.yml（PostgreSQL :15432、Redis :16379、API :18080、Reader :13000）。报告生成在 `server/tests/e2e/reports/`。

**快速冒烟测试**：
```bash
cd server && ./scripts/smoke_api_e2e.sh
```

**iOS UI 自动化测试**（Appium + XCUITest）：

用于模拟器上的 UI 交互验证，与后端 E2E 测试独立。

前置条件：后端服务已通过 `dev-start.sh` 启动，App 已安装到模拟器。

```bash
# 启动 Appium 服务器
nohup /Users/mac/.npm-global/bin/appium --relaxed-security > /tmp/appium.log 2>&1 &

# 构建并安装最新 iOS App 到模拟器
xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,id=7910EBEA-1F8E-47B3-9AF4-7A30F48407C9' -quiet
xcrun simctl terminate booted com.folio.app
xcrun simctl install booted /Users/mac/Library/Developer/Xcode/DerivedData/Folio-doibwjteeqeddrcbskywtleokllf/Build/Products/Debug-iphonesimulator/Folio.app
xcrun simctl launch booted com.folio.app
```

连接模板（Python）：
```python
from appium import webdriver
from appium.options.ios import XCUITestOptions

options = XCUITestOptions()
options.platform_name = "iOS"
options.device_name = "iPhone 17 Pro"
options.udid = "7910EBEA-1F8E-47B3-9AF4-7A30F48407C9"
options.bundle_id = "com.folio.app"
options.no_reset = True
options.set_capability("appium:automationName", "XCUITest")
options.set_capability("appium:usePreinstalledApp", True)

driver = webdriver.Remote("http://localhost:4723", options=options)
```

注意事项：
- 每次 `webdriver.Remote()` 会创建新会话（重启 WDA），约需 5 秒
- `xcrun simctl install` 替换 bundle 但不会重启运行中的进程——必须先 `terminate` 再 `launch`
- Reader 页面返回按钮名称是 `chevron.left`（非 `BackButton`），Home 页从设置返回是 `BackButton`

## 关键设计决策

- **本地优先**：所有用户内容存储在设备上；仅 AI 处理时将内容发送到服务器
- **离线优先保存**：Share Extension 立即将 URL + 元数据写入本地 SwiftData，然后尝试客户端内容提取（ContentExtractor 管线）；后端处理在网络可用时异步进行
- **单次 AI 调用**：分类 + 标签 + 摘要在一次 DeepSeek API 请求中完成，提高效率
- **AI 模型**：DeepSeek Chat (deepseek-chat) 用于分类/摘要；置信度阈值 70%
- **内容来源优先级**：P0 = 博客、微信公众号、Twitter/X；P1 = 知乎、微博；P2 = Newsletter、YouTube
- **微信特殊处理**：代理抓取、防盗链图片转存
- **订阅等级**：Free（30 次/月）、Pro（¥68/年）、Pro+（¥128/年）
- **不做清单**：不做笔记编辑器、不做批量编辑、不做多级文件夹、不做 RSS、不做社交功能、不做推荐

## 构建命令

| 项目 | 命令 |
|------|------|
| 开发一键启动（全容器） | `cd server && ./scripts/dev-start.sh` |
| 开发栈重建（代码改动后） | `cd server && docker compose -f docker-compose.local.yml up --build -d app` |
| 开发栈全量重建 | `cd server && ./scripts/deploy-local.sh rebuild` |
| Go 服务器（本地构建） | `cd server && go build -o folio-server ./cmd/server` |
| Reader 服务（本地构建） | `cd server/reader-service && npm run build` |
| iOS（Xcode） | 打开 `ios/Folio.xcodeproj`，选择 Folio scheme，Cmd+R |
| iOS（命令行构建 - 模拟器） | `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'` |
| iOS（命令行构建 - 真机） | `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'id=00008130-000A61483EC0001C' -allowProvisioningUpdates` |
| XcodeGen 重新生成 | `cd ios && xcodegen generate` |
| Docker 生产环境 | `cd server && docker compose up -d` |

## 语言与国际化

文档使用中文。产品面向全球用户（中英双语）。AI 输出语言与文章语言匹配。iOS 应用本地化支持 en + zh-Hans。
