# Folio MVP 全栈任务规划

> 版本：2.0
> 创建日期：2026-02-20
> 最后更新：2026-02-20
> ⚠️ 本文档包含 [28 个待解决问题](#待解决问题清单)，需在对应任务开始前逐一处理
> 📐 本文档采用 [双 Agent 并行执行计划](#双-agent-并行执行计划)，iOS + Backend 两条轨道并行推进
> 关联文档：[PRD](design/prd.md) | [系统架构](architecture/system-design.md) | [交互流程](interaction/core-flows.md)

---

## 使用说明

本文档包含 Folio MVP 从零到上线的全部开发任务，拆分给 **2 个 Agent** 并行执行。

**任务 ID 规则**：`M{里程碑}-E{模块}-T{任务}`

**执行模式**：双 Agent 并行。每个 Agent 严格按照[并行执行计划](#双-agent-并行执行计划)中的阶段和顺序执行任务。跨 Agent 仅在标注的同步点对齐。

**Agent 分工**：

| | Agent iOS | Agent Backend |
|---|-----------|---------------|
| **技术栈** | Swift 5.9+ / SwiftUI / SwiftData / SQLite FTS5 / iOS 17+ | Go 1.22+ / chi / asynq / pgx / PostgreSQL 16+ / Python 3.12+ / FastAPI / Node.js / Docker |
| **工作目录** | `ios/` | `server/` |
| **任务数** | 50 | 22 + 补充任务 |
| **里程碑** | M0-E1/E6, M1-E1/E2, M2, M3, M4, M5, M7, M8(iOS部分) | M0-E2/E3/E4/E5, M1-E3, M6, M8-E2-T3 |

---

## 自验证协议

**每个任务必须通过全部测试才算完成。** 每个任务包含 `**测试**` 段落，定义了该任务必须编写的测试用例和验证命令。

### 执行闭环

```
实现代码 → 编写测试 → 执行验证命令 → 失败则修复代码 → 重新执行 → 全部 PASS → 任务完成
```

### 测试策略矩阵

| 任务类型 | 测试方式 | 验证命令 | 覆盖度要求 |
|---------|---------|---------|-----------|
| iOS 数据层 / 业务逻辑 | XCTest 单元测试（内存 SwiftData 容器） | `xcodebuild test -scheme Folio -only-testing:FolioTests/{TestClass}` | 每个公开方法 100% 覆盖 |
| iOS UI 组件 | SwiftUI `#Preview` + 编译检查 | `xcodebuild build -scheme Folio` + Preview 不 crash | 每个组件至少 3 个 Preview（正常态/边界态/Dark） |
| iOS ViewModel | XCTest 单元测试（Mock Repository） | `xcodebuild test -scheme Folio -only-testing:FolioTests/{TestClass}` | 每个公开方法 100% 覆盖 |
| Go 后端 Domain/Service | `go test` 单元测试 | `cd server && go test ./internal/{pkg}/... -v -count=1` | 每个公开方法 100% 覆盖 |
| Go 后端 Repository | `go test` + testcontainers（临时 PostgreSQL） | `cd server && go test ./internal/repository/... -v -count=1` | 每个 CRUD 方法 100% 覆盖 |
| Go 后端 Handler | `go test` + `net/http/httptest` | `cd server && go test ./internal/api/... -v -count=1` | 每个接口正常 + 错误路径覆盖 |
| Python AI 服务 | `pytest`（Mock Claude API） | `cd server/ai-service && pytest -v --tb=short` | 每个公开方法 100% 覆盖 |
| Node.js Reader 服务 | 编译检查 + 健康检查 | `cd server/reader-service && npm run build && npm test` | 端点可达性 |
| 基础设施 / Docker | 健康检查脚本 | `cd server && bash scripts/healthcheck.sh` | 全部服务 200 OK |
| 端到端集成 | Bash 集成测试脚本 | `cd server && bash scripts/e2e-test.sh` | 核心链路覆盖 |

### 测试文件命名约定

| 语言 | 测试文件位置 | 命名 |
|------|------------|------|
| Swift | `ios/FolioTests/{被测类名}Tests.swift` | `class ArticleRepositoryTests: XCTestCase` |
| Go | 与源码同目录 `{source}_test.go` | `func TestArticleRepo_Create(t *testing.T)` |
| Python | `server/ai-service/tests/test_{module}.py` | `def test_pipeline_validates_category():` |
| Node.js | `server/reader-service/src/__tests__/` | `describe("POST /scrape")` |

### 关键原则

1. **测试先于任务完成**：没有通过验证命令的任务不算完成
2. **每个公开方法都有测试**：100% 方法覆盖度，包括正常路径和错误路径
3. **测试要快速可靠**：使用内存数据库、Mock 外部服务、testcontainers，不依赖远程 API
4. **失败后修复再跑**：验证命令失败 → 读错误信息 → 修复代码 → 再次运行 → 直到全部 PASS

---

## 双 Agent 并行执行计划

### 总览

```
          Phase 1               Phase 2                   Phase 3          Phase 4
        项目初始化+基座         核心功能                   前后端对接        上线打磨
       ┌────────────┐    ┌──────────────────────┐    ┌───────────┐    ┌───────────┐
 iOS   │ 11 任务    │    │ 24 任务              │    │ 7 任务    │    │ 8 任务    │
 Agent │ M0-E1/E6   │───▶│ M2 + M3 + M4 + M5   │───▶│ M7        │───▶│ M8 iOS    │
       │ M1-E1/E2   │    │                      │    │           │    │           │
       └────────────┘    └──────────────────────┘    └─────┬─────┘    └───────────┘
                                                           │
                                                      ★ 同步点 S2
                                                           │
       ┌────────────┐    ┌──────────────────────┐    ┌─────┴─────┐    ┌───────────┐
  Back │ 9 任务     │    │ 12 任务 + 补充任务   │    │ 联调协助  │    │ 1 + 补充  │
 Agent │ M0-E2~E5   │───▶│ M6                   │───▶│ E2E 测试  │───▶│ M8 后端   │
       │ M1-E3      │    │ (约提前 12 任务完成)  │    │           │    │           │
       └────────────┘    └──────────────────────┘    └───────────┘    └───────────┘
```

### 跨 Agent 同步协议

两个 Agent 在各自工作目录（`ios/` 和 `server/`）内独立工作，**不存在文件冲突**。仅在以下节点需要对齐：

| 同步点 | 时机 | 交付物 | 说明 |
|--------|------|--------|------|
| **S1: API 契约** | Phase 1 结束时 | Backend 输出所有 API 端点的 JSON Schema，iOS 确认模型映射 | 确保请求/响应格式、`categories` 的 slug 值、错误码定义双方一致 |
| **S2: 联调启动** | Phase 2 双方完成 | Backend：`docker compose up` 全部服务可用；iOS：Mock 数据可切换为真实 API | Phase 3 的进入条件，缺一不可 |
| **S3: E2E 验收** | Phase 3 结束时 | `scripts/e2e-test.sh` 全部 PASS | 分享链接 → 抓取 → AI → 同步回 iOS → 搜索可达 全链路跑通 |

---

### Phase 1: 项目初始化 + 基座层

> 两个 Agent 同时启动，各自搭建项目骨架和基础设施。Phase 结束时执行 S1 同步。

#### Agent iOS — Phase 1（11 任务）

| # | 任务 ID | 任务名称 | Phase 内前置 |
|---|---------|---------|-------------|
| 1 | M0-E1-T1 | 创建 Xcode 项目 | — |
| 2 | M0-E1-T2 | 配置 SPM 依赖 | #1 |
| 3 | M0-E1-T3 | 建立 iOS 目录结构 | #1 |
| 4 | M0-E6-T1 | 国际化配置 | #3 |
| 5 | M1-E1-T1 | 颜色系统 | #3 |
| 6 | M1-E1-T2 | 字体系统 | #3 |
| 7 | M1-E1-T3 | 间距和圆角系统 | #3 |
| 8 | M1-E2-T1 | SwiftData 模型定义 | #3 |
| 9 | M1-E1-T4 | 通用 UI 组件 | #5 #6 #7 |
| 10 | M1-E2-T2 | SwiftData 容器配置 | #8 |
| 11 | M1-E2-T3 | Repository 层 | #10 |

**推荐执行顺序**：

```
#1 → #2, #3（顺序）
   → #4, #5, #6, #7, #8（#3 完成后这 5 个无互相依赖，顺序做）
   → #9（等 #5#6#7）, #10（等 #8）
   → #11（等 #10）
```

**Phase 1 完成标志**：
- `xcodebuild build -scheme Folio` 成功
- `xcodebuild test -scheme Folio` 全部通过（ModelTests, RepositoryTests, DesignSystem tests）
- `Color.folio.xxx`、`Typography.xxx`、`Spacing.xxx` 可用
- SwiftData 内存容器可创建 Article/Tag/Category，Repository CRUD 全部通过

---

#### Agent Backend — Phase 1（9 任务）

| # | 任务 ID | 任务名称 | Phase 内前置 |
|---|---------|---------|-------------|
| 1 | M0-E2-T1 | 初始化 Go 项目 | — |
| 2 | M0-E3-T1 | 初始化 Python AI 服务 | — |
| 3 | M0-E4-T1 | 初始化 Reader HTTP 服务 | — |
| 4 | M0-E2-T2 | 添加 Go 核心依赖 | #1 |
| 5 | M0-E5-T1 | Docker Compose 配置 | #1 #2 #3 |
| 6 | M0-E2-T3 | Go 配置管理 | #4 |
| 7 | M0-E5-T2 | PostgreSQL 初始化迁移 | #5 |
| 8 | M1-E3-T1 | Go Domain 模型 | #4 |
| 9 | M1-E3-T2 | Go Repository 层 | #7 #8 |

**推荐执行顺序**：

```
#1 → #2 → #3 → #4 → #5
   → #6, #7, #8（#5 完成后这 3 个无互相依赖，顺序做）
   → #9（等 #7 + #8）
```

**Phase 1 完成标志**：
- `go build ./cmd/server` 成功，`/health` 返回 200
- `docker compose up postgres redis` 正常，迁移脚本执行成功
- Python AI 服务 `/health` 返回 200
- Reader 服务 `/health` 返回 200
- Go Repository 全部测试通过（testcontainers）

---

#### 同步点 S1: API 契约对齐

Phase 1 双方完成后，对齐以下内容：

1. **API 端点列表**：Backend Agent 输出所有端点的请求/响应 JSON Schema
2. **分类 slug 映射**：确认 9 条预置分类的 slug（如 `tech`、`product`、`business`…）在 iOS Category 模型和 PostgreSQL categories 表中一致
3. **错误码约定**：400/401/403/404/409/429/500 的 JSON 格式
4. **字段命名约定**：确认 snake_case (API) ↔ camelCase (iOS) 自动转换规则

---

### Phase 2: 核心功能（最长阶段）

> iOS 开发 App 四大功能模块（收藏库/收藏入口/阅读/搜索），Backend 开发全部 API 和 Worker。
> Backend 预计比 iOS 提前完成，空闲期执行补充任务。

#### Agent iOS — Phase 2（24 任务）

Phase 1 完成后，M2/M3/M4/M5 四条链路入口均已解锁。以下顺序**优先完成 M7 前置依赖**（⚡ 标记）：

| # | 任务 ID | 任务名称 | 前置 | 说明 |
|---|---------|---------|------|------|
| 1 | M2-E3-T1 | 文章卡片组件 | — | M2 入口 |
| 2 | M2-E1-T1 | 三 Tab 导航框架 | — | App 骨架 |
| 3 | M2-E2-T1 | Mock 数据工厂 | — | 后续 UI 开发依赖 |
| 4 | M2-E3-T2 | 收藏库列表视图 | #1 #3 | 核心列表 |
| 5 | M2-E3-T3 | 空状态视图 | — | 独立 |
| 6 | ⚡ M3-E4-T1 | 离线队列管理器 | — | **M7-E3-T1 前置** |
| 7 | ⚡ M3-E2-T1 | Share Extension 核心 | — | **M7 前置链路** |
| 8 | M3-E2-T2 | 月度配额检查 | #7 | |
| 9 | ⚡ M3-E1-T1 | 欢迎引导页 | — | **M7-E2-T1 前置** |
| 10 | ⚡ M3-E1-T2 | 通知权限请求 | #9 | **M7-E4-T2 前置** |
| 11 | M3-E3-T1 | 剪贴板检测 | — | |
| 12 | ⚡ M5-E1-T1 | FTS5 索引管理 | — | **M7-E3-T1 前置** |
| 13 | M5-E1-T2 | 全文搜索查询 | #12 | |
| 14 | M5-E2-T1 | 搜索页面 | #13 | |
| 15 | M4-E1-T1 | Markdown 渲染引擎 | — | M4 入口 |
| 16 | M4-E1-T2 | 图片查看器 | #15 | |
| 17 | M4-E2-T1 | 阅读页视图 | #15 | |
| 18 | M4-E2-T2 | 原文 WebView | #17 | |
| 19 | M4-E3-T1 | 阅读偏好设置 | #17 | |
| 20 | M4-E4-T1 | 阅读进度追踪 | #17 | |
| 21 | M2-E4-T1 | 分类筛选条 | #4 | 不阻塞 M7 |
| 22 | M2-E4-T2 | 标签筛选 | #21 | 不阻塞 M7 |
| 23 | M2-E5-T1 | 时间线视图 | #4 | 不阻塞 M7 |
| 24 | M2-E6-T1 | 列表手势操作 | #4 | 不阻塞 M7 |

**执行策略说明**：

- **#1~#5**（M2 基础）先行：建立 App 可视化骨架，方便后续开发直接看到效果
- **#6~#12**（M3 + M5 关键路径）紧随：这些是 M7 的硬前置，越早完成越好
- **#15~#20**（M4 阅读）中段：独立模块，与 M2/M3/M5 无依赖
- **#21~#24**（M2 增强）末段：筛选/时间线/手势是锦上添花，不阻塞 M7

**提前启动 M7-E1 的机会**：M7-E1-T1（APIClient）仅依赖 M0-E1-T2（Phase 1 已完成）。如果 iOS Agent 在 Phase 2 后期尚有余力，可提前开始 M7-E1-T1 和 M7-E1-T2，缩短 Phase 3 关键路径。

---

#### Agent Backend — Phase 2（12 任务 + 补充任务）

| # | 任务 ID | 任务名称 | Phase 内前置 |
|---|---------|---------|-------------|
| 1 | M6-E5-T1 | Reader 服务客户端（Go） | — |
| 2 | M6-E5-T2 | AI 服务集成（Go 客户端 + Python 完整实现） | — |
| 3 | M6-E1-T1 | chi 路由 + 中间件 | — |
| 4 | M6-E6-T1 | Caddy 反向代理配置 | — |
| 5 | M6-E4-T1 | asynq Worker 框架 | #3 |
| 6 | M6-E2-T1 | Apple ID 登录接口 | #3 |
| 7 | M6-E2-T2 | 用户信息 + 配额接口 | #6 |
| 8 | M6-E3-T1 | 文章 CRUD 接口 | #3 #7 |
| 9 | M6-E3-T2 | 标签和分类接口 | #8 |
| 10 | M6-E4-T2 | 抓取任务 Handler | #5 #1 |
| 11 | M6-E4-T3 | AI 处理任务 Handler | #5 #2 |
| 12 | M6-E4-T4 | 图片转存任务 Handler | #5 |

**推荐执行顺序**：

```
#1, #2 先行（外部服务客户端，无需等 API 框架）
→ #3 → #4
→ #5, #6（#3 完成后并行入口）
→ #7 → #8 → #9
→ #10（等 #5 + #1）, #11（等 #5 + #2）, #12（等 #5）
```

##### Backend 空闲期：补充任务

Backend Agent 预计比 iOS Agent 早约 12 个任务完成 Phase 2。空闲期执行以下补充工作，按优先级排列：

| 优先级 | 补充任务 | 产出 | 关联 |
|--------|---------|------|------|
| **P0** | 补全 M6-E5-T1/T2 测试 | Reader/AI 客户端和服务的单元测试 | Issue-14 |
| **P0** | 编写 E2E 集成测试脚本 | `server/scripts/e2e-test.sh` | Issue-28 |
| **P0** | 编写 API 契约文档 | `docs/api-contract.md`（OpenAPI 格式） | S1 同步点 |
| **P1** | 后端搜索 API | `GET /api/v1/articles/search`（PostgreSQL `tsvector`） | Issue-06 |
| **P1** | Docker 生产配置 | `docker-compose.prod.yml`、多阶段构建优化 | — |
| **P1** | 数据库迁移执行策略 | 自动迁移脚本 + 版本管理文档 | Issue-23 |
| **P2** | App Store Server 通知 Webhook | `POST /api/v1/webhook/appstore`（续订/退款回调） | Issue-21 |
| **P2** | 后端性能基线 | 压测脚本（100 并发提交文章） | M8-E6 |

---

### Phase 3: 前后端对接（同步点 S2 → S3）

> **进入条件**：iOS Phase 2 全部完成 **且** Backend Phase 2 全部完成。
> 此阶段两个 Agent 需要密切协作。

#### Agent iOS — Phase 3（7 任务）

| # | 任务 ID | 任务名称 | 前置 |
|---|---------|---------|------|
| 1 | M7-E1-T1 | APIClient 实现 | — (如已在 Phase 2 提前完成则跳过) |
| 2 | M7-E1-T2 | 请求/响应模型 | #1 |
| 3 | M7-E2-T1 | Sign in with Apple 全链路 | #2 + Backend M6-E2-T1 |
| 4 | M7-E3-T1 | 文章提交 + 结果同步 | #2 |
| 5 | M7-E3-T2 | 图片下载到本地 | #4 |
| 6 | M7-E4-T1 | 后台任务处理 | #4 |
| 7 | M7-E4-T2 | 本地通知 | #4 |

**执行顺序**：#1 → #2 → #3, #4（#2 完成后两者可顺序执行）→ #5, #6, #7（#4 完成后三者无互相依赖）

---

#### Agent Backend — Phase 3

Backend 核心 API 已在 Phase 2 完成。此阶段职责：

1. **启动完整后端环境**：`docker compose up`，确保全部服务健康
2. **联调支持**：排查 iOS 对接过程中的 API 问题（格式调整、错误码修正、超时调优）
3. **监控 Worker 日志**：观察 asynq 任务处理日志，修复集成 Bug
4. **运行 E2E 测试**：持续运行 `scripts/e2e-test.sh`，确保链路不退化

---

#### 同步点 S3: 端到端验收

Phase 3 完成标准（全部通过才可进入 Phase 4）：

- [ ] **核心链路**：iOS Share Extension 分享链接 → 后端抓取 + AI 处理 → iOS 列表显示完整文章（标题、摘要、标签、分类）
- [ ] **Apple 登录**：iOS Apple ID 登录 → 后端验证 → 返回 JWT → 后续 API 调用正常
- [ ] **搜索联通**：后端处理完成的文章 → FTS5 索引更新 → iOS 搜索可搜到
- [ ] **离线恢复**：iOS 离线保存 → 恢复联网 → 自动提交处理 → 结果同步回本地
- [ ] **通知推送**：后台处理完成 → iOS 收到本地通知 → 点击通知跳转到文章
- [ ] **E2E 脚本**：`scripts/e2e-test.sh` 全部 PASS

---

### Phase 4: 上线打磨

> 两个 Agent 再次并行。iOS 做设置/订阅/无障碍/性能，Backend 做订阅验证和部署准备。

#### Agent iOS — Phase 4（8 任务）

| # | 任务 ID | 任务名称 |
|---|---------|---------|
| 1 | M8-E1-T1 | 设置页面 |
| 2 | M8-E2-T1 | StoreKit 2 订阅实现 |
| 3 | M8-E2-T2 | 订阅页面 UI |
| 4 | M8-E3-T1 | 功能门控 |
| 5 | M8-E4-T1 | VoiceOver + Dynamic Type |
| 6 | M8-E5-T1 | 暗色模式全面适配 |
| 7 | M8-E6-T1 | 性能达标审查 |
| 8 | M8-E7-T1 | App Store 素材准备 |

**推荐执行顺序**：#1 → #2 → #3 → #4（订阅链路优先）→ #5 → #6（无障碍 + 暗色适配）→ #7 → #8

---

#### Agent Backend — Phase 4（1 任务 + 补充）

| 任务 | 说明 |
|------|------|
| **M8-E2-T3** | 后端订阅验证接口（`POST /api/v1/subscription/verify`） |
| 全链路压测 | 模拟 100 用户并发提交文章，验证 Worker 稳定性 |
| 生产部署检查清单 | HTTPS 证书、环境变量审计、数据库备份策略、监控告警 |
| 安全审计 | SQL 注入、JWT 配置、CORS 策略、限流阈值验证 |
| 生产 Docker 配置 | `docker-compose.prod.yml` 最终调优、资源限制 |

---

### 任务所有权速查表

下表列出全部任务的 Agent 归属，便于快速查找：

| Agent iOS（50 任务） | Agent Backend（22 任务） |
|---------------------|------------------------|
| M0-E1-T1, T2, T3 | M0-E2-T1, T2, T3 |
| M0-E6-T1 | M0-E3-T1 |
| M1-E1-T1, T2, T3, T4 | M0-E4-T1 |
| M1-E2-T1, T2, T3 | M0-E5-T1, T2 |
| M2-E1-T1 | M1-E3-T1, T2 |
| M2-E2-T1 | M6-E1-T1 |
| M2-E3-T1, T2, T3 | M6-E2-T1, T2 |
| M2-E4-T1, T2 | M6-E3-T1, T2 |
| M2-E5-T1 | M6-E4-T1, T2, T3, T4 |
| M2-E6-T1 | M6-E5-T1, T2 |
| M3-E1-T1, T2 | M6-E6-T1 |
| M3-E2-T1, T2 | M8-E2-T3 |
| M3-E3-T1 | |
| M3-E4-T1 | |
| M4-E1-T1, T2 | |
| M4-E2-T1, T2 | |
| M4-E3-T1 | |
| M4-E4-T1 | |
| M5-E1-T1, T2 | |
| M5-E2-T1 | |
| M7-E1-T1, T2 | |
| M7-E2-T1 | |
| M7-E3-T1, T2 | |
| M7-E4-T1, T2 | |
| M8-E1-T1 | |
| M8-E2-T1, T2 | |
| M8-E3-T1 | |
| M8-E4-T1 | |
| M8-E5-T1 | |
| M8-E6-T1 | |
| M8-E7-T1 | |

---

### 风险与应对

| 风险 | 影响 | 应对措施 |
|------|------|---------|
| **iOS 是关键路径**：50 任务远多于 Backend 22 任务 | 整体进度取决于 iOS Agent 速度 | Backend 空闲期提前完成补充任务（E2E 测试、API 文档）；iOS Phase 2 中优先做 M7 前置 |
| **Phase 3 联调发现接口不匹配** | 返工修改 API 格式或 iOS 模型 | S1 同步点提前对齐 API 契约；iOS 使用 `APIEndpoint` 枚举集中管理所有 URL |
| **FTS5 直接操作 SQLite 风险**（Issue-13） | 可能与 SwiftData 冲突 | Phase 1 结束时做技术 Spike 验证，失败则改用独立 SQLite 文件 |
| **Backend 等待 iOS 进入 Phase 3 时间过长** | Backend Agent 闲置浪费 | 用补充任务列表填充空闲期，优先级 P0 → P1 → P2 |

---

## M0: 项目初始化

### E1: iOS 项目

#### M0-E1-T1: 创建 Xcode 项目

**描述**：创建 Folio iOS 项目，包含 Main App Target 和 Share Extension Target。配置 App Group（`group.com.folio.app`）用于主 App 和 Extension 共享数据。设置最低部署目标 iOS 17.0。配置 Bundle Identifier（`com.folio.app` 和 `com.folio.app.share-extension`）。

**前置**：无

**产出**：
- `ios/Folio.xcodeproj`
- `ios/Folio/FolioApp.swift`
- `ios/Folio/ContentView.swift`
- `ios/Folio/Info.plist`
- `ios/ShareExtension/ShareViewController.swift`
- `ios/ShareExtension/Info.plist`

**验收**：
- Xcode 项目可编译运行，Simulator 显示空白 App
- Share Extension Target 存在并可编译
- App Group `group.com.folio.app` 已配置在两个 Target 的 Capabilities 中
- Signing & Capabilities 中已启用 Sign in with Apple、Push Notifications、Background Modes

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

#### M0-E1-T2: 配置 Swift Package 依赖

**描述**：通过 Swift Package Manager 添加项目所需依赖：
- `swift-markdown`（Apple 官方 Markdown 解析库）
- `Nuke`（高性能图片加载和缓存）
- `KeychainAccess`（Keychain 封装，存储 JWT Token）

**前置**：M0-E1-T1

**产出**：
- `ios/Folio.xcodeproj/project.pbxproj`（更新依赖）
- `ios/Folio.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`

**验收**：
- 所有 Package 解析成功，项目可编译
- 在代码中可 `import Markdown`、`import Nuke`、`import KeychainAccess`

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

#### M0-E1-T3: 建立 iOS 目录结构

**描述**：按 MVVM + Clean Architecture 建立目录结构（参考架构文档 2.1 节）。创建空的占位文件确保目录结构存在。

```
ios/Folio/
├── App/
│   ├── FolioApp.swift
│   └── AppDelegate.swift
├── Presentation/
│   ├── Home/
│   ├── Search/
│   ├── Reader/
│   ├── Settings/
│   ├── Onboarding/
│   └── Components/
├── Domain/
│   ├── Models/
│   └── UseCases/
├── Data/
│   ├── SwiftData/
│   ├── Repository/
│   ├── Network/
│   ├── Search/
│   └── KeyChain/
├── Utils/
│   └── Extensions/
└── Resources/
    ├── Assets.xcassets
    └── Localizable.xcstrings
```

**前置**：M0-E1-T1

**产出**：上述目录结构中的空占位文件

**验收**：
- 目录结构清晰，项目仍可编译
- 每个子目录包含至少一个占位 `.swift` 文件

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E2: Go 后端项目

#### M0-E2-T1: 初始化 Go 项目

**描述**：创建 Go 后端项目，执行 `go mod init`（module 名 `folio-server`）。按架构文档 3.2 节建立完整目录结构。创建 `cmd/server/main.go` 入口文件，包含最小化的 HTTP 服务器（监听 8080，`/health` 返回 `{"status":"ok"}`）。

**前置**：无

**产出**：
```
server/
├── cmd/server/main.go
├── internal/
│   ├── api/
│   │   ├── router.go
│   │   ├── middleware/
│   │   └── handler/
│   ├── domain/
│   ├── service/
│   ├── repository/
│   ├── worker/
│   ├── client/
│   └── config/
├── migrations/
├── go.mod
└── go.sum
```

**验收**：
- `go build ./cmd/server` 成功
- `go run ./cmd/server` 启动后 `curl localhost:8080/health` 返回 `{"status":"ok"}`

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd server && go build ./cmd/server 2>&1 | tail -3
# 期望：无错误输出，生成 server 二进制
```

---

#### M0-E2-T2: 添加 Go 核心依赖

**描述**：`go get` 安装以下核心依赖：
- `github.com/go-chi/chi/v5`（路由）
- `github.com/go-chi/cors`（CORS）
- `github.com/hibiken/asynq`（异步任务队列）
- `github.com/jackc/pgx/v5`（PostgreSQL 驱动）
- `github.com/redis/go-redis/v9`（Redis 客户端）
- `github.com/golang-jwt/jwt/v5`（JWT）
- `github.com/aws/aws-sdk-go-v2`（R2/S3 客户端）
- `github.com/kelseyhightower/envconfig`（环境变量配置）
- `github.com/golang-migrate/migrate/v4`（数据库迁移）

**前置**：M0-E2-T1

**产出**：
- `server/go.mod`（更新）
- `server/go.sum`（更新）

**验收**：
- `go mod tidy` 无错误
- `go build ./cmd/server` 成功

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd server && go build ./cmd/server 2>&1 | tail -3
# 期望：无错误输出，编译成功
```

---

#### M0-E2-T3: Go 配置管理

**描述**：实现配置加载模块 `internal/config/config.go`，使用 `envconfig` 从环境变量加载配置。配置项包括：
- `DATABASE_URL`：PostgreSQL 连接串
- `REDIS_ADDR`：Redis 地址
- `READER_URL`：Reader 服务地址
- `AI_SERVICE_URL`：AI 服务地址
- `JWT_SECRET`：JWT 签名密钥
- `R2_ENDPOINT`、`R2_ACCESS_KEY`、`R2_SECRET_KEY`：Cloudflare R2
- `SERVER_PORT`：HTTP 端口，默认 8080

同时创建 `server/.env.example` 列出所有配置项及说明。

**前置**：M0-E2-T2

**产出**：
- `server/internal/config/config.go`
- `server/.env.example`

**验收**：
- 缺少必要环境变量时启动报错并提示缺少哪些变量
- 设置环境变量后可正常加载

**测试**：
测试文件：`server/internal/config/config_test.go`
测试用例：
- `TestLoad_AllFieldsSet()` — 设置全部环境变量，验证 Config 结构体字段值正确
- `TestLoad_DefaultPort()` — 不设置 SERVER_PORT，验证默认值 8080
- `TestLoad_MissingRequired()` — 不设置 DATABASE_URL，验证返回错误
- `TestLoad_MissingJWTSecret()` — 不设置 JWT_SECRET，验证返回错误

验证命令：
```bash
cd server && go test ./internal/config/... -v -count=1 2>&1 | tail -10
# 期望：PASS ok folio-server/internal/config
```

---

### E3: Python AI 服务

#### M0-E3-T1: 初始化 Python AI 服务项目

**描述**：创建 FastAPI 项目。包含 `main.py` 入口、`/health` 端点。使用 `uvicorn` 启动，监听 8000 端口。创建 `requirements.txt`，包含：`fastapi`、`uvicorn[standard]`、`anthropic`、`redis`、`pydantic`。创建 `Dockerfile`（基于 `python:3.12-slim`）。

**前置**：无

**产出**：
```
server/ai-service/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── models.py
│   ├── pipeline.py
│   ├── cache.py
│   └── prompts/
│       ├── __init__.py
│       └── combined.py
├── requirements.txt
└── Dockerfile
```

**验收**：
- `pip install -r requirements.txt` 成功
- `uvicorn app.main:app` 启动后 `curl localhost:8000/health` 返回 `{"status":"ok"}`
- Docker 构建成功

**测试**：
测试文件：`server/ai-service/tests/test_health.py`
测试用例：
- `test_health_endpoint_returns_ok()` — GET /health 返回 200 + `{"status":"ok"}`
- `test_app_starts_without_error()` — FastAPI app 实例创建成功

验证命令：
```bash
cd server/ai-service && pip install -r requirements.txt -q && pytest tests/test_health.py -v --tb=short 2>&1 | tail -5
# 期望：passed
cd server/ai-service && docker build -t folio-ai-test . 2>&1 | tail -3
# 期望：Successfully tagged folio-ai-test
```

---

### E4: Reader 抓取服务

#### M0-E4-T1: 初始化 Reader HTTP 包装服务

**描述**：创建 Node.js 项目，薄包装 `@vakra-dev/reader`（参考架构文档 3.3.2 节）。使用 Express 暴露 `POST /scrape` 和 `GET /health`。`POST /scrape` 接收 `{url, timeout_ms}`，调用 Reader 进行抓取，返回 `{markdown, metadata, duration_ms}`。创建 `Dockerfile`。使用 TypeScript 编写。

**前置**：无

**产出**：
```
server/reader-service/
├── src/
│   └── index.ts
├── package.json
├── tsconfig.json
└── Dockerfile
```

**验收**：
- `npm install` 成功
- `npm run dev` 启动后 `curl localhost:3000/health` 返回 `{"status":"ok"}`
- Docker 构建成功

**测试**：
测试文件：`server/reader-service/src/__tests__/health.test.ts`
测试用例：
- `describe("GET /health")` — 验证返回 200 + `{"status":"ok"}`
- `describe("POST /scrape")` — 验证缺少 url 参数时返回 400

验证命令：
```bash
cd server/reader-service && npm install && npm run build 2>&1 | tail -3
# 期望：编译无错误
cd server/reader-service && npm test 2>&1 | tail -5
# 期望：Tests passed
```

---

### E5: 基础设施

#### M0-E5-T1: Docker Compose 配置

**描述**：创建 `docker-compose.yml`，定义以下服务（参考架构文档 6.2 节）：
- `postgres`：PostgreSQL 16-alpine，端口 5432，数据持久化到 volume
- `redis`：Redis 7-alpine，端口 6379，maxmemory 256mb
- `caddy`：Caddy 2.7-alpine，端口 80/443
- `api`：Go 服务，端口 8080，依赖 postgres、redis
- `reader`：Reader 服务，端口 3000
- `ai`：AI 服务，端口 8000，依赖 redis

创建 `.env.example`，创建 `Caddyfile`（开发阶段直接反向代理到 api:8080）。

**前置**：M0-E2-T1, M0-E3-T1, M0-E4-T1

**产出**：
- `server/docker-compose.yml`
- `server/.env.example`（如已存在则合并）
- `server/Caddyfile`
- `server/Dockerfile`（Go 多阶段构建）

**验收**：
- `docker compose up postgres redis` 启动成功，PostgreSQL 和 Redis 可连接
- 所有服务容器可独立构建

**测试**：
测试文件：`server/scripts/healthcheck.sh`
测试用例：
- 验证 PostgreSQL 容器启动并接受连接（`pg_isready`）
- 验证 Redis 容器启动并响应 PING（`redis-cli ping`）
- 验证 docker-compose.yml 语法正确（`docker compose config`）

验证命令：
```bash
cd server && docker compose config --quiet 2>&1 | tail -3
# 期望：无错误输出
cd server && docker compose up -d postgres redis && sleep 5 && docker compose exec postgres pg_isready && docker compose exec redis redis-cli ping && docker compose down 2>&1 | tail -5
# 期望：accepting connections + PONG
```

---

#### M0-E5-T2: PostgreSQL 初始化迁移脚本

**描述**：创建数据库初始化迁移文件，包含架构文档 4.2 节定义的全部建表语句：`users`、`articles`、`categories`（含预置分类数据 9 条）、`tags`、`article_tags`、`crawl_tasks`、`activity_logs`，以及所有索引、`updated_at` 触发器。同时创建 down 迁移（drop 所有表）。

**前置**：M0-E5-T1

**产出**：
- `server/migrations/001_init.up.sql`
- `server/migrations/001_init.down.sql`

**验收**：
- `docker compose up postgres` 后手动执行 up.sql，所有表创建成功
- 执行 down.sql 后所有表删除
- `\dt` 显示 6 张表，`SELECT * FROM categories` 返回 9 条预置分类

**测试**：
测试文件：`server/scripts/test-migration.sh`
测试用例：
- 执行 up.sql 后验证所有表存在（users、articles、categories、tags、article_tags、crawl_tasks、activity_logs）
- 验证 categories 表有 9 条预置数据
- 执行 down.sql 后验证所有表已删除

验证命令：
```bash
cd server && docker compose up -d postgres && sleep 3 && \
  docker compose exec -T postgres psql -U folio -d folio -f /migrations/001_init.up.sql && \
  docker compose exec -T postgres psql -U folio -d folio -c "SELECT count(*) FROM categories;" && \
  docker compose exec -T postgres psql -U folio -d folio -f /migrations/001_init.down.sql && \
  docker compose down 2>&1 | tail -5
# 期望：CREATE TABLE（多次）、count = 9、DROP TABLE（多次）
```

---

### E6: 国际化基础

#### M0-E6-T1: iOS 国际化配置

**描述**：配置 Xcode String Catalog（`Localizable.xcstrings`），添加中文（zh-Hans）和英文（en）两种语言。预填基础 UI 文案（参考交互文档十四节）：
- App 名称：Folio · 页集 / Folio
- Tab 名称：收藏/Library、搜索/Search、设置/Settings
- 空状态文案
- Share Extension 文案
- 通用按钮文案（取消/Cancel、确定/OK、删除/Delete、重试/Retry）

**前置**：M0-E1-T3

**产出**：
- `ios/Folio/Resources/Localizable.xcstrings`
- `ios/Folio/Resources/InfoPlist.xcstrings`

**验收**：
- 切换系统语言后 App 名称和基础文案正确切换
- 中文和英文条目数量一致

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

## M1: 设计系统 + 数据层

### E1: iOS 设计系统

#### M1-E1-T1: 颜色系统

**描述**：在 `Assets.xcassets` 中定义 Color Set，支持 Light/Dark 两种模式。所有颜色值来自交互文档十三节：

Light 模式：
- `background`: #FAFAF8
- `cardBackground`: #FFFFFF
- `textPrimary`: #1A1A1A
- `textSecondary`: #6B6B6B
- `textTertiary`: #9B9B9B
- `separator`: #F0F0EC
- `accent`: #2C2C2C
- `link`: #4A7C59
- `unread`: #5B8AF0
- `success`: #5B9A6B
- `warning`: #C4793C
- `error`: #C44B4B
- `tagBackground`: #F2F2ED
- `tagText`: #4A4A4A
- 高亮色：`highlightYellow` #FFF3C4、`highlightGreen` #D4EDDA、`highlightBlue` #CCE5FF、`highlightRed` #F8D7DA

Dark 模式：背景 #1C1C1E，文字 #E5E5E5，其余颜色适配暗色。

创建 `Color+Folio.swift` 扩展，提供 `Color.folio.xxx` 语法糖。

**前置**：M0-E1-T3

**产出**：
- `ios/Folio/Resources/Assets.xcassets/Colors/`（所有 Color Set）
- `ios/Folio/Utils/Extensions/Color+Folio.swift`

**验收**：
- SwiftUI Preview 中所有颜色正确显示
- 切换暗色模式后颜色自动适配
- 代码中可通过 `Color.folio.textPrimary` 等方式引用

**测试**：
测试文件：`ios/FolioTests/DesignSystem/ColorTests.swift`
测试用例：
- `testAllColorsExist()` — 验证所有 Color.folio.xxx 属性可访问不为 nil
- `testLightDarkVariants()` — 验证 Light/Dark 模式颜色值不同
- `testBackgroundColor()` — 验证 background 颜色在 Light 模式下为 #FAFAF8
- `testAccentColor()` — 验证 accent 颜色值正确
- `testHighlightColors()` — 验证 4 种高亮色存在

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ColorTests 2>&1 | tail -5
# 期望：Test Suite 'ColorTests' passed
```

---

#### M1-E1-T2: 字体系统

**描述**：创建 `Typography.swift`，定义 Folio 字体系统（参考交互文档十三节字体系统）：

界面文字：
- `navTitle`：SF Pro Display, 20pt, Semibold
- `pageTitle`：SF Pro Display, 28pt, Bold
- `listTitle`：SF Pro Text, 17pt, Semibold
- `body`：SF Pro Text, 15pt, Regular
- `caption`：SF Pro Text, 13pt, Regular
- `tag`：SF Pro Text, 13pt, Medium

阅读页文字（中文）：
- `articleTitle`：Noto Serif SC, 24pt, Bold
- `articleBody`：Noto Serif SC, 17pt, Regular, 行高 1.7
- `articleCode`：SF Mono, 14pt, Regular
- `articleQuote`：Noto Serif SC, 16pt, Italic

用 ViewModifier 实现，支持 Dynamic Type。

**前置**：M0-E1-T3

**产出**：
- `ios/Folio/Presentation/Components/Typography.swift`

**验收**：
- 各级字体在 Preview 中显示正确
- Dynamic Type 调整后文字大小跟随变化

**测试**：
测试文件：`ios/FolioTests/DesignSystem/TypographyTests.swift`
测试用例：
- `testAllFontStylesExist()` — 验证所有 Typography 样式（navTitle、pageTitle、listTitle、body、caption、tag）可创建
- `testArticleFontsExist()` — 验证阅读页字体样式（articleTitle、articleBody、articleCode、articleQuote）可创建
- `testFontSizes()` — 验证各字体尺寸值正确（如 navTitle = 20pt, body = 15pt）

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/TypographyTests 2>&1 | tail -5
# 期望：Test Suite 'TypographyTests' passed
```

---

#### M1-E1-T3: 间距和圆角系统

**描述**：创建 `Spacing.swift` 和 `CornerRadius.swift`，定义设计规范（参考交互文档十三节）：

间距（基于 4pt 网格）：
- `xxs`: 4pt、`xs`: 8pt、`sm`: 12pt、`md`: 16pt、`lg`: 24pt、`xl`: 32pt
- `screenPadding`: 16pt

圆角：
- `small`: 4pt（标签、小按钮）
- `medium`: 8pt（卡片、缩略图）
- `large`: 12pt（弹窗、底部面板）

**前置**：M0-E1-T3

**产出**：
- `ios/Folio/Presentation/Components/Spacing.swift`
- `ios/Folio/Presentation/Components/CornerRadius.swift`

**验收**：
- 代码中可用 `Spacing.md`、`CornerRadius.medium` 等常量引用

**测试**：
测试文件：`ios/FolioTests/DesignSystem/SpacingTests.swift`
测试用例：
- `testSpacingValues()` — 验证 xxs=4, xs=8, sm=12, md=16, lg=24, xl=32
- `testScreenPadding()` — 验证 screenPadding=16
- `testCornerRadiusValues()` — 验证 small=4, medium=8, large=12

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/SpacingTests 2>&1 | tail -5
# 期望：Test Suite 'SpacingTests' passed
```

---

#### M1-E1-T4: 通用 UI 组件

**描述**：创建以下通用 UI 组件：
1. `TagChip`：标签胶囊视图（背景 tagBackground，文字 tagText，圆角 small，字体 tag）
2. `StatusBadge`：内容状态标识（未读蓝点、处理中沙漏、失败警告、离线图标——参考交互文档五节内容状态标识）
3. `FolioButton`：主按钮和次按钮样式
4. `ToastView`：顶部 Toast 提示（淡入 → 停留 2s → 淡出，参考交互文档十三节动画清单）

**前置**：M1-E1-T1, M1-E1-T2, M1-E1-T3

**产出**：
- `ios/Folio/Presentation/Components/TagChip.swift`
- `ios/Folio/Presentation/Components/StatusBadge.swift`
- `ios/Folio/Presentation/Components/FolioButton.swift`
- `ios/Folio/Presentation/Components/ToastView.swift`

**验收**：
- 每个组件有 SwiftUI Preview
- 组件支持 Light/Dark 模式
- 组件支持 Dynamic Type

**测试**：
测试文件：`ios/FolioTests/Components/UIComponentTests.swift`
测试用例：
- `testTagChipRendersWithText()` — TagChip 组件可创建并渲染指定文本
- `testStatusBadgeAllStates()` — StatusBadge 支持所有状态（unread、processing、failed、offline）
- `testFolioButtonStyles()` — FolioButton 支持 primary 和 secondary 样式
- `testToastViewAppears()` — ToastView 可正确创建

验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E2: iOS 数据层

#### M1-E2-T1: SwiftData 模型定义

**描述**：实现 SwiftData 数据模型（完整参考架构文档 2.3 节）：
- `Article`：包含 id(UUID)、url、title、author、siteName、faviconURL、coverImageURL、markdownContent、summary、keyPoints([String])、category(关系)、tags(多对多关系)、status(ArticleStatus枚举)、isFavorite、isArchived、readProgress(Double)、createdAt、updatedAt、publishedAt、lastReadAt、sourceType(SourceType枚举)、syncState(SyncState枚举)、serverID
- `Tag`：id(UUID)、name(unique)、isUserCreated、articleCount、articles(反向关系)、createdAt
- `Category`：id(UUID)、name、icon(SF Symbol 名称)、articleCount、createdAt

包含 `ArticleStatus`、`SourceType`、`SyncState` 三个枚举。`SourceType.detect(from:)` 静态方法根据 URL 判断来源类型。

**前置**：M0-E1-T3

**产出**：
- `ios/Folio/Domain/Models/Article.swift`
- `ios/Folio/Domain/Models/Tag.swift`
- `ios/Folio/Domain/Models/Category.swift`

**验收**：
- `ModelContainer` 可用这三个模型初始化
- `Article` 与 `Tag` 多对多关系正确
- `Article` 与 `Category` 多对一关系正确
- `SourceType.detect(from: "https://mp.weixin.qq.com/s/xxx")` 返回 `.wechat`

**测试**：
测试文件：`ios/FolioTests/Models/ArticleModelTests.swift`
测试用例：
- `testArticleCreation()` — 创建 Article 并验证默认值
- `testSourceTypeDetection_wechat()` — `mp.weixin.qq.com` → `.wechat`
- `testSourceTypeDetection_twitter()` — `twitter.com` 和 `x.com` → `.twitter`
- `testSourceTypeDetection_weibo()` — `weibo.com` → `.weibo`
- `testSourceTypeDetection_zhihu()` — `zhihu.com` → `.zhihu`
- `testSourceTypeDetection_web()` — 普通 URL → `.web`
- `testArticleTagRelationship()` — 文章与标签多对多关系
- `testArticleCategoryRelationship()` — 文章与分类多对一关系
- `testArticleStatusEnum()` — 枚举 Codable 编解码

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ArticleModelTests 2>&1 | tail -5
# 期望：Test Suite 'ArticleModelTests' passed
```

---

#### M1-E2-T2: SwiftData 容器配置

**描述**：创建 `DataManager.swift`，负责 SwiftData ModelContainer 的创建和配置。支持两种模式：
1. App Group 共享模式（主 App 和 Share Extension 共用）：使用 `ModelConfiguration(groupContainer: .identifier("group.com.folio.app"))`
2. Preview / 测试模式：使用内存数据库

在 `FolioApp.swift` 中注入 `modelContainer`。预置默认分类数据（9 个分类，参考架构文档 4.2 节 categories INSERT）。

**前置**：M1-E2-T1

**产出**：
- `ios/Folio/Data/SwiftData/DataManager.swift`
- `ios/Folio/App/FolioApp.swift`（更新）

**验收**：
- App 启动后 SwiftData 容器正确初始化
- Share Extension 可访问同一个数据库
- 首次启动后 Category 表有 9 条预置分类
- Preview 模式使用内存数据库不影响真实数据

**测试**：
测试文件：`ios/FolioTests/Data/DataManagerTests.swift`
测试用例：
- `testCreateInMemoryContainer()` — 内存模式创建 ModelContainer 成功
- `testPreloadCategories()` — 首次初始化后 Category 表有 9 条预置分类
- `testPreloadCategoriesIdempotent()` — 多次初始化不重复创建分类
- `testSharedContainerConfiguration()` — App Group 容器配置正确

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/DataManagerTests 2>&1 | tail -5
# 期望：Test Suite 'DataManagerTests' passed
```

---

#### M1-E2-T3: Repository 层

**描述**：实现数据访问层（Repository 模式），封装 SwiftData 的 CRUD 操作：

1. `ArticleRepository`：
   - `save(url:tags:note:)` — 创建 pending 状态文章
   - `fetchAll(category:tags:sortBy:limit:offset:)` — 分页查询，支持分类和标签筛选
   - `fetchByID(_:)` — 按 ID 查询
   - `update(_:)` — 更新文章
   - `delete(_:)` — 删除文章（同步删除关联图片缓存目录）
   - `fetchPending()` — 获取所有 pending 状态文章
   - `existsByURL(_:)` — URL 去重检查
   - `updateStatus(_:status:)` — 更新处理状态
   - `countForCurrentMonth()` — 当月收藏数量

2. `TagRepository`：
   - `fetchAll(sortBy:)` — 获取所有标签
   - `fetchPopular(limit:)` — 获取热门标签
   - `findOrCreate(name:isUserCreated:)` — 查找或创建标签
   - `delete(_:)` — 删除标签

3. `CategoryRepository`：
   - `fetchAll()` — 获取所有分类
   - `fetchBySlug(_:)` — 按 slug 查找

**前置**：M1-E2-T2

**产出**：
- `ios/Folio/Data/Repository/ArticleRepository.swift`
- `ios/Folio/Data/Repository/TagRepository.swift`
- `ios/Folio/Data/Repository/CategoryRepository.swift`

**验收**：
- 可创建 Article 并通过 fetchAll 查询到
- 分类筛选和标签筛选返回正确结果
- URL 去重检测正常工作
- 分页查询返回正确数量

**测试**：
测试文件：
- `ios/FolioTests/Repository/ArticleRepositoryTests.swift`
- `ios/FolioTests/Repository/TagRepositoryTests.swift`
- `ios/FolioTests/Repository/CategoryRepositoryTests.swift`
测试用例（ArticleRepositoryTests）：
- `testSave_createsArticleWithPendingStatus()`
- `testFetchAll_returnsSortedByDate()`
- `testFetchAll_filterByCategory()`
- `testFetchAll_filterByTags()`
- `testFetchAll_pagination()`
- `testFetchByID_found()`
- `testFetchByID_notFound()`
- `testExistsByURL_exists()`
- `testExistsByURL_notExists()`
- `testDelete_removesArticle()`
- `testFetchPending_returnsOnlyPending()`
- `testUpdateStatus()`
- `testCountForCurrentMonth()`
测试用例（TagRepositoryTests）：
- `testFindOrCreate_createsNew()`
- `testFindOrCreate_findsExisting()`
- `testFetchPopular_orderedByCount()`
- `testDelete_removesTag()`
测试用例（CategoryRepositoryTests）：
- `testFetchAll_returns9DefaultCategories()`
- `testFetchBySlug_found()`

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ArticleRepositoryTests -only-testing:FolioTests/TagRepositoryTests -only-testing:FolioTests/CategoryRepositoryTests 2>&1 | tail -5
# 期望：Test Suite 'All tests' passed
```

---

### E3: 后端数据层

#### M1-E3-T1: Go Domain 模型

**描述**：在 `internal/domain/` 下定义 Go 领域模型（对应 PostgreSQL 表结构）：
- `User`：ID、AppleID、Email、Nickname、Subscription、MonthlyQuota、CurrentMonthCount 等
- `Article`：ID、UserID、URL、Title、Author、MarkdownContent、Summary、KeyPoints、CategoryID、Status、SourceType 等
- `Tag`：ID、Name、UserID、IsAIGenerated、ArticleCount
- `Category`：ID、Slug、NameZh、NameEn、Icon、SortOrder
- `CrawlTask`：ID、ArticleID、UserID、URL、Status 等

**前置**：M0-E2-T2

**产出**：
- `server/internal/domain/user.go`
- `server/internal/domain/article.go`
- `server/internal/domain/tag.go`
- `server/internal/domain/category.go`
- `server/internal/domain/task.go`

**验收**：
- `go build ./internal/domain/...` 成功
- 所有字段有 JSON tag

**测试**：
测试文件：`server/internal/domain/domain_test.go`
测试用例：
- `TestArticle_JSONTags()` — 验证 Article 结构体所有字段有正确的 JSON tag
- `TestUser_JSONTags()` — 验证 User 结构体所有字段有正确的 JSON tag
- `TestTag_JSONTags()` — 验证 Tag 结构体 JSON tag
- `TestCategory_JSONTags()` — 验证 Category 结构体 JSON tag
- `TestArticle_JSONMarshal()` — 验证 Article 序列化为 JSON 后字段名符合 snake_case
- `TestUser_JSONMarshal()` — 验证 User 序列化为 JSON 后字段名符合 snake_case

验证命令：
```bash
cd server && go build ./internal/domain/... 2>&1 | tail -3
# 期望：无错误输出
cd server && go test ./internal/domain/... -v -count=1 2>&1 | tail -10
# 期望：PASS ok folio-server/internal/domain
```

---

#### M1-E3-T2: Go Repository 层

**描述**：实现 PostgreSQL 数据访问层，使用 `pgx` 连接池。每个 Repository 接收 `*pgxpool.Pool`：

1. `UserRepo`：CreateOrUpdate、FindByAppleID、FindByID、UpdateSubscription、IncrementMonthlyCount、ResetMonthlyCount
2. `ArticleRepo`：Create、FindByID、ListByUser(分页+筛选)、Update、Delete、FindByUserAndURL(去重)、UpdateStatus、UpdateCrawlResult、SetError
3. `TagRepo`：FindOrCreate、ListByUser、Delete、IncrementCount
4. `CategoryRepo`：List、FindBySlug
5. `TaskRepo`：Create、FindByID、UpdateStatus

包含连接池初始化函数 `NewPool(databaseURL string) *pgxpool.Pool`。

**前置**：M1-E3-T1, M0-E5-T2

**产出**：
- `server/internal/repository/pool.go`
- `server/internal/repository/user.go`
- `server/internal/repository/article.go`
- `server/internal/repository/tag.go`
- `server/internal/repository/category.go`
- `server/internal/repository/task.go`

**验收**：
- `go build ./internal/repository/...` 成功
- 连接池可连接到 Docker Compose 中的 PostgreSQL
- 所有 SQL 使用参数化查询（`$1`、`$2` 占位符）

**测试**：
测试文件：
- `server/internal/repository/user_test.go`
- `server/internal/repository/article_test.go`
- `server/internal/repository/tag_test.go`
- `server/internal/repository/category_test.go`
- `server/internal/repository/task_test.go`
测试用例（使用 testcontainers 临时 PostgreSQL）：
- `TestUserRepo_CreateOrUpdate()` — 创建新用户和更新已有用户
- `TestUserRepo_FindByAppleID()` — 按 Apple ID 查找用户
- `TestUserRepo_FindByID()` — 按 ID 查找用户
- `TestArticleRepo_Create()` — 创建文章
- `TestArticleRepo_FindByID()` — 按 ID 查找文章
- `TestArticleRepo_ListByUser()` — 按用户分页查询 + 分类/标签筛选
- `TestArticleRepo_Update()` — 更新文章字段
- `TestArticleRepo_Delete()` — 删除文章
- `TestArticleRepo_FindByUserAndURL()` — URL 去重查询
- `TestArticleRepo_UpdateStatus()` — 更新状态
- `TestTagRepo_FindOrCreate()` — 查找或创建标签
- `TestTagRepo_ListByUser()` — 按用户获取标签列表
- `TestTagRepo_Delete()` — 删除标签
- `TestCategoryRepo_List()` — 获取全部分类（预置 9 条）
- `TestCategoryRepo_FindBySlug()` — 按 slug 查找分类
- `TestTaskRepo_Create()` — 创建任务
- `TestTaskRepo_UpdateStatus()` — 更新任务状态

验证命令：
```bash
cd server && go test ./internal/repository/... -v -count=1 2>&1 | tail -10
# 期望：PASS ok folio-server/internal/repository
```

---

## M2: 收藏库主界面（iOS，Mock 数据）

### E1: 导航框架

#### M2-E1-T1: 三 Tab 导航框架

**描述**：实现底部 Tab Bar 导航，3 个 Tab（参考交互文档一节导航结构）：
1. 收藏（Library）— SF Symbol `book`
2. 搜索（Search）— SF Symbol `magnifyingglass`
3. 设置（Settings）— SF Symbol `gearshape`

使用 SwiftUI `TabView`。Tab Bar 图标使用 Regular 粗细、24pt。每个 Tab 内使用 `NavigationStack` 支持页面跳转。

**前置**：M1-E1-T1, M0-E6-T1

**产出**：
- `ios/Folio/App/MainTabView.swift`
- `ios/Folio/App/FolioApp.swift`（更新，根视图改为 MainTabView）

**验收**：
- App 启动显示 3 Tab 导航
- Tab 名称中英文正确
- 各 Tab 切换流畅

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E2: Mock 数据

#### M2-E2-T1: Mock 数据工厂

**描述**：创建 `MockDataFactory.swift`，生成测试用的 Article/Tag/Category 数据。包含：
- `generateArticles(count:)` — 生成指定数量文章，覆盖不同 SourceType、不同 Status、不同分类
- `generateTags()` — 生成 15-20 个常见标签（Swift、AI、产品设计、Rust 等）
- `populateSampleData(context:)` — 向 ModelContext 注入完整的 Mock 数据集（30 篇文章，含多种状态）

Mock 文章应包含真实感的标题（中英文混合）、摘要、标签和来源信息。

**前置**：M1-E2-T2

**产出**：
- `ios/Folio/Utils/MockDataFactory.swift`

**验收**：
- Preview 中使用 Mock 数据显示完整列表
- Mock 数据包含不同分类、不同状态、不同时间的文章

**测试**：
测试文件：`ios/FolioTests/Utils/MockDataFactoryTests.swift`
测试用例：
- `testGenerateArticles_correctCount()` — `generateArticles(count: 10)` 返回 10 篇文章
- `testGenerateArticles_diverseSourceTypes()` — 生成的文章包含至少 3 种不同 SourceType
- `testGenerateArticles_diverseStatuses()` — 生成的文章包含不同 ArticleStatus
- `testGenerateTags_notEmpty()` — `generateTags()` 返回 15-20 个标签
- `testPopulateSampleData()` — `populateSampleData(context:)` 后 ModelContext 包含 30 篇文章

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/MockDataFactoryTests 2>&1 | tail -5
# 期望：Test Suite 'MockDataFactoryTests' passed
```

---

### E3: 收藏库列表

#### M2-E3-T1: 文章卡片组件

**描述**：实现收藏库列表中的文章卡片 `ArticleCardView`（参考交互文档五节内容卡片设计）。卡片布局：
- 左侧可选缩略图（60×60，圆角 8pt）
- 右侧纵向排列：
  - 第一层：文章标题（17pt, Semibold，最多 2 行）
  - 第二层：AI 摘要（15pt, Regular, textSecondary，最多 2 行）
  - 第三层：来源平台图标 + 来源名称 + " · " + 相对时间（13pt, textTertiary）
  - 第四层：标签列表（最多 3 个 TagChip，超出显示 "+N"）
- 左侧未读标记（蓝色圆点）
- 处理中/失败/离线状态图标（StatusBadge 组件）

相对时间格式：刚刚、N分钟前、N小时前、昨天、N天前、具体日期。

**前置**：M1-E1-T4, M1-E2-T1

**产出**：
- `ios/Folio/Presentation/Home/ArticleCardView.swift`
- `ios/Folio/Utils/Extensions/Date+RelativeFormat.swift`

**验收**：
- Preview 显示不同状态的卡片（未读、已读、处理中、失败）
- 标题和摘要正确截断
- 时间显示格式正确（中英文切换后使用不同文案）
- Light/Dark 模式正确

**测试**：
测试文件：`ios/FolioTests/Extensions/DateRelativeFormatTests.swift`
测试用例：
- `testJustNow()` — 当前时间 → "刚刚"
- `testMinutesAgo()` — 5 分钟前 → "5分钟前"
- `testHoursAgo()` — 3 小时前 → "3小时前"
- `testYesterday()` — 昨天 → "昨天"
- `testDaysAgo()` — 3 天前 → "3天前"
- `testSpecificDate()` — 超过 7 天 → 具体日期格式
- `testEnglishLocale()` — 英文环境下格式正确

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/DateRelativeFormatTests 2>&1 | tail -5
# 期望：Test Suite 'DateRelativeFormatTests' passed
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

#### M2-E3-T2: 收藏库列表视图

**描述**：实现收藏库主列表 `HomeView` + `HomeViewModel`。功能：
- SwiftData `@Query` 按 `createdAt` 倒序查询文章
- `LazyVStack` 显示文章卡片列表，分页加载（每次 20 条）
- 按日期分组显示（今天、昨天、具体日期）——参考交互文档五节时间线布局
- 点击卡片跳转到阅读页（先用空页面占位）
- 导航栏标题 "Folio"
- 右上角粘贴按钮（`[+粘贴]`）

**前置**：M2-E3-T1, M2-E2-T1

**产出**：
- `ios/Folio/Presentation/Home/HomeView.swift`
- `ios/Folio/Presentation/Home/HomeViewModel.swift`

**验收**：
- Mock 数据正确显示在列表中
- 列表滚动流畅（60fps）
- 按日期分组正确
- 首屏加载 < 0.3 秒

**测试**：
测试文件：`ios/FolioTests/ViewModels/HomeViewModelTests.swift`
测试用例：
- `testFetchArticles_returnsAllWhenNoFilter()` — 无筛选条件返回全部文章
- `testFetchArticles_sortedByDateDescending()` — 文章按 createdAt 倒序排列
- `testGroupByDate_today()` — 今天的文章归入"今天"组
- `testGroupByDate_yesterday()` — 昨天的文章归入"昨天"组
- `testGroupByDate_specificDate()` — 更早的文章按具体日期分组
- `testPagination_loadsNextPage()` — 分页加载第二页
- `testMarkAsRead()` — 标记已读更新 readProgress

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/HomeViewModelTests 2>&1 | tail -5
# 期望：Test Suite 'HomeViewModelTests' passed
```

---

#### M2-E3-T3: 空状态视图

**描述**：实现收藏库空状态 `EmptyStateView`（参考交互文档三节空状态首页）：
- 书本图标
- 标题："你的知识库还是空的" / "Your library is empty"
- 分步引导：1. 打开微信/Safari → 2. 找到一篇好文章 → 3. 点击「分享」按钮 → 4. 选择「Folio」
- 分隔线 "── 或者 ──"
- 「粘贴链接试试」按钮（检测剪贴板中是否有 URL）
- 整体淡入 + 上移 8pt 动画（300ms, ease-out）

**前置**：M1-E1-T1, M0-E6-T1

**产出**：
- `ios/Folio/Presentation/Home/EmptyStateView.swift`

**验收**：
- 无文章数据时显示空状态
- 粘贴按钮仅在剪贴板有 URL 时显示
- 入场动画正确
- 中英文切换正确

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E4: 筛选系统

#### M2-E4-T1: 分类筛选条

**描述**：实现分类横向滚动筛选条 `CategoryFilterBar`（参考交互文档五节分类筛选）：
- 横向 ScrollView，`全部` 始终在第一位
- 仅显示 articleCount > 0 的分类
- 选中态：深色背景 + 白色文字
- 未选中态：浅灰背景 + 深灰文字
- 点击切换分类，列表联动刷新
- 切换动画 < 0.2 秒

与 HomeViewModel 绑定，选中分类后过滤文章列表。

**前置**：M2-E3-T2

**产出**：
- `ios/Folio/Presentation/Home/CategoryFilterBar.swift`
- `ios/Folio/Presentation/Home/HomeViewModel.swift`（更新，增加分类筛选逻辑）

**验收**：
- 分类列表正确显示，可横向滚动
- 点击分类后列表筛选结果正确
- 切换分类无延迟

**测试**：
测试文件：`ios/FolioTests/ViewModels/HomeViewModelFilterTests.swift`
测试用例：
- `testFilterByCategory_tech()` — 选择"技术"分类后仅显示该分类文章
- `testFilterByCategory_all()` — 选择"全部"后显示所有文章
- `testFilterByCategory_emptyCategory()` — 选择无文章的分类返回空列表
- `testCategoriesWithArticles()` — 仅返回 articleCount > 0 的分类
- `testCategoryFilterResetsPagination()` — 切换分类后分页重置为第一页

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/HomeViewModelFilterTests 2>&1 | tail -5
# 期望：Test Suite 'HomeViewModelFilterTests' passed
```

---

#### M2-E4-T2: 标签筛选

**描述**：在分类筛选条下方，添加可展开/收起的标签筛选区域 `TagFilterView`（参考交互文档五节标签筛选）：
- 收起状态显示 "🏷 标签筛选" 文字，点击展开
- 展开后显示热门标签（按 articleCount 倒序排列）
- 标签使用 FlowLayout（Wrap 布局），支持多选（AND 逻辑）
- 选中标签高亮显示
- 再次点击取消选择
- 与 HomeViewModel 绑定，选中标签后过滤列表

**前置**：M2-E4-T1

**产出**：
- `ios/Folio/Presentation/Home/TagFilterView.swift`
- `ios/Folio/Presentation/Components/FlowLayout.swift`
- `ios/Folio/Presentation/Home/HomeViewModel.swift`（更新）

**验收**：
- 标签 Wrap 布局正确
- 多标签筛选结果正确（AND 逻辑）
- 分类和标签可组合筛选

**测试**：
测试文件：`ios/FolioTests/ViewModels/HomeViewModelTagFilterTests.swift`
测试用例：
- `testFilterBySingleTag()` — 选择一个标签后仅显示含该标签的文章
- `testFilterByMultipleTags_AND()` — 选择两个标签后仅显示同时含两个标签的文章
- `testDeselectTag_removesFilter()` — 取消选择标签后恢复完整列表
- `testCombineCategoryAndTagFilter()` — 分类 + 标签组合筛选结果正确
- `testPopularTags_orderedByCount()` — 热门标签按 articleCount 倒序

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/HomeViewModelTagFilterTests 2>&1 | tail -5
# 期望：Test Suite 'HomeViewModelTagFilterTests' passed
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **（FlowLayout 编译检查）
```

---

### E5: 时间线视图

#### M2-E5-T1: 时间线视图

**描述**：实现时间线视图 `TimelineView`（参考交互文档五节时间线视图）：
- 在导航栏右侧添加视图切换按钮（列表 ☰ / 时间线 📅）
- 时间线按月分组 → 按日分组
- 月份可折叠/展开
- 每条仅显示标题（信息密度高）
- 最新在最上方
- 月份行右侧显示当月收藏数量统计

**前置**：M2-E3-T2

**产出**：
- `ios/Folio/Presentation/Home/TimelineView.swift`
- `ios/Folio/Presentation/Home/HomeView.swift`（更新，添加视图切换）

**验收**：
- 列表视图和时间线视图可切换
- 月份折叠/展开正常
- 文章按日期正确分组

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E6: 手势系统

#### M2-E6-T1: 列表手势操作

**描述**：为文章卡片列表添加手势操作（参考交互文档二节手势系统）：
1. **左滑**：显示红色删除按钮。点击后弹确认对话框。使用 SwiftUI `.swipeActions(edge: .trailing)`
2. **右滑**：切换已读/未读。蓝色背景。使用 `.swipeActions(edge: .leading)`
3. **长按**：弹出快捷操作菜单（`.contextMenu`）——分享、编辑标签、删除。Haptic 反馈
4. **下拉刷新**：使用 `.refreshable`，触发检查待处理任务
5. **捏合切换视图**：两指捏合在列表/紧凑视图间切换（使用 `MagnificationGesture`）

**前置**：M2-E3-T2

**产出**：
- `ios/Folio/Presentation/Home/HomeView.swift`（更新，添加手势）
- `ios/Folio/Presentation/Home/ArticleCardView.swift`（更新，添加 swipeActions 和 contextMenu）

**验收**：
- 左滑显示删除按钮，确认后删除
- 右滑切换已读/未读状态
- 长按弹出菜单，带 Haptic 反馈
- 下拉刷新触发回调
- 手势之间不冲突

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

## M3: 收藏入口（iOS）

### E1: Onboarding

#### M3-E1-T1: 欢迎引导页

**描述**：实现 3 页欢迎引导（参考交互文档三节首次使用流程）：

页面 1：
- Folio 图标
- "Folio · 页集"
- "分享链接，知识留住"
- 说明文案 + [继续] 按钮

页面 2：
- 分享操作示意图（Safari/微信 → 分享 → 选择 Folio → ✓ 已收藏）
- 说明文案 + [继续] 按钮

页面 3：
- 🔒 本地优先，隐私安全
- 说明文案
- [用 Apple ID 继续] 按钮
- "稍后再说" 链接

使用 `TabView` + `PageTabViewStyle` 实现。用 `@AppStorage("hasCompletedOnboarding")` 控制仅首次显示。

**前置**：M1-E1-T1, M0-E6-T1

**产出**：
- `ios/Folio/Presentation/Onboarding/OnboardingView.swift`
- `ios/Folio/Presentation/Onboarding/OnboardingPage.swift`
- `ios/Folio/App/FolioApp.swift`（更新，根据 hasCompletedOnboarding 显示）

**验收**：
- 首次启动显示欢迎页
- 三页可左右滑动
- 点击"稍后再说"跳过后进入主界面
- 再次启动不再显示欢迎页

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

#### M3-E1-T2: 通知权限请求

**描述**：在 Onboarding 最后一页后，显示通知权限说明页（参考交互文档三节权限说明页）：
- "Folio 需要以下权限来更好地为你服务："
- 🔔 通知权限：文章抓取完成时提醒你 [允许] [跳过]
- "通知仅用于告知抓取状态，不会发送任何营销信息。"
- [开始使用] 按钮

点击 [允许] 调用 `UNUserNotificationCenter.requestAuthorization`。

**前置**：M3-E1-T1

**产出**：
- `ios/Folio/Presentation/Onboarding/PermissionView.swift`

**验收**：
- 点击允许后弹出系统权限对话框
- 点击跳过后不请求权限
- 权限结果不影响 App 使用

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E2: Share Extension

#### M3-E2-T1: Share Extension 核心实现

**描述**：实现 Share Extension 完整功能（参考架构文档 2.2 节和交互文档四节）。

`ShareViewController`（UIViewController 子类）：
1. 接收 URL（支持 `UTType.url` 和 `UTType.plainText` 两种类型）
2. 展示极简 SwiftUI 界面 `CompactShareView`：
   - 状态 1（瞬间）：「正在添加...」+ 进度动画
   - 状态 2（0.5秒后）：「✓ 已添加到 Folio」+ AI 将在后台自动整理
   - 状态 3（1.5秒后）：自动关闭
3. 通过 `SharedDataManager`（App Group 共享 SwiftData 容器）写入 Article（status = .pending）
4. 离线时额外显示 "📶 当前离线，联网后自动抓取正文"
5. URL 去重：如已收藏过，显示 "📌 这篇已经收藏过了" + [查看] [知道了]

严格控制内存（120MB 限制）：不加载主 App 完整依赖。

**前置**：M1-E2-T2, M0-E6-T1

**产出**：
- `ios/ShareExtension/ShareViewController.swift`
- `ios/ShareExtension/CompactShareView.swift`
- `ios/Folio/Data/SwiftData/SharedDataManager.swift`

**验收**：
- 从 Safari 分享链接到 Folio，显示成功动画后自动关闭
- 从微信分享链接到 Folio 正常工作
- 离线状态下显示离线提示
- 分享已收藏过的 URL 显示重复提示
- Extension 内存占用 < 120MB

**测试**：
测试文件：`ios/FolioTests/Data/SharedDataManagerTests.swift`
测试用例：
- `testSaveArticle_createsPendingArticle()` — 保存 URL 后创建 pending 状态文章
- `testSaveArticle_extractsURLFromPlainText()` — 从纯文本中提取 URL 并保存
- `testSaveArticle_duplicateURL()` — 保存重复 URL 时返回已存在错误
- `testSaveArticle_setsSourceType()` — 保存微信链接自动设置 sourceType 为 .wechat
- `testSharedContainer_accessible()` — App Group 共享容器可正常读写

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/SharedDataManagerTests 2>&1 | tail -5
# 期望：Test Suite 'SharedDataManagerTests' passed
```

---

#### M3-E2-T2: 月度配额检查

**描述**：在 Share Extension 保存文章前检查当月配额（Free 用户 30 篇/月）。使用 App Group UserDefaults 存储当月计数（Key = `quota_yyyy-MM`）。

- 未达限额：正常保存，计数 +1
- 已达限额：显示 "本月已收藏 30 篇，升级 Pro 无限收藏" + [了解 Pro] [知道了]

**前置**：M3-E2-T1

**产出**：
- `ios/Folio/Data/SwiftData/SharedDataManager.swift`（更新，增加配额检查）
- `ios/ShareExtension/CompactShareView.swift`（更新，增加限额提示 UI）

**验收**：
- Free 用户第 31 篇收藏时显示限额提示
- 计数跨月自动重置
- Pro 用户无限制

**测试**：
测试文件：`ios/FolioTests/Data/QuotaCheckTests.swift`
测试用例：
- `testFreeUser_underQuota()` — Free 用户第 1-29 篇收藏，canSave 返回 true
- `testFreeUser_atQuota()` — Free 用户第 30 篇收藏，canSave 返回 true
- `testFreeUser_overQuota()` — Free 用户第 31 篇收藏，canSave 返回 false
- `testProUser_noQuotaLimit()` — Pro 用户无限额，canSave 始终返回 true
- `testQuotaResets_onNewMonth()` — 跨月后计数自动重置为 0
- `testQuotaKey_includesYearMonth()` — 配额 Key 格式为 `quota_yyyy-MM`

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/QuotaCheckTests 2>&1 | tail -5
# 期望：Test Suite 'QuotaCheckTests' passed
```

---

### E3: 剪贴板检测

#### M3-E3-T1: 剪贴板检测 + 收藏

**描述**：实现剪贴板检测功能（参考 PRD 四节 F1 剪贴板检测规格和交互文档三节剪贴板检测逻辑）：

1. App 从后台切回前台时（`.scenePhase` 变为 `.active`），检测剪贴板是否包含 URL
2. 有 URL 且未提示过且未收藏过：顶部浮出 Toast："检测到链接，是否收藏？" + [收藏] [忽略]
3. Toast 5 秒无操作自动消失
4. 点击 [收藏]：调用 ArticleRepository.save 保存，显示 "已添加" 反馈
5. 点击 [忽略] 或自动消失：记录该 URL 为"已忽略"，下次不再提示
6. 仅在 App 前台时读取剪贴板，遵循 iOS 隐私策略

使用 `UIPasteboard.general.url` 或解析 `UIPasteboard.general.string` 中的 URL。

**前置**：M1-E2-T3, M1-E1-T4

**产出**：
- `ios/Folio/Presentation/Home/ClipboardDetector.swift`
- `ios/Folio/Presentation/Home/HomeView.swift`（更新，集成 Toast）

**验收**：
- 复制 URL 后切回 App，顶部显示 Toast
- 点击收藏后文章出现在列表
- 同一 URL 不重复提示
- 5 秒后 Toast 自动消失

**测试**：
测试文件：`ios/FolioTests/Home/ClipboardDetectorTests.swift`
测试用例：
- `testDetectsURL_fromPasteboard()` — 剪贴板有 URL 时检测到并返回
- `testDetectsURL_fromPlainText()` — 剪贴板有纯文本 URL 时解析并返回
- `testIgnoresNonURL()` — 剪贴板是普通文本时返回 nil
- `testAlreadySaved_noPrompt()` — URL 已收藏过时不再提示
- `testAlreadyIgnored_noPrompt()` — URL 已忽略过时不再提示
- `testMarkAsIgnored()` — 忽略后该 URL 记录为"已忽略"
- `testEmptyPasteboard_noPrompt()` — 剪贴板为空时不提示

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ClipboardDetectorTests 2>&1 | tail -5
# 期望：Test Suite 'ClipboardDetectorTests' passed
```

---

### E4: 离线队列

#### M3-E4-T1: 离线队列管理器

**描述**：实现离线队列管理（参考架构文档 2.5 节）：

`OfflineQueueManager`（ObservableObject）：
1. `NWPathMonitor` 监控网络状态
2. 网络恢复后自动处理 pending 状态的文章（调用后端 API 提交）
3. `BGTaskScheduler` 注册后台任务（identifier: `com.folio.article-processing`），App 进入后台时继续处理
4. 维护 `@Published var pendingCount: Int`
5. 处理失败的文章标记为 `.failed`

注意：此阶段 API 调用部分先用 TODO 注释占位，等后端对接时（M7）再实现。

**前置**：M1-E2-T3

**产出**：
- `ios/Folio/Data/Network/OfflineQueueManager.swift`

**验收**：
- 离线创建的 pending 文章在联网后触发处理回调
- 后台任务注册成功
- pendingCount 准确反映待处理数量

**测试**：
测试文件：`ios/FolioTests/Network/OfflineQueueManagerTests.swift`
测试用例：
- `testPendingCount_reflectsActualPending()` — pendingCount 等于 pending 状态文章数量
- `testNetworkAvailable_triggerProcessing()` — 网络恢复后调用处理回调
- `testProcessPending_updatesStatus()` — 处理成功后文章状态不再是 pending
- `testProcessFailed_marksAsFailed()` — 处理失败的文章标记为 .failed
- `testBackgroundTaskRegistration()` — BGTaskScheduler 注册 identifier 正确

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/OfflineQueueManagerTests 2>&1 | tail -5
# 期望：Test Suite 'OfflineQueueManagerTests' passed
```

---

## M4: 阅读视图（iOS）

### E1: Markdown 渲染

#### M4-E1-T1: Markdown 渲染引擎

**描述**：基于 `swift-markdown` 库实现 Markdown → SwiftUI AttributedString 渲染。支持以下元素（参考交互文档六节阅读界面设计规范）：
- 标题 h1-h6（各级字号和间距：h1 24pt Bold 上方 32pt，h2 20pt Semibold 上方 24pt，h3 17pt Semibold 上方 20pt）
- 正文（17pt, Regular, 行高 1.6）
- **加粗**、*斜体*
- `行内代码`（等宽字体，浅灰色背景）
- 代码块（等宽字体，深色背景，支持语法高亮——至少 Swift/Python/JavaScript/Go/Rust/TypeScript/HTML/CSS/JSON/SQL 10 种语言，可横向滚动）
- > 引用（左侧灰色竖线，灰色文字）
- 有序/无序列表
- 表格（横向可滚动，斑马条纹）
- 图片（宽度自适应，保持比例）
- 链接（暗绿色 #4A7C59，点击在 App 内浏览器打开）

创建 `MarkdownRenderer` 类，输入 Markdown 字符串，输出 SwiftUI View。

**前置**：M1-E1-T2, M0-E1-T2

**产出**：
- `ios/Folio/Presentation/Reader/MarkdownRenderer.swift`
- `ios/Folio/Presentation/Reader/CodeBlockView.swift`
- `ios/Folio/Presentation/Reader/TableView.swift`
- `ios/Folio/Presentation/Reader/ImageView.swift`

**验收**：
- Preview 中渲染包含所有 Markdown 元素的测试文档
- 代码块有语法高亮
- 表格可横向滚动
- 图片自适应宽度
- Dark 模式下所有元素可读

**测试**：
测试文件：`ios/FolioTests/Reader/MarkdownRendererTests.swift`
测试用例：
- `testRenderHeadings()` — h1-h6 标题正确解析为对应级别
- `testRenderBoldAndItalic()` — **加粗** 和 *斜体* 正确解析
- `testRenderInlineCode()` — `行内代码` 正确解析
- `testRenderCodeBlock()` — 代码块正确解析，识别语言类型
- `testRenderBlockquote()` — 引用块正确解析
- `testRenderOrderedList()` — 有序列表正确解析
- `testRenderUnorderedList()` — 无序列表正确解析
- `testRenderTable()` — 表格正确解析
- `testRenderLink()` — 链接正确解析含 URL
- `testRenderImage()` — 图片正确解析含 URL 和 alt
- `testRenderComplexDocument()` — 包含所有元素的完整文档正确渲染
- `testSupportedLanguages()` — 代码块至少支持 10 种语言高亮

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/MarkdownRendererTests 2>&1 | tail -5
# 期望：Test Suite 'MarkdownRendererTests' passed
```

---

#### M4-E1-T2: 图片查看器

**描述**：实现图片点击放大查看功能：
- 点击文章中的图片，全屏展示
- 支持手势缩放（捏合）和拖动
- 双击快速缩放（1x ↔ 2x）
- 下滑关闭
- 背景半透明黑色

**前置**：M4-E1-T1

**产出**：
- `ios/Folio/Presentation/Reader/ImageViewerOverlay.swift`

**验收**：
- 点击图片全屏显示
- 捏合缩放流畅
- 下滑关闭回到原位

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E2: 阅读页

#### M4-E2-T1: 阅读页视图

**描述**：实现完整阅读页 `ReaderView` + `ReaderViewModel`（参考交互文档六节阅读体验）：

页面结构（从上到下）：
1. 导航栏：← 返回 + 右上角 [...] 更多操作
2. 文章标题（Noto Serif SC, 24pt, Bold）
3. 元信息卡片（浅灰背景）：来源（可点击跳转）、收藏时间、分类（可点击跳转筛选）、标签（TagChip 组件，可点击跳转筛选）、字数 + 预计阅读时间
4. "── AI 摘要 ──" 分隔线 + 摘要内容
5. "── 正文 ──" 分隔线 + Markdown 渲染正文
6. 底部工具栏：[🔗 原文链接]（App 内 WebView 打开原 URL）+ [📤 分享]

右上角 [...] 菜单：编辑标签、修改分类、复制 Markdown、在浏览器打开、分享、删除收藏。

进入阅读页时标记为已读（readProgress > 0，lastReadAt 更新）。

**前置**：M4-E1-T1, M1-E1-T4, M1-E2-T3

**产出**：
- `ios/Folio/Presentation/Reader/ReaderView.swift`
- `ios/Folio/Presentation/Reader/ReaderViewModel.swift`
- `ios/Folio/Presentation/Reader/ArticleMetaInfoView.swift`

**验收**：
- Mock 数据文章可完整渲染
- 元信息显示正确
- AI 摘要和正文分区清晰
- 长文章（10000 字）滚动流畅
- 加载 < 0.3 秒

**测试**：
测试文件：`ios/FolioTests/ViewModels/ReaderViewModelTests.swift`
测试用例：
- `testLoadArticle_setsProperties()` — 加载文章后 title、summary、content 正确设置
- `testLoadArticle_marksAsRead()` — 进入阅读页后 readProgress > 0 且 lastReadAt 更新
- `testMetaInfo_wordCount()` — 字数统计正确
- `testMetaInfo_estimatedReadTime()` — 预计阅读时间正确（按 400 字/分钟）
- `testDeleteArticle()` — 删除文章后文章不可查询
- `testToggleFavorite()` — 切换收藏状态
- `testCopyMarkdown()` — 复制 Markdown 内容到剪贴板

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ReaderViewModelTests 2>&1 | tail -5
# 期望：Test Suite 'ReaderViewModelTests' passed
```

---

#### M4-E2-T2: 原文 WebView

**描述**：实现 App 内 WebView 浏览器，用于打开原始链接。使用 `WKWebView`（通过 `UIViewRepresentable` 包装）：
- 导航栏显示页面标题和 URL
- 支持前进/后退
- 加载进度条
- 右上角分享按钮

**前置**：M4-E2-T1

**产出**：
- `ios/Folio/Presentation/Reader/WebViewContainer.swift`

**验收**：
- 点击原文链接可在 App 内打开
- 进度条显示加载进度
- 左滑手势返回上一页

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E3: 阅读偏好

#### M4-E3-T1: 阅读偏好设置

**描述**：实现阅读偏好面板（参考交互文档六节阅读偏好）：
- 触发方式：长按文章标题区域唤出
- 使用 `.sheet` 或自定义半屏面板

设置项（全局生效，使用 `@AppStorage` 持久化）：
1. 字号：15 / 17（默认）/ 19 / 21 pt — 使用 Slider 或分段控件
2. 行距：紧凑(1.4) / 标准(1.6, 默认) / 宽松(1.8)
3. 主题：浅色 / 深色 / 自动（跟随系统）
4. 字体：系统默认（苹方/SF Pro）/ 衬线体（Noto Serif SC/Georgia）

`ReaderView` 响应偏好变化实时更新排版。

**前置**：M4-E2-T1

**产出**：
- `ios/Folio/Presentation/Reader/ReadingPreferenceView.swift`
- `ios/Folio/Presentation/Reader/ReaderView.swift`（更新，应用偏好设置）

**验收**：
- 长按标题区域弹出偏好面板
- 修改字号后正文立即更新
- 偏好设置退出 App 后保持

**测试**：
测试文件：`ios/FolioTests/Reader/ReadingPreferenceTests.swift`
测试用例：
- `testDefaultFontSize()` — 默认字号为 17pt
- `testDefaultLineSpacing()` — 默认行距为 1.6（标准）
- `testDefaultFont()` — 默认字体为系统默认
- `testPersistFontSize()` — @AppStorage 持久化字号设置
- `testPersistLineSpacing()` — @AppStorage 持久化行距设置
- `testPersistTheme()` — @AppStorage 持久化主题设置

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ReadingPreferenceTests 2>&1 | tail -5
# 期望：Test Suite 'ReadingPreferenceTests' passed
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

### E4: 阅读进度

#### M4-E4-T1: 阅读进度追踪

**描述**：追踪用户阅读进度：
1. 使用 `ScrollView` 的 `GeometryReader` 或 `ScrollViewReader` 检测滚动位置
2. 计算阅读进度 `readProgress`（0.0 - 1.0），写入 Article 模型
3. 下次打开同一文章恢复到上次阅读位置
4. 滚动到底部标记为"阅读完成"（readProgress = 1.0）

**前置**：M4-E2-T1

**产出**：
- `ios/Folio/Presentation/Reader/ReaderViewModel.swift`（更新，增加进度追踪）

**验收**：
- 阅读进度实时更新到数据库
- 关闭后重新打开恢复到上次位置
- 进度达到 100% 时标记为已读

**测试**：
测试文件：`ios/FolioTests/ViewModels/ReaderViewModelProgressTests.swift`
测试用例：
- `testInitialProgress_zero()` — 新文章初始阅读进度为 0.0
- `testUpdateProgress_savesToModel()` — 更新进度后写入 Article 模型
- `testProgress_clampedTo0And1()` — 进度值限制在 0.0-1.0 范围内
- `testScrollToBottom_marksComplete()` — 滚动到底部进度设为 1.0
- `testRestorePosition_onReopen()` — 重新打开文章恢复到上次阅读位置
- `testLastReadAt_updatedOnScroll()` — 滚动时更新 lastReadAt 时间戳

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ReaderViewModelProgressTests 2>&1 | tail -5
# 期望：Test Suite 'ReaderViewModelProgressTests' passed
```

---

## M5: 全文搜索（iOS）

### E1: FTS5 搜索引擎

#### M5-E1-T1: FTS5 索引管理

**描述**：实现 SQLite FTS5 全文搜索引擎（完整参考架构文档 2.4 节）。

`FTS5SearchManager` 类：
1. 获取 SwiftData 底层 SQLite 数据库路径，直接操作 SQLite API
2. 创建 FTS5 虚拟表：`article_fts(article_id UNINDEXED, title, content, summary, tags, author, site_name)`，使用 `unicode61 remove_diacritics 2` 分词器
3. `indexArticle(_:)` — 添加文章到索引
4. `removeFromIndex(articleID:)` — 从索引中删除
5. `updateIndex(_:)` — 更新文章索引
6. `rebuildAll(articles:)` — 重建全部索引

**前置**：M1-E2-T2

**产出**：
- `ios/Folio/Data/Search/FTS5SearchManager.swift`

**验收**：
- 文章写入后可被搜索到
- 删除文章后搜索不到
- FTS5 表创建成功

**测试**：
测试文件：`ios/FolioTests/Search/FTS5SearchManagerIndexTests.swift`
测试用例：
- `testCreateFTS5Table()` — FTS5 虚拟表创建成功
- `testIndexArticle_addsToIndex()` — 索引文章后可通过 SQL 查询到
- `testRemoveFromIndex()` — 从索引中删除后查询不到
- `testUpdateIndex()` — 更新索引后搜索到新内容
- `testRebuildAll()` — 重建全部索引后文章数量正确
- `testIndexArticle_allFieldsIndexed()` — title、content、summary、tags、author、site_name 全部被索引

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/FTS5SearchManagerIndexTests 2>&1 | tail -5
# 期望：Test Suite 'FTS5SearchManagerIndexTests' passed
```

---

#### M5-E1-T2: 全文搜索查询

**描述**：实现搜索查询功能：

1. `search(query:limit:)` — 全文搜索，BM25 排序。权重配置（参考 PRD 五节搜索范围）：title 10.0、content 5.0、summary 3.0、tags 2.0、author 1.0、site_name 1.0。支持前缀匹配（词尾加 `*`）。
2. `searchWithHighlight(query:)` — 搜索并返回高亮结果，使用 `highlight(article_fts, column, '<mark>', '</mark>')`
3. `searchWithSnippet(query:)` — 搜索并返回上下文片段，使用 `snippet(article_fts, column, '<mark>', '</mark>', '...', 20)`

中文搜索说明：`unicode61` 分词器按字符拆分中文，支持基本中文搜索。后续可升级为 ICU 或 jieba 分词。

**前置**：M5-E1-T1

**产出**：
- `ios/Folio/Data/Search/FTS5SearchManager.swift`（更新，增加查询方法）

**验收**：
- 中文搜索 "机器学习" 可找到包含该词的文章
- 英文搜索 "learning" 可找到 "Learn"、"Learning" 的文章
- 搜索结果按 BM25 相关性排序
- 1000 篇文章搜索 < 200ms

**测试**：
测试文件：`ios/FolioTests/Search/FTS5SearchManagerQueryTests.swift`
测试用例：
- `testSearch_findsMatchingArticle()` — 搜索关键词返回匹配文章
- `testSearch_BM25Ranking()` — 标题匹配排在内容匹配前面（权重 10.0 vs 5.0）
- `testSearch_prefixMatch()` — "learn" 前缀匹配 "learning"
- `testSearch_chineseText()` — 中文搜索 "机器学习" 可找到匹配文章
- `testSearch_noResults()` — 无匹配时返回空数组
- `testSearchWithHighlight()` — 搜索结果包含 `<mark>` 高亮标记
- `testSearchWithSnippet()` — 搜索结果包含上下文片段
- `testSearch_limitResults()` — limit 参数限制返回数量
- `testSearch_caseInsensitive()` — 搜索不区分大小写

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/FTS5SearchManagerQueryTests 2>&1 | tail -5
# 期望：Test Suite 'FTS5SearchManagerQueryTests' passed
```

---

### E2: 搜索 UI

#### M5-E2-T1: 搜索页面

**描述**：实现搜索 Tab 完整 UI（参考交互文档七节搜索流程）：

`SearchView` + `SearchViewModel`：

1. **默认状态**（搜索框为空）：
   - 搜索框 placeholder："搜索收藏内容..."
   - "── 最近搜索 ──" 区域：最近 10 条搜索历史（可单条删除，可清除全部）
   - "── 热门标签 ──" 区域：显示 articleCount 最高的 8 个标签（TagChip，点击直接搜索）

2. **输入状态**（搜索框有内容）：
   - 实时搜索（debounce 200ms），每次输入变化触发 FTS5 查询
   - 搜索建议（标签匹配、标题前缀匹配）
   - "── 搜索结果（N 篇）──"
   - 搜索结果列表：标题（高亮关键词）+ 上下文片段（高亮关键词）+ 来源 · 时间 · 分类
   - 点击结果跳转阅读页

3. **空结果状态**：
   - 📭 图标
   - "没有找到相关内容"
   - 建议文案：检查错别字、使用更简短的关键词、搜索英文关键词

搜索历史使用 `@AppStorage` 存储（JSON 编码的字符串数组）。

**前置**：M5-E1-T2, M1-E1-T4

**产出**：
- `ios/Folio/Presentation/Search/SearchView.swift`
- `ios/Folio/Presentation/Search/SearchViewModel.swift`
- `ios/Folio/Presentation/Search/SearchResultRow.swift`
- `ios/Folio/Presentation/Search/SearchHistoryView.swift`

**验收**：
- 输入关键词后实时显示结果
- 关键词高亮显示
- 搜索历史正确存储和显示
- 热门标签点击触发搜索
- 空结果显示友好提示
- 搜索响应 < 100ms

**测试**：
测试文件：`ios/FolioTests/ViewModels/SearchViewModelTests.swift`
测试用例：
- `testSearch_debounce200ms()` — 快速输入后仅触发一次搜索（debounce 200ms）
- `testSearch_showsResults()` — 搜索后结果列表不为空
- `testSearch_emptyQuery_showsHistory()` — 搜索框为空时显示搜索历史
- `testSearch_savesHistory()` — 搜索后关键词保存到历史记录
- `testSearch_historyLimit10()` — 搜索历史最多保存 10 条
- `testClearHistory()` — 清除全部搜索历史
- `testDeleteSingleHistory()` — 删除单条搜索历史
- `testPopularTags_shows8()` — 热门标签最多显示 8 个
- `testTagClick_triggersSearch()` — 点击标签触发搜索
- `testEmptyResults_showsHint()` — 无结果时 showsEmptyState 为 true

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/SearchViewModelTests 2>&1 | tail -5
# 期望：Test Suite 'SearchViewModelTests' passed
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

## M6: 后端核心服务

### E1: Go API 框架

#### M6-E1-T1: chi 路由 + 中间件

**描述**：实现 Go API 框架（参考架构文档 3.2 节 API 层和 5.1 节完整 API 列表）：

`internal/api/router.go`：使用 chi 定义所有路由。路由分组：
- `/health` — 健康检查（无认证）
- `/api/v1/auth/*` — 认证相关（无认证）
- `/api/v1/*` — 其余所有接口（需认证）

中间件：
1. `middleware/auth.go`：JWT 认证中间件。从 `Authorization: Bearer xxx` 提取 Token，验证签名和过期时间，提取 user_id 注入 `context.Context`
2. `middleware/ratelimit.go`：基于 Redis 的限流中间件。不同接口不同限制（登录 5次/分钟、抓取 10次/分钟、搜索 30次/分钟、通用 60次/分钟）
3. `middleware/cors.go`：CORS 配置
4. `middleware/logger.go`：请求日志（使用 `slog`）

更新 `cmd/server/main.go`：初始化配置、数据库连接池、Redis 连接、注册路由、启动 HTTP 服务器和 Worker。

**前置**：M0-E2-T3, M1-E3-T2

**产出**：
- `server/internal/api/router.go`
- `server/internal/api/middleware/auth.go`
- `server/internal/api/middleware/ratelimit.go`
- `server/internal/api/middleware/cors.go`
- `server/internal/api/middleware/logger.go`
- `server/cmd/server/main.go`（更新）

**验收**：
- `go build ./cmd/server` 成功
- 启动后 `/health` 返回 200
- 无 Token 访问 `/api/v1/*` 返回 401
- 限流超过阈值返回 429

**测试**：
测试文件：
- `server/internal/api/middleware/auth_test.go`
- `server/internal/api/middleware/ratelimit_test.go`
- `server/internal/api/router_test.go`
测试用例（auth_test.go）：
- `TestAuthMiddleware_ValidToken()` — 有效 JWT Token 通过中间件，context 中有 user_id
- `TestAuthMiddleware_MissingToken()` — 缺少 Authorization 头返回 401
- `TestAuthMiddleware_InvalidToken()` — 无效 Token 返回 401
- `TestAuthMiddleware_ExpiredToken()` — 过期 Token 返回 401
- `TestAuthMiddleware_MalformedBearer()` — 格式错误的 Bearer 头返回 401
测试用例（ratelimit_test.go）：
- `TestRateLimit_UnderLimit()` — 未超限的请求正常通过
- `TestRateLimit_OverLimit()` — 超限返回 429
- `TestRateLimit_DifferentEndpoints()` — 不同接口有不同的限流阈值
测试用例（router_test.go）：
- `TestHealthEndpoint()` — GET /health 返回 200
- `TestProtectedEndpoint_NoAuth()` — 无认证访问 /api/v1/* 返回 401

验证命令：
```bash
cd server && go test ./internal/api/... -v -count=1 2>&1 | tail -10
# 期望：PASS ok folio-server/internal/api
```

---

### E2: 用户模块

#### M6-E2-T1: Apple ID 登录接口

**描述**：实现 Sign in with Apple 后端验证（参考架构文档 5.2.1 和 5.3 节）：

`handler/auth.go` — `POST /api/v1/auth/apple`：
1. 接收 `identity_token`、`authorization_code`、`user`（name + email）
2. 验证 Apple identity_token（JWT 验证：从 Apple 公钥端点获取公钥，验证签名、audience、issuer、expiry）
3. 提取 Apple User ID（`sub` claim）
4. UserRepo.CreateOrUpdate：如果用户不存在则创建，存在则更新
5. 生成 JWT Access Token（2 小时有效）和 Refresh Token（90 天有效）
6. 返回 tokens + user 信息

`handler/auth.go` — `POST /api/v1/auth/refresh`：
1. 验证 Refresh Token
2. 颁发新 Access Token
3. Refresh Token 不变

`service/auth.go`：封装 Apple JWT 验证、Token 生成逻辑。JWT 使用 HS256 签名，密钥从环境变量 `JWT_SECRET` 获取。

**前置**：M6-E1-T1

**产出**：
- `server/internal/api/handler/auth.go`
- `server/internal/service/auth.go`

**验收**：
- 使用有效的 Apple identity_token 可登录并获取 JWT
- 使用 Refresh Token 可获取新 Access Token
- 无效 Token 返回 401

**测试**：
测试文件：
- `server/internal/api/handler/auth_test.go`
- `server/internal/service/auth_test.go`
测试用例（auth_test.go，使用 httptest）：
- `TestAppleAuth_ValidToken()` — 有效 Apple identity_token 返回 200 + JWT tokens
- `TestAppleAuth_InvalidToken()` — 无效 Apple token 返回 401
- `TestAppleAuth_MissingFields()` — 缺少必要字段返回 400
- `TestAppleAuth_CreatesNewUser()` — 新用户自动创建
- `TestAppleAuth_ExistingUser()` — 已有用户更新登录时间
- `TestRefreshToken_Valid()` — 有效 Refresh Token 返回新 Access Token
- `TestRefreshToken_Expired()` — 过期 Refresh Token 返回 401
- `TestRefreshToken_Invalid()` — 无效 Refresh Token 返回 401
测试用例（auth_test.go service 层）：
- `TestGenerateJWT_ValidClaims()` — JWT 包含正确的 user_id 和 expiry
- `TestVerifyJWT_ValidSignature()` — 验证签名成功
- `TestVerifyJWT_WrongSecret()` — 错误密钥验证失败

验证命令：
```bash
cd server && go test ./internal/api/handler/ -run TestApple -v -count=1 && go test ./internal/service/ -run TestAuth -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

#### M6-E2-T2: 用户信息 + 配额接口

**描述**：实现用户相关接口：

1. `GET /api/v1/user/profile` — 返回用户信息（id、nickname、email、subscription、created_at）
2. `PUT /api/v1/user/profile` — 更新昵称
3. `GET /api/v1/user/quota` — 返回当月用量（monthly_quota、current_month_count、quota_reset_at）

`service/quota.go`：配额管理逻辑：
- Free 用户 30 篇/月，Pro/Pro+ 无限制
- 每月 1 日自动重置计数
- 提交文章时检查配额

**前置**：M6-E2-T1

**产出**：
- `server/internal/api/handler/user.go`
- `server/internal/service/quota.go`

**验收**：
- 登录后可获取用户信息
- Free 用户第 31 次提交返回 403 + 配额超限提示
- Pro 用户无限制

**测试**：
测试文件：
- `server/internal/api/handler/user_test.go`
- `server/internal/service/quota_test.go`
测试用例（user_test.go，使用 httptest）：
- `TestGetProfile_Authenticated()` — 认证用户获取 profile 返回 200
- `TestGetProfile_Unauthenticated()` — 未认证返回 401
- `TestUpdateProfile_ValidNickname()` — 更新昵称返回 200
- `TestUpdateProfile_EmptyNickname()` — 空昵称返回 400
- `TestGetQuota_FreeUser()` — Free 用户返回 monthly_quota=30
- `TestGetQuota_ProUser()` — Pro 用户返回 monthly_quota=-1（无限）
测试用例（quota_test.go）：
- `TestCheckQuota_FreeUnderLimit()` — Free 用户 29 篇，允许
- `TestCheckQuota_FreeAtLimit()` — Free 用户 30 篇，禁止
- `TestCheckQuota_ProNoLimit()` — Pro 用户无限制
- `TestIncrementCount()` — 计数加 1
- `TestResetMonthlyCount()` — 重置计数为 0

验证命令：
```bash
cd server && go test ./internal/api/handler/ -run TestUser -v -count=1 && go test ./internal/service/ -run TestQuota -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

### E3: 文章模块

#### M6-E3-T1: 文章 CRUD 接口

**描述**：实现文章 API（参考架构文档 5.2 节）：

1. `POST /api/v1/articles` — 提交 URL 抓取（参考 5.2.2）：
   - 检查配额
   - URL 去重（同一用户同一 URL 返回 409 + 已有 article_id）
   - 创建 Article 记录（status = pending）
   - 创建 CrawlTask 记录
   - 通过 asynq 入队抓取任务 `article:crawl`
   - 返回 202 + article_id + task_id

2. `GET /api/v1/articles` — 获取文章列表（参考 5.2.5）：
   - 分页（page、per_page，默认 20）
   - 筛选（category、tag、source_type、status、is_favorite）
   - 排序（created_at DESC 默认）
   - 返回列表项（不含 markdown_content，减少传输）

3. `GET /api/v1/articles/:id` — 获取文章详情（参考 5.2.4）：含完整 markdown_content

4. `PUT /api/v1/articles/:id` — 更新文章（收藏、归档、阅读进度等字段）

5. `DELETE /api/v1/articles/:id` — 删除文章（级联删除关联 tags、tasks、R2 图片）

6. `GET /api/v1/tasks/:id` — 查询抓取任务状态（参考 5.2.3）

**前置**：M6-E1-T1, M6-E2-T2

**产出**：
- `server/internal/api/handler/article.go`
- `server/internal/api/handler/task.go`
- `server/internal/service/article.go`

**验收**：
- 提交 URL 返回 202
- 重复 URL 返回 409
- 分页列表返回正确条目数
- 分类和标签筛选正确
- 删除后查询返回 404

**测试**：
测试文件：
- `server/internal/api/handler/article_test.go`
- `server/internal/service/article_test.go`
测试用例（article_test.go，使用 httptest + mock repository）：
- `TestSubmitArticle_Success()` — 提交 URL 返回 202 + article_id + task_id
- `TestSubmitArticle_DuplicateURL()` — 重复 URL 返回 409 + 已有 article_id
- `TestSubmitArticle_QuotaExceeded()` — 配额超限返回 403
- `TestSubmitArticle_InvalidURL()` — 无效 URL 返回 400
- `TestListArticles_DefaultPagination()` — 默认分页返回 20 条
- `TestListArticles_CustomPagination()` — 自定义 page + per_page
- `TestListArticles_FilterByCategory()` — 分类筛选
- `TestListArticles_FilterByTag()` — 标签筛选
- `TestListArticles_FilterBySourceType()` — 来源筛选
- `TestGetArticle_Found()` — 获取文章详情返回 200 + 完整内容
- `TestGetArticle_NotFound()` — 不存在返回 404
- `TestUpdateArticle_Success()` — 更新收藏/归档状态返回 200
- `TestDeleteArticle_Success()` — 删除返回 204
- `TestDeleteArticle_NotFound()` — 不存在返回 404
- `TestGetTaskStatus_Found()` — 查询任务状态返回进度
- `TestGetTaskStatus_NotFound()` — 任务不存在返回 404

验证命令：
```bash
cd server && go test ./internal/api/handler/ -run TestArticle -v -count=1 && go test ./internal/api/handler/ -run TestTask -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

#### M6-E3-T2: 标签和分类接口

**描述**：实现标签和分类 API：

1. `GET /api/v1/categories` — 获取分类列表（含每个分类的文章数量）
2. `GET /api/v1/tags` — 获取用户标签列表（按 article_count 倒序）
3. `POST /api/v1/tags` — 创建自定义标签
4. `DELETE /api/v1/tags/:id` — 删除标签（解除关联，不删除文章）

**前置**：M6-E3-T1

**产出**：
- `server/internal/api/handler/tag.go`
- `server/internal/api/handler/category.go`

**验收**：
- 分类列表返回 9 条预置分类 + 文章计数
- 标签列表正确排序
- 创建和删除标签正常工作

**测试**：
测试文件：
- `server/internal/api/handler/tag_test.go`
- `server/internal/api/handler/category_test.go`
测试用例（tag_test.go，使用 httptest + mock repository）：
- `TestListTags_OrderedByCount()` — 标签按 article_count 倒序
- `TestListTags_Empty()` — 无标签返回空数组
- `TestCreateTag_Success()` — 创建标签返回 201
- `TestCreateTag_Duplicate()` — 重复标签名返回 409
- `TestCreateTag_EmptyName()` — 空标签名返回 400
- `TestDeleteTag_Success()` — 删除标签返回 204
- `TestDeleteTag_NotFound()` — 不存在返回 404
测试用例（category_test.go）：
- `TestListCategories_Returns9()` — 返回 9 条预置分类
- `TestListCategories_WithArticleCounts()` — 每个分类包含文章数量

验证命令：
```bash
cd server && go test ./internal/api/handler/ -run "TestTag|TestCategory" -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

### E4: 异步任务队列

#### M6-E4-T1: asynq Worker 框架

**描述**：实现 asynq 异步任务框架（参考架构文档 3.4 节）：

1. `worker/tasks.go`：定义三种任务类型和 Payload 结构：
   - `article:crawl`（CrawlPayload：ArticleID、URL、UserID）
   - `article:ai`（AIProcessPayload：ArticleID、Title、Markdown、Source、Author）
   - `article:images`（ImageUploadPayload：ArticleID、ImageURLs []string）

2. `worker/server.go`：Worker 服务器配置：
   - 并发数 10
   - 队列优先级：critical 6（抓取）、default 3（AI）、low 1（图片）
   - 错误处理和日志

3. `cmd/server/main.go`：更新，同进程启动 HTTP Server 和 asynq Worker（两个 goroutine）

**前置**：M6-E1-T1

**产出**：
- `server/internal/worker/tasks.go`
- `server/internal/worker/server.go`
- `server/cmd/server/main.go`（更新）

**验收**：
- Worker 启动并连接 Redis
- 手动入队任务后 Worker 接收并执行
- 任务失败自动重试

**测试**：
测试文件：`server/internal/worker/tasks_test.go`
测试用例：
- `TestCrawlPayload_Serialize()` — CrawlPayload JSON 序列化/反序列化正确
- `TestAIProcessPayload_Serialize()` — AIProcessPayload JSON 序列化/反序列化正确
- `TestImageUploadPayload_Serialize()` — ImageUploadPayload JSON 序列化/反序列化正确
- `TestNewCrawlTask_Type()` — 任务类型为 "article:crawl"
- `TestNewAITask_Type()` — 任务类型为 "article:ai"
- `TestNewImageTask_Type()` — 任务类型为 "article:images"
- `TestWorkerConfig_Concurrency()` — Worker 并发数为 10
- `TestWorkerConfig_QueuePriority()` — 队列优先级 critical=6, default=3, low=1

验证命令：
```bash
cd server && go test ./internal/worker/ -run "TestPayload|TestNew|TestWorkerConfig" -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

#### M6-E4-T2: 抓取任务 Handler

**描述**：实现抓取任务处理（参考架构文档 3.4.2 节 CrawlHandler）：

`worker/crawl_handler.go`：
1. 反序列化 CrawlPayload
2. 更新 Article 状态为 processing
3. 调用 ReaderClient.Scrape 获取 Markdown + 元数据
4. 保存抓取结果到 PostgreSQL（title、author、siteName、markdown、coverImage、language、faviconURL）
5. 入队 AI 处理任务 `article:ai`
6. 提取 Markdown 中的图片 URL，入队图片转存任务 `article:images`
7. 抓取失败时更新状态为 failed + 保存错误信息

**前置**：M6-E4-T1, M6-E5-T1

**产出**：
- `server/internal/worker/crawl_handler.go`

**验收**：
- 入队抓取任务后，Reader 被调用，结果写入数据库
- 抓取失败后状态更新为 failed
- AI 任务和图片任务正确入队

**测试**：
测试文件：`server/internal/worker/crawl_handler_test.go`
测试用例（使用 mock ReaderClient 和 mock Repository）：
- `TestCrawlHandler_Success()` — 抓取成功后数据写入数据库，AI 任务和图片任务入队
- `TestCrawlHandler_ReaderFailure()` — Reader 返回错误时文章状态更新为 failed
- `TestCrawlHandler_UpdatesStatus()` — 处理过程中文章状态从 pending → processing
- `TestCrawlHandler_SavesMetadata()` — title、author、siteName 等元数据正确保存
- `TestCrawlHandler_ExtractsImageURLs()` — 从 Markdown 中提取图片 URL 列表
- `TestCrawlHandler_EnqueuesAITask()` — AI 任务入队包含正确的 ArticleID 和 Markdown
- `TestCrawlHandler_EnqueuesImageTask()` — 图片任务入队包含正确的图片 URL 列表

验证命令：
```bash
cd server && go test ./internal/worker/ -run TestCrawlHandler -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

#### M6-E4-T3: AI 处理任务 Handler

**描述**：实现 AI 处理任务（调用 Python AI 服务）：

`worker/ai_handler.go`：
1. 反序列化 AIProcessPayload
2. 调用 AIClient.Analyze 发送到 Python 服务
3. 结果写入 PostgreSQL：category_id（根据返回的 category slug 查找 categories 表）、summary、key_points、ai_confidence
4. 创建/关联标签：遍历 AI 返回的 tags，调用 TagRepo.FindOrCreate 后插入 article_tags
5. 更新 Article 状态为 ready
6. 更新 CrawlTask 状态为 done

**前置**：M6-E4-T1, M6-E5-T2

**产出**：
- `server/internal/worker/ai_handler.go`

**验收**：
- AI 处理完成后文章有分类、标签、摘要
- 标签正确创建和关联
- 文章状态更新为 ready

**测试**：
测试文件：`server/internal/worker/ai_handler_test.go`
测试用例（使用 mock AIClient 和 mock Repository）：
- `TestAIHandler_Success()` — AI 处理完成后文章有 category、tags、summary、key_points
- `TestAIHandler_SetsCategoryBySlug()` — 根据 AI 返回的 category slug 查找并设置 category_id
- `TestAIHandler_CreatesAndAssociatesTags()` — AI 返回的 tags 调用 FindOrCreate 并关联
- `TestAIHandler_UpdatesStatusReady()` — 处理成功后文章状态为 ready
- `TestAIHandler_UpdatesTaskDone()` — 处理成功后 CrawlTask 状态为 done
- `TestAIHandler_AIServiceFailure()` — AI 服务返回错误时文章状态为 failed
- `TestAIHandler_InvalidCategory()` — AI 返回无效分类 slug 时使用默认分类

验证命令：
```bash
cd server && go test ./internal/worker/ -run TestAIHandler -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

#### M6-E4-T4: 图片转存任务 Handler

**描述**：实现图片下载 + R2 上传（参考架构文档 3.4.2 节 Step 4）：

`worker/image_handler.go`：
1. 反序列化 ImageUploadPayload
2. 遍历 ImageURLs，逐个下载图片
3. 上传到 Cloudflare R2（路径：`images/{article_id}/{hash}.{ext}`）
4. 替换 Article 的 markdown_content 中对应的图片 URL 为 R2 URL
5. 更新 PostgreSQL 中的 markdown_content

`client/r2.go`：R2 客户端（S3 兼容 API）：
- Upload(ctx, key, data, contentType) — 上传
- GetPublicURL(key) — 获取公开 URL
- ProxyUpload(ctx, sourceURL, headers) — 代理下载 + 上传（用于微信防盗链）

**前置**：M6-E4-T1

**产出**：
- `server/internal/worker/image_handler.go`
- `server/internal/client/r2.go`

**验收**：
- 图片下载并上传到 R2
- Markdown 中图片链接被替换为 R2 URL
- 微信域名图片带 Referer 头下载

**测试**：
测试文件：
- `server/internal/worker/image_handler_test.go`
- `server/internal/client/r2_test.go`
测试用例（image_handler_test.go，使用 mock R2Client）：
- `TestImageHandler_Success()` — 图片下载并上传到 R2，Markdown 中 URL 被替换
- `TestImageHandler_DownloadFailure()` — 单张图片下载失败不影响其他图片处理
- `TestImageHandler_ReplacesURLInMarkdown()` — Markdown 中图片 URL 正确替换为 R2 URL
- `TestImageHandler_GeneratesCorrectPath()` — R2 路径为 `images/{article_id}/{hash}.{ext}`
- `TestImageHandler_EmptyImageList()` — 无图片时跳过处理
测试用例（r2_test.go，使用 mock S3 API）：
- `TestR2Upload_Success()` — 上传成功返回 key
- `TestR2GetPublicURL()` — 公开 URL 格式正确
- `TestR2ProxyUpload_WechatReferer()` — 微信图片下载时带正确 Referer 头

验证命令：
```bash
cd server && go test ./internal/worker/ -run TestImageHandler -v -count=1 && go test ./internal/client/ -run TestR2 -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

### E5: 外部服务集成

#### M6-E5-T1: Reader 服务客户端

**描述**：实现 Go 调用 Reader 服务的 HTTP 客户端（完整参考架构文档 3.3.3 节）：

`client/reader.go`：
- `ReaderClient` 结构体，baseURL + httpClient（超时 60s）
- `Scrape(ctx, url) (*ScrapeResponse, error)` — POST /scrape，发送 `{url, timeout_ms: 30000}`
- `ScrapeResponse` 包含 Markdown、ReaderMetadata（Title、Description、Author、SiteName、Favicon、OGImage、Language、Canonical）、DurationMs

`service/source.go`：内容源识别（参考架构文档 3.3.4 节）：
- `DetectSource(url) SourceType` — 根据域名判断 wechat/twitter/weibo/zhihu/web

**前置**：M0-E4-T1, M0-E2-T2

**产出**：
- `server/internal/client/reader.go`
- `server/internal/service/source.go`

**验收**：
- 调用 Reader 服务抓取普通网页成功，返回 Markdown
- 正确识别微信/Twitter/微博/知乎链接

**测试**：
测试文件：
- `server/internal/client/reader_test.go`
- `server/internal/service/source_test.go`
测试用例（reader_test.go，使用 httptest mock Reader 服务）：
- `TestReaderClient_Scrape_Success()` — 成功调用返回 Markdown 和 Metadata
- `TestReaderClient_Scrape_Timeout()` — 超时返回错误
- `TestReaderClient_Scrape_ServerError()` — Reader 返回 500 时返回错误
- `TestReaderClient_Scrape_InvalidJSON()` — 返回非法 JSON 时返回解析错误
测试用例（source_test.go，表驱动测试）：
- `TestDetectSource_Wechat()` — `mp.weixin.qq.com` → wechat
- `TestDetectSource_Twitter()` — `twitter.com` 和 `x.com` → twitter
- `TestDetectSource_Weibo()` — `weibo.com` 和 `m.weibo.cn` → weibo
- `TestDetectSource_Zhihu()` — `zhihu.com` 和 `zhuanlan.zhihu.com` → zhihu
- `TestDetectSource_GenericWeb()` — `example.com` → web
- `TestDetectSource_WithPath()` — 带路径的 URL 正确识别域名

验证命令：
```bash
cd server && go test ./internal/client/ -run TestReaderClient -v -count=1 && go test ./internal/service/ -run TestDetectSource -v -count=1 2>&1 | tail -10
# 期望：PASS
```

---

#### M6-E5-T2: AI 服务集成

**描述**：完成 AI 服务两端实现：

**Go 客户端**（参考架构文档 3.4.4 节）：
`client/ai.go`：
- `AIClient`，baseURL + httpClient（超时 30s）
- `Analyze(ctx, AnalyzeRequest) (*AnalyzeResponse, error)` — POST /api/analyze
- AnalyzeRequest：Title、Content、Source、Author
- AnalyzeResponse：Category、CategoryName、Confidence、Tags、Summary、KeyPoints、Language

**Python AI 服务完整实现**（参考架构文档 3.5 节）：
1. `app/main.py`：FastAPI 入口，`POST /api/analyze` 端点
2. `app/pipeline.py`：AIPipeline 类（完整参考 3.5.6 节）——预处理（截断 4000 字）→ 调用 Claude API（单次调用）→ 解析验证 → Redis 缓存
3. `app/prompts/combined.py`：合并分析 Prompt（完整参考 3.5.2 节）——系统 Prompt 定义 9 个分类、标签要求、摘要要求、要点提取要求、JSON 输出格式
4. `app/cache.py`：Redis 缓存（内容 MD5 哈希为 Key，TTL 7 天）
5. `app/models.py`：Pydantic 请求/响应模型

**前置**：M0-E3-T1, M0-E2-T2

**产出**：
- `server/internal/client/ai.go`
- `server/ai-service/app/main.py`（更新完整实现）
- `server/ai-service/app/pipeline.py`（更新完整实现）
- `server/ai-service/app/prompts/combined.py`（更新完整 Prompt）
- `server/ai-service/app/cache.py`（更新完整实现）
- `server/ai-service/app/models.py`（更新完整实现）

**验收**：
- Python 服务启动后 POST /api/analyze 返回正确 JSON
- 返回结果包含 category（在 9 个预定义分类中）、3-5 个 tags、summary（<= 100 字）、3-5 个 key_points
- 相同内容第二次调用命中缓存
- Go 客户端可调用 Python 服务

**测试**：
测试文件：
- `server/ai-service/tests/test_pipeline.py`
- `server/ai-service/tests/test_models.py`
- `server/ai-service/tests/test_cache.py`
- `server/internal/client/ai_test.go`
测试用例（test_pipeline.py，使用 mock Claude API）：
- `test_pipeline_validates_category()` — 返回的 category 在 9 个预定义分类中
- `test_pipeline_returns_tags()` — 返回 3-5 个 tags
- `test_pipeline_returns_summary()` — 返回 summary <= 100 字
- `test_pipeline_returns_key_points()` — 返回 3-5 个 key_points
- `test_pipeline_truncates_long_content()` — 超过 4000 字的内容被截断
- `test_pipeline_detects_language()` — 正确检测中文/英文
- `test_pipeline_handles_api_error()` — Claude API 异常时返回错误
测试用例（test_models.py）：
- `test_analyze_request_validation()` — 请求模型字段校验
- `test_analyze_response_schema()` — 响应模型包含所有必需字段
测试用例（test_cache.py，使用 mock Redis）：
- `test_cache_hit()` — 相同内容命中缓存
- `test_cache_miss()` — 新内容缓存未命中
- `test_cache_ttl_7days()` — 缓存 TTL 为 7 天
测试用例（ai_test.go，使用 httptest mock AI 服务）：
- `TestAIClient_Analyze_Success()` — 成功调用返回分类、标签、摘要
- `TestAIClient_Analyze_Timeout()` — 超时返回错误
- `TestAIClient_Analyze_ServerError()` — 服务端错误返回错误

验证命令：
```bash
cd server/ai-service && pytest -v --tb=short 2>&1 | tail -10
# 期望：passed
cd server && go test ./internal/client/ -run TestAIClient -v -count=1 2>&1 | tail -5
# 期望：PASS
```

---

### E6: Caddy 网关

#### M6-E6-T1: Caddy 反向代理配置

**描述**：配置 Caddy 反向代理（参考架构文档 6.1 节）：

`Caddyfile`：
- 开发模式：`localhost` 反向代理到 `api:8080`
- 生产模式（注释备用）：`api.folio.app` 自动 HTTPS，反向代理到 `api:8080`
- 请求体大小限制 1MB
- 安全头（X-Content-Type-Options、X-Frame-Options 等）

**前置**：M0-E5-T1

**产出**：
- `server/Caddyfile`（更新完整配置）

**验收**：
- docker compose 启动后通过 Caddy 访问 API 正常
- CORS 头正确返回

**测试**：
测试文件：`server/scripts/healthcheck.sh`（更新）
测试用例：
- 验证 docker compose 全部服务启动成功
- 验证通过 Caddy 访问 /health 返回 200
- 验证 CORS 头正确返回（Origin、Methods、Headers）
- 验证安全头存在（X-Content-Type-Options、X-Frame-Options）

验证命令：
```bash
cd server && docker compose up -d && sleep 10 && \
  curl -s -o /dev/null -w "%{http_code}" http://localhost/health && \
  curl -s -I -H "Origin: http://localhost" http://localhost/health | grep -i "access-control" && \
  docker compose down 2>&1 | tail -5
# 期望：200 + access-control 头存在
```

---

## M7: 前后端对接（iOS ↔ 后端联调）

### E1: iOS 网络层

#### M7-E1-T1: APIClient 实现

**描述**：实现 iOS 端 HTTP 客户端 `APIClient`，使用 URLSession + async/await：

1. 基础设施：
   - `baseURL` 配置（开发/生产环境切换）
   - 通用请求方法 `request<T: Decodable>(endpoint:method:body:) async throws -> T`
   - 自动附加 `Authorization: Bearer` 头
   - Token 过期自动刷新（401 → 调用 /auth/refresh → 重试原请求）
   - JSON 编解码（snake_case ↔ camelCase）
   - 错误处理（网络错误、服务端错误、解码错误统一为 `APIError` 枚举）

2. Token 管理：
   - Access Token 和 Refresh Token 存储在 Keychain
   - Token 过期时间存储
   - 刷新锁（防止并发刷新）

**前置**：M0-E1-T2

**产出**：
- `ios/Folio/Data/Network/APIClient.swift`
- `ios/Folio/Data/Network/APIError.swift`
- `ios/Folio/Data/Network/APIEndpoint.swift`
- `ios/Folio/Data/KeyChain/TokenStorage.swift`

**验收**：
- 可发起 GET/POST/PUT/DELETE 请求
- 401 时自动刷新 Token 并重试
- 网络错误返回友好错误信息

**测试**：
测试文件：`ios/FolioTests/Network/APIClientTests.swift`
测试用例（使用 mock URLProtocol）：
- `testGETRequest_success()` — GET 请求成功解码响应
- `testPOSTRequest_success()` — POST 请求成功编码 body 并解码响应
- `testPUTRequest_success()` — PUT 请求成功
- `testDELETERequest_success()` — DELETE 请求成功
- `testAuthorizationHeader_attached()` — 请求自动附加 Bearer Token
- `testTokenRefresh_on401()` — 收到 401 后自动调用 refresh 并重试原请求
- `testTokenRefresh_failedRefresh()` — Refresh Token 也过期时抛出 authenticationRequired 错误
- `testNetworkError_mapped()` — 网络超时映射为 APIError.networkError
- `testServerError_mapped()` — 500 映射为 APIError.serverError
- `testDecodingError_mapped()` — JSON 解码失败映射为 APIError.decodingError
- `testConcurrentRefresh_onlyOnce()` — 并发 401 只触发一次 refresh

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/APIClientTests 2>&1 | tail -5
# 期望：Test Suite 'APIClientTests' passed
```

---

#### M7-E1-T2: 请求/响应模型

**描述**：定义所有 API 请求和响应的 Codable 模型（对应架构文档 5.2 节各接口）：

请求模型：
- `AppleAuthRequest`：identityToken、authorizationCode、user(name + email)
- `SubmitArticleRequest`：url、tags、source
- `UpdateArticleRequest`：isFavorite、isArchived、readProgress

响应模型：
- `AuthResponse`：accessToken、refreshToken、expiresIn、user
- `SubmitArticleResponse`：articleID、taskID、status、estimatedSeconds
- `TaskStatusResponse`：taskID、status、progress(crawl + aiAnalysis)、estimatedSeconds
- `ArticleResponse`：完整文章字段
- `ArticleListResponse`：data [ArticleResponse] + pagination
- `UserProfileResponse`
- `QuotaResponse`
- `CategoryResponse`
- `TagResponse`

**前置**：M7-E1-T1

**产出**：
- `ios/Folio/Data/Network/Models/AuthModels.swift`
- `ios/Folio/Data/Network/Models/ArticleModels.swift`
- `ios/Folio/Data/Network/Models/UserModels.swift`
- `ios/Folio/Data/Network/Models/TagModels.swift`

**验收**：
- 所有模型可正确编解码后端返回的 JSON
- snake_case JSON 字段正确映射为 camelCase Swift 属性

**测试**：
测试文件：`ios/FolioTests/Network/CodableModelsTests.swift`
测试用例：
- `testAuthResponse_decode()` — 解码后端返回的 auth JSON，snake_case → camelCase
- `testSubmitArticleResponse_decode()` — 解码 article 提交响应
- `testTaskStatusResponse_decode()` — 解码任务状态响应
- `testArticleResponse_decode()` — 解码完整文章响应
- `testArticleListResponse_decode()` — 解码文章列表 + 分页信息
- `testUserProfileResponse_decode()` — 解码用户信息响应
- `testQuotaResponse_decode()` — 解码配额响应
- `testCategoryResponse_decode()` — 解码分类响应
- `testTagResponse_decode()` — 解码标签响应
- `testAppleAuthRequest_encode()` — 编码 Apple 登录请求为 snake_case JSON
- `testSubmitArticleRequest_encode()` — 编码文章提交请求
- `testUpdateArticleRequest_encode()` — 编码文章更新请求

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/CodableModelsTests 2>&1 | tail -5
# 期望：Test Suite 'CodableModelsTests' passed
```

---

### E2: Sign in with Apple 全链路

#### M7-E2-T1: iOS Sign in with Apple

**描述**：实现 iOS 端完整 Apple ID 登录流程：

`AuthViewModel`：
1. 使用 `AuthenticationServices` 框架发起 Apple 登录
2. 获取 `identityToken` 和 `authorizationCode`
3. 调用 `APIClient.post("/api/v1/auth/apple", body: AppleAuthRequest)`
4. 保存返回的 Access Token 和 Refresh Token 到 Keychain
5. 更新用户登录状态（`@Published var isLoggedIn: Bool`）

在 Onboarding 页和设置页集成登录按钮。支持"稍后再说"跳过登录（本地功能可用，AI 功能不可用）。

**前置**：M7-E1-T2, M6-E2-T1, M3-E1-T1

**产出**：
- `ios/Folio/Presentation/Onboarding/AuthViewModel.swift`
- `ios/Folio/Presentation/Onboarding/OnboardingView.swift`（更新，集成 Apple 登录）

**验收**：
- 点击"用 Apple ID 继续"弹出 Apple 登录对话框
- 登录成功后获取 Token 并跳转主界面
- 跳过登录后可浏览本地数据

**测试**：
测试文件：`ios/FolioTests/ViewModels/AuthViewModelTests.swift`
测试用例（使用 mock APIClient）：
- `testLogin_success()` — 登录成功后 isLoggedIn=true
- `testLogin_savesTokens()` — 登录成功后 Token 保存到 Keychain
- `testLogin_failure()` — Apple 登录失败时 isLoggedIn=false + errorMessage 有值
- `testLogout_clearsTokens()` — 退出登录清除 Keychain 中的 Token
- `testLogout_updatesState()` — 退出登录后 isLoggedIn=false
- `testSkipLogin_localOnly()` — 跳过登录后 isLoggedIn=false 但可使用本地功能
- `testRestoreLogin_fromKeychain()` — App 启动时从 Keychain 恢复登录状态

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/AuthViewModelTests 2>&1 | tail -5
# 期望：Test Suite 'AuthViewModelTests' passed
```

---

### E3: 文章提交 + 结果同步

#### M7-E3-T1: 文章提交到后端

**描述**：实现文章从 iOS 端提交到后端并获取处理结果的完整链路：

更新 `OfflineQueueManager`：
1. 扫描 pending 状态文章
2. 调用 `APIClient.post("/api/v1/articles", body: SubmitArticleRequest)`
3. 获取 task_id，更新本地 Article 的 serverID
4. 轮询 `GET /api/v1/tasks/{task_id}`（间隔 2 秒，最多 30 次）
5. 任务完成后获取文章详情 `GET /api/v1/articles/{article_id}`
6. 更新本地 SwiftData：title、markdownContent、summary、keyPoints、tags、category、status = ready
7. 更新 FTS5 索引
8. 发送本地通知（"《文章标题》已整理完成"）

处理失败时更新状态为 failed。

**前置**：M7-E1-T2, M3-E4-T1, M5-E1-T1

**产出**：
- `ios/Folio/Data/Network/OfflineQueueManager.swift`（更新，实现 API 调用）
- `ios/Folio/Data/Network/ArticleSyncService.swift`

**验收**：
- Share Extension 保存文章后，联网时自动提交到后端
- 处理完成后本地数据更新（有标题、摘要、标签、分类）
- FTS5 索引更新，可搜索到新文章
- 处理完成发送本地通知

**测试**：
测试文件：`ios/FolioTests/Network/ArticleSyncServiceTests.swift`
测试用例（使用 mock APIClient 和内存 ModelContainer）：
- `testSubmitPending_callsAPI()` — pending 文章调用 POST /api/v1/articles
- `testSubmitPending_savesServerID()` — 提交后本地 Article 的 serverID 更新
- `testPollTask_untilDone()` — 轮询任务状态直到 done
- `testPollTask_timeout()` — 超过最大轮询次数后停止
- `testFetchResult_updatesLocalArticle()` — 获取结果后更新本地 title、summary、tags、category、status
- `testFetchResult_updatesSearchIndex()` — FTS5 索引更新
- `testSubmitFailed_marksAsFailed()` — 提交失败时标记为 .failed
- `testMultiplePending_processesSequentially()` — 多篇 pending 文章按序处理

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ArticleSyncServiceTests 2>&1 | tail -5
# 期望：Test Suite 'ArticleSyncServiceTests' passed
```

---

#### M7-E3-T2: 图片下载到本地

**描述**：文章处理完成后，下载 R2 上的图片到本地缓存：

1. 解析 markdown_content 中的图片 URL（R2 域名）
2. 使用 Nuke 下载图片到本地 `Documents/images/{article_id}/` 目录
3. 替换 Markdown 中的图片 URL 为本地路径
4. 更新 SwiftData 中的 markdownContent
5. 列表页的缩略图使用 Nuke 异步加载 + 内存/磁盘缓存

**前置**：M7-E3-T1, M0-E1-T2

**产出**：
- `ios/Folio/Data/Network/ImageDownloadService.swift`

**验收**：
- 图片下载到本地后离线可查看
- 缩略图加载流畅
- 删除文章时对应图片缓存一并删除

**测试**：
测试文件：`ios/FolioTests/Network/ImageDownloadServiceTests.swift`
测试用例（使用 mock URLSession）：
- `testParseImageURLs_fromMarkdown()` — 从 Markdown 中正确提取 R2 域名图片 URL
- `testDownloadImages_savesToLocal()` — 图片下载到 `Documents/images/{article_id}/` 目录
- `testReplaceURLs_inMarkdown()` — Markdown 中图片 URL 替换为本地路径
- `testUpdateSwiftData_afterReplace()` — 替换后更新 Article 的 markdownContent
- `testDeleteImages_onArticleDelete()` — 删除文章时清除对应图片缓存目录
- `testSkipDownload_nonR2URLs()` — 非 R2 域名的图片 URL 不处理
- `testDownloadFailure_skipsImage()` — 单张图片下载失败不影响其他图片

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/ImageDownloadServiceTests 2>&1 | tail -5
# 期望：Test Suite 'ImageDownloadServiceTests' passed
```

---

### E4: 后台任务 + 通知

#### M7-E4-T1: 后台任务处理

**描述**：完善 BGTaskScheduler 后台任务：

1. 注册 BGProcessingTask（identifier: `com.folio.article-processing`）
2. App 进入后台时提交任务请求
3. 后台任务触发时：
   - 检查 pending 状态文章
   - 逐条提交到后端
   - 轮询结果
   - 更新本地数据
4. 任务完成后调用 `task.setTaskCompleted(success:)`

在 `Info.plist` 中添加 `BGTaskSchedulerPermittedIdentifiers`。

**前置**：M7-E3-T1

**产出**：
- `ios/Folio/App/AppDelegate.swift`（更新，注册后台任务）
- `ios/Folio/Data/Network/OfflineQueueManager.swift`（更新，后台处理逻辑）

**验收**：
- App 进入后台后仍能处理 pending 文章
- 后台处理有时间限制保护

**测试**：
测试文件：无需单独测试文件
验证命令：
```bash
cd ios && xcodebuild build -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -3
# 期望：** BUILD SUCCEEDED **
```

---

#### M7-E4-T2: 本地通知

**描述**：实现本地通知功能：

1. 文章处理完成时发送通知："《文章标题》已整理完成，分类：技术"
2. 处理失败时发送通知："链接抓取失败，点击查看详情"
3. 点击通知跳转到对应文章的阅读页
4. 使用 `UNUserNotificationCenter`
5. 只在 App 不在前台时发送通知

**前置**：M7-E3-T1, M3-E1-T2

**产出**：
- `ios/Folio/Data/Network/NotificationService.swift`
- `ios/Folio/App/AppDelegate.swift`（更新，处理通知点击）

**验收**：
- 后台处理完成后收到通知
- 点击通知跳转到正确文章
- App 在前台时不弹通知

**测试**：
测试文件：`ios/FolioTests/Network/NotificationServiceTests.swift`
测试用例（使用 mock UNUserNotificationCenter）：
- `testSendSuccessNotification()` — 处理成功时发送通知，标题包含文章标题
- `testSendFailureNotification()` — 处理失败时发送通知
- `testNotificationContent_success()` — 成功通知内容包含分类信息
- `testNotificationContent_failure()` — 失败通知内容包含"点击查看详情"
- `testNotification_onlyWhenBackground()` — App 在前台时不发送通知
- `testNotificationUserInfo_containsArticleID()` — 通知 userInfo 包含 articleID 用于跳转
- `testDeepLink_navigatesToArticle()` — 点击通知后可解析出 articleID

验证命令：
```bash
cd ios && xcodebuild test -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:FolioTests/NotificationServiceTests 2>&1 | tail -5
# 期望：Test Suite 'NotificationServiceTests' passed
```

---

## M8: 设置 + 订阅 + 上线打磨

### E1: 设置页

#### M8-E1-T1: 设置页面

**描述**：实现设置页完整 UI（参考交互文档九节设置与账号）：

设置页结构：
1. **账号区域**：头像 + 用户名 + 邮箱 + Apple ID 登录状态。未登录显示 [登录]
2. **订阅区域**：当前方案（Free/Pro/Pro+）+ 本月已用 N/30 篇 + [升级到 Pro →]
3. **数据区域**：
   - iCloud 同步开关（仅 Pro+ 可用）
   - 导出数据 → 导出选择页（Markdown 文件 / JSON 数据）
   - 清除缓存（显示缓存大小）
   - 清除所有数据 → 二次确认
4. **关于区域**：版本号 + 隐私政策 → WebView + 用户协议 → WebView + 反馈与建议 → 邮件
5. **退出登录** 按钮（红色文字）

**前置**：M2-E1-T1, M7-E2-T1

**产出**：
- `ios/Folio/Presentation/Settings/SettingsView.swift`
- `ios/Folio/Presentation/Settings/SettingsViewModel.swift`
- `ios/Folio/Presentation/Settings/DataExportView.swift`

**验收**：
- 设置页所有条目显示正确
- 导出功能可导出 Markdown ZIP 到「文件」App
- 清除缓存可释放图片缓存空间
- 退出登录清除 Token 但保留本地数据

---

### E2: 订阅

#### M8-E2-T1: StoreKit 2 订阅实现

**描述**：使用 StoreKit 2 实现 IAP 订阅（三档方案）：

Product ID：
- `com.folio.pro.monthly`（¥9/月 / $1.49/月）
- `com.folio.pro.yearly`（¥68/年 / $9.99/年）
- `com.folio.proplus.monthly`（¥15/月 / $2.49/月）
- `com.folio.proplus.yearly`（¥128/年 / $19.99/年）

`SubscriptionManager`（ObservableObject）：
1. `loadProducts()` — 加载产品信息
2. `purchase(product:)` — 发起购买
3. `restorePurchases()` — 恢复购买
4. `checkSubscriptionStatus()` — 检查当前订阅状态
5. 监听 `Transaction.updates` 流处理续订和过期
6. 购买成功后调用后端 `POST /api/v1/subscription/verify` 验证收据

**前置**：M7-E1-T1

**产出**：
- `ios/Folio/Data/Subscription/SubscriptionManager.swift`

**验收**：
- 可加载产品列表及价格
- 购买流程完整（StoreKit Testing 环境）
- 恢复购买正常
- 订阅过期后权限降级

---

#### M8-E2-T2: 订阅页面 UI

**描述**：实现订阅选择页面（参考交互文档九节订阅管理）：

三档方案卡片式展示：
1. **Free**（当前方案标记）：每月 30 篇收藏、基础自动分类、本地存储
2. **Pro ¥68/年**（★ 标记）：无限收藏、AI 摘要 & 智能标签、全文搜索、高亮 & 标注。[选择 Pro] 按钮
3. **Pro+ ¥128/年**（★★ 标记）：包含 Pro 全部功能、AI 知识问答、知识周报、iCloud 同步。[选择 Pro+] 按钮

底部：订阅可随时在系统设置中取消 + [恢复购买] 链接

**前置**：M8-E2-T1, M1-E1-T1

**产出**：
- `ios/Folio/Presentation/Settings/SubscriptionView.swift`

**验收**：
- 三档方案正确显示
- 价格从 StoreKit 获取（本地化货币）
- 点击购买触发 IAP 流程

---

#### M8-E2-T3: 后端订阅验证接口

**描述**：实现 `POST /api/v1/subscription/verify`：

1. 接收 App Store Server 的交易信息（transaction ID）
2. 使用 App Store Server API v2 验证交易
3. 确认有效后更新用户 subscription 和 subscription_expires_at
4. 返回更新后的用户信息

**前置**：M6-E2-T2

**产出**：
- `server/internal/api/handler/subscription.go`
- `server/internal/service/subscription.go`

**验收**：
- 有效交易验证通过，用户订阅升级
- 无效交易返回错误

---

### E3: 功能权限控制

#### M8-E3-T1: 功能门控

**描述**：实现基于订阅等级的功能权限控制：

`FeatureGate`：
- `canSave` — Free: 检查月度配额；Pro/Pro+: 无限制
- `canUseAITags` — Free: 否；Pro/Pro+: 是
- `canUseAISummary` — Free: 否；Pro/Pro+: 是
- `canFullTextSearch` — Free: 仅标题搜索；Pro/Pro+: 全文搜索
- `canUseHighlight` — Free: 否；Pro/Pro+: 是
- `canExport` — Free: 否；Pro/Pro+: 是
- `canUseAIChat` — Free/Pro: 否；Pro+: 是
- `canUseiCloudSync` — Free/Pro: 否；Pro+: 是

非 Pro 功能点击时显示底部非模态 banner（参考交互文档十五节免费用户限制交互）："★ 升级 Pro 解锁全文搜索" + [了解详情] [✕]。同一场景 24 小时内不重复提示。

**前置**：M8-E2-T1

**产出**：
- `ios/Folio/Domain/UseCases/FeatureGate.swift`
- `ios/Folio/Presentation/Components/UpgradeBanner.swift`

**验收**：
- Free 用户触碰 Pro 功能时显示升级提示
- 提示关闭后 24 小时内不重复
- Pro/Pro+ 用户所有功能可用

---

### E4: 无障碍

#### M8-E4-T1: VoiceOver + Dynamic Type

**描述**：全面无障碍适配（参考交互文档十七节无障碍设计）：

1. **VoiceOver**：为所有关键元素添加 `.accessibilityLabel`：
   - 文章卡片："文章：{标题}，来源 {来源}，{时间}，{未读/已读}"
   - 分类标签："分类：{分类名}，{数量} 篇文章"
   - 搜索框："搜索收藏内容"
   - 状态徽章、操作按钮等

2. **Dynamic Type**：确保所有文字使用 `.dynamicTypeSize` 修饰符，从 xSmall 到 AX5 全范围支持。避免固定字号。

3. **对比度**：验证所有文字/背景组合满足 WCAG AA（>= 4.5:1）

**前置**：M2-E3-T1, M5-E2-T1, M4-E2-T1

**产出**：
- 更新所有 View 文件，添加 accessibility 修饰符

**验收**：
- 打开 VoiceOver 可完整操作 App
- Dynamic Type 调到最大后所有页面可用
- Accessibility Inspector 无严重警告

---

### E5: 暗色模式

#### M8-E5-T1: 暗色模式全面适配

**描述**：检查并完善所有页面的暗色模式显示：

1. 确认所有颜色使用 M1-E1-T1 定义的 Folio 颜色系统（自动适配 Dark）
2. 背景色 Dark: #1C1C1E
3. 代码块暗色背景适配
4. 图片不反色
5. 分隔线、卡片阴影、标签等细节在暗色下清晰可辨
6. 阅读页在暗色模式下排版舒适

**前置**：M1-E1-T1, M4-E2-T1

**产出**：
- 更新需要调整的 View 和 Color Set

**验收**：
- 所有页面暗色模式下无白色刺眼区域
- 文字对比度达标
- 截图对比所有页面 Light/Dark 效果

---

### E6: 性能审查

#### M8-E6-T1: 性能达标审查

**描述**：按 PRD 第六章性能要求逐项检查并优化：

| 指标 | 要求 |
|------|------|
| App 冷启动 | < 1.5 秒 |
| Share Extension 启动 | < 0.5 秒 |
| 列表首屏加载 | < 0.3 秒（1000 篇收藏） |
| 列表滚动帧率 | 60 fps |
| 阅读页加载 | < 0.3 秒（10000 字文章） |
| 搜索响应 | < 50ms（1000 篇）/ < 200ms（10000 篇） |
| 内存占用 | < 150MB |
| 包大小 | < 30MB |

优化手段：
- 列表使用 `LazyVStack` + 固定高度 Cell
- 图片使用 Nuke 异步加载 + 缩略图
- SwiftData 查询优化（适当索引）
- Markdown 渲染缓存
- Instruments 分析 CPU/Memory/网络热点

**前置**：所有 M2-M7 任务

**产出**：
- 性能优化后的代码更新
- `docs/performance-report.md`（性能测试结果记录）

**验收**：
- 上述所有性能指标达标
- Instruments 无明显 CPU 或内存问题

---

### E7: App Store 素材

#### M8-E7-T1: App Store 素材准备

**描述**：准备 App Store 上线所需素材：

1. **App 图标**：1024×1024 App Icon（Assets.xcassets 中配置全尺寸）
2. **截图**：6 张截图（6.7 英寸 iPhone 15 Pro Max 尺寸 1290×2796），覆盖：
   - 收藏库列表（有数据状态）
   - Share Extension 收藏动作
   - AI 摘要 + 标签
   - 阅读页
   - 搜索页
   - 暗色模式
3. **App 描述文案**：中英文双语（简洁突出"分享链接，知识留住"核心卖点）
4. **关键词**：中英文 App Store 搜索关键词（100 字以内）
5. **隐私政策 URL**：指向隐私政策页面
6. **分类**：Productivity

**前置**：所有 M0-M7 任务

**产出**：
- `ios/Folio/Resources/Assets.xcassets/AppIcon.appiconset/`
- `docs/appstore/screenshots/`（6 张截图）
- `docs/appstore/description_zh.md`
- `docs/appstore/description_en.md`
- `docs/appstore/keywords.md`

**验收**：
- App 图标在各尺寸下清晰
- 截图准确反映 App 功能
- 描述文案简洁有吸引力

---

## 任务总览

### 按里程碑

| 里程碑 | 任务数 | Agent iOS | Agent Backend | 核心产出 |
|--------|--------|-----------|---------------|---------|
| M0: 项目初始化 | 11 | 4 | 7 | 各端项目骨架 + Docker Compose + 数据库 Schema |
| M1: 设计系统 + 数据层 | 9 | 7 | 2 | iOS 设计系统 + SwiftData 模型 + Go Repository |
| M2: 收藏库主界面 | 9 | 9 | — | 列表/卡片/筛选/时间线/手势/空状态 |
| M3: 收藏入口 | 6 | 6 | — | Onboarding + Share Extension + 剪贴板 + 离线队列 |
| M4: 阅读视图 | 6 | 6 | — | Markdown 渲染 + 阅读页 + 偏好 + 进度 |
| M5: 全文搜索 | 3 | 3 | — | FTS5 引擎 + 搜索 UI |
| M6: 后端核心服务 | 12 | — | 12 | API 框架 + 用户/文章/标签接口 + Worker + AI + Reader |
| M7: 前后端对接 | 7 | 7 | 联调协助 | APIClient + Apple 登录 + 文章同步 + 后台任务 + 通知 |
| M8: 上线打磨 | 9 | 8 | 1 | 设置 + 订阅 + 权限 + 无障碍 + 暗色 + 性能 + 素材 |
| **合计** | **72** | **50** | **22** | |

### 按执行阶段

| 阶段 | Agent iOS | Agent Backend | 同步点 |
|------|-----------|---------------|--------|
| Phase 1: 初始化 + 基座 | 11 任务（M0-E1/E6 + M1-E1/E2） | 9 任务（M0-E2~E5 + M1-E3） | → S1: API 契约对齐 |
| Phase 2: 核心功能 | 24 任务（M2 + M3 + M4 + M5） | 12 任务（M6）+ 补充任务 | |
| Phase 3: 前后端对接 | 7 任务（M7） | 联调协助 + E2E 测试 | → S2 进入 / S3 验收 |
| Phase 4: 上线打磨 | 8 任务（M8 iOS 部分） | 1 任务 + 压测/部署 | |

---

## 依赖关系总图（双 Agent 视角）

```
                     Agent iOS                              Agent Backend
                ─────────────────                      ─────────────────────
  Phase 1       M0-E1-T1 ──┬── M0-E1-T2               M0-E2-T1 ── M0-E2-T2 ── M0-E2-T3
  初始化               │    └── M0-E1-T3 ──┐           M0-E3-T1 ─┐
  + 基座               │                   │           M0-E4-T1 ─┼── M0-E5-T1 ── M0-E5-T2
                       │     ┌─ M0-E6-T1   │                     │
                       │     ├─ M1-E1-T1 ─┐│           M1-E3-T1 ─┘            │
                       │     ├─ M1-E1-T2 ─┤│                    └── M1-E3-T2 ◄─┘
                       │     ├─ M1-E1-T3 ─┤│
                       │     │  M1-E1-T4 ◄─┘│
                       │     │  M1-E2-T1 ◄──┘
                       │     │  M1-E2-T2
                       │     │  M1-E2-T3
                       │     │
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ★ S1: API 契约对齐 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                       │     │
  Phase 2        ┌─ M2 (9 tasks) ─┐                   M6-E5-T1 (Reader 客户端)
  核心功能       ├─ M3 (6 tasks)  │                   M6-E5-T2 (AI 集成)
                 ├─ M4 (6 tasks)  │                   M6-E1-T1 ── M6-E2 ── M6-E3
                 └─ M5 (3 tasks)  │                   M6-E4-T1 ── M6-E4-T2~T4
                                  │                   M6-E6-T1
                                  │                      │
                                  │                      │ ← Backend 先完成
                                  │                   补充任务（E2E/文档/搜索API...）
                                  │                      │
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─★ S2: 联调启动 ─ ─ ─ ─┘
                       │
  Phase 3        M7-E1-T1 ── M7-E1-T2                 docker compose up
  对接                    ├── M7-E2-T1 ◄─── Backend M6-E2-T1
                          ├── M7-E3-T1 ── M7-E3-T2    联调协助
                          ├── M7-E4-T1                 E2E 测试
                          └── M7-E4-T2
                       │
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─★ S3: E2E 验收 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                       │
  Phase 4        M8-E1-T1 → M8-E2-T1 → T2             M8-E2-T3 (订阅验证)
  上线打磨       M8-E3-T1, M8-E4-T1, M8-E5-T1         压测 / 部署 / 安全审计
                 M8-E6-T1 → M8-E7-T1
```

**跨 Agent 唯一硬依赖**：M7-E2-T1（iOS Apple 登录全链路）依赖 M6-E2-T1（后端 Apple 登录接口）。其余所有依赖均在 Agent 内部闭合。

---

## 待解决问题清单

> 以下问题通过与 PRD（`docs/design/prd.md`）、系统架构（`docs/architecture/system-design.md`）、交互流程（`docs/interaction/core-flows.md`）交叉审查发现。每个问题需在对应任务开始前解决。
>
> 状态标记：🔴 缺失（需新增任务）| 🟡 模糊（需补充细节）| 🟠 不明确（需产品决策）

---

### 一、缺失的关键任务（🔴 需新增）

#### Issue-01: 数据导出功能没有实现任务

**关联**：M8-E1-T1 设置页产出列了 `DataExportView.swift`，但无独立任务描述导出逻辑。

**待明确**：
- 导出格式：Markdown 文件 / JSON 数据 / 两者都支持？
- 导出形式：ZIP 压缩包还是单文件？
- 导出路径：分享到「文件」App、AirDrop、还是 `UIActivityViewController`？
- 图片是否随导出打包？
- Free 用户 PRD 规定只能单篇导出，Pro 可批量——权限区分逻辑在哪实现？
- 需要新增独立任务 `M8-E1-Tn: 数据导出实现`。

---

#### Issue-02: 缺少「编辑标签 / 修改分类」任务

**关联**：M4-E2-T1 阅读页右上角菜单列出了「编辑标签、修改分类」操作，交互文档也有描述，但没有任何任务覆盖 UI 和逻辑实现。

**待明确**：
- 编辑标签 UI：弹出 Sheet？内联编辑？
- 是否支持从已有标签选择 + 新建标签？
- 修改分类 UI：选择器还是列表？
- 修改后本地和服务端如何同步（M7 阶段）？
- 是否需要在列表页长按菜单中也支持编辑？
- 建议新增 `M4-E2-Tn: 文章标签和分类编辑` 任务。

---

#### Issue-03: 缺少「分享文章」功能任务

**关联**：M4-E2-T1 阅读页底部工具栏 `[📤 分享]`、长按菜单「分享」，均无实现任务。

**待明确**：
- 分享内容是什么？原始链接？Markdown 文本？带 App 水印的卡片图？
- PRD P1 功能提到分享为 Markdown 或原始链接——MVP 中包含哪种？
- 使用 `UIActivityViewController` 还是自定义分享面板？
- 建议新增 `M4-E2-Tn: 文章分享功能` 任务。

---

#### Issue-04: 缺少错误重试机制任务

**关联**：PRD 明确要求「抓取失败的文章可手动重试」，交互文档有失败卡片「重试」按钮，但计划中无覆盖。

**待明确**：
- 失败状态卡片 UI 设计（与正常卡片的区别、重试按钮位置）
- `OfflineQueueManager` 只描述了自动重试，缺少用户手动重试入口
- 自动重试次数上限、指数退避参数（初始间隔、倍数、最大间隔）
- 重试次数耗尽后的终态处理（永久标记 failed？允许再次手动重试？）
- 建议新增 `M3-E4-Tn: 失败重试机制` 任务，覆盖 UI 和逻辑两部分。

---

#### Issue-05: 缺少「清除缓存」和「清除所有数据」实现任务

**关联**：M8-E1-T1 设置页提到两个功能，但没有独立实现任务。

**待明确**：
- 「清除缓存」具体清除什么？Nuke 图片缓存？FTS5 索引？临时文件？
- 缓存大小如何计算并显示？
- 「清除所有数据」的二次确认流程？是否需要输入确认文字（如 "DELETE"）？
- 清除后是否保留登录状态？是否需要重新登录？
- SwiftData 数据库文件如何安全清除并重建？
- 建议新增 `M8-E1-Tn: 数据清理功能实现` 任务。

---

#### Issue-06: 缺少后端搜索 API

**关联**：架构文档 5.2 节定义了 `GET /api/v1/articles/search?q=...`，但 M6-E3-T1 文章 CRUD 接口未包含搜索端点。

**待明确**：
- MVP 阶段后端搜索是否跳过（仅依赖 iOS 本地 FTS5）？
- 如果跳过，需在 M6-E3-T1 中显式标注「后端搜索 API 推迟到 V1.1」
- 如果包含，需新增任务并定义 PostgreSQL `tsvector` / `pg_trgm` 搜索实现

---

#### Issue-07: 缺少 Markdown 内链接点击处理

**关联**：M4-E2-T2 只描述了「原文链接」的 WebView，但阅读页 Markdown 正文中的外部链接点击行为未定义。

**待明确**：
- Markdown 中链接点击是 App 内 WebView 打开、跳转 Safari、还是提供选择？
- 是否支持链接长按「收藏到 Folio」？
- 需在 M4-E1-T1 或 M4-E2-T1 的描述中补充链接点击行为定义。

---

### 二、边界模糊的任务（🟡 需补充细节）

#### Issue-08: M1-E1-T1 暗色模式颜色值不完整

**问题**：Light 模式定义了全部颜色 Hex 值，但 Dark 模式只写了：
> Dark 模式：背景 #1C1C1E，文字 #E5E5E5，其余颜色适配暗色。

**需补充**：以下颜色的 Dark 模式 Hex 值：

| 颜色 | Light 值 | Dark 值（待定义） |
|------|---------|------------------|
| `cardBackground` | #FFFFFF | ? |
| `textSecondary` | #6B6B6B | ? |
| `textTertiary` | #9B9B9B | ? |
| `separator` | #F0F0EC | ? |
| `accent` | #2C2C2C | ? |
| `link` | #4A7C59 | ?（注意：原值在 #1C1C1E 背景上对比度可能不足 4.5:1） |
| `unread` | #5B8AF0 | ? |
| `success` | #5B9A6B | ? |
| `warning` | #C4793C | ? |
| `error` | #C44B4B | ? |
| `tagBackground` | #F2F2ED | ? |
| `tagText` | #4A4A4A | ? |
| `highlightYellow` | #FFF3C4 | ? |
| `highlightGreen` | #D4EDDA | ? |
| `highlightBlue` | #CCE5FF | ? |
| `highlightRed` | #F8D7DA | ? |

---

#### Issue-09: M1-E2-T1 SwiftData 模型多项细节未定义

**问题 1**：`keyPoints([String])` 在 SwiftData 中的存储方式。
- SwiftData 不原生支持 `[String]` 作为持久化属性
- 需要说明：使用 `@Attribute(.transformable(by:))` 自定义 Transformer？还是 JSON 编码为 `String` 再存？

**问题 2**：`syncState` 枚举的状态机未定义。
- 有哪些状态？建议至少：`.notSynced`、`.syncing`、`.synced`、`.syncFailed`、`.localOnly`
- 状态之间的流转规则是什么？
- 什么条件触发状态变化？

**问题 3**：iOS ↔ 后端字段同步范围不清。
- `readProgress`、`lastReadAt`、`isFavorite`、`isArchived` 这些 iOS 本地字段是否同步到后端？
- M7 中未描述这些字段的双向同步策略（仅同步了 AI 处理结果的单向回填）

---

#### Issue-10: M3-E2-T1 Share Extension 120MB 内存限制缺乏实施指导

**问题**：任务提到「严格控制内存（120MB 限制）：不加载主 App 完整依赖」，但缺乏具体指导。

**需补充**：
- Share Extension Target 具体应引用哪些源文件？排除哪些？
- `SharedDataManager` 初始化 SwiftData `ModelContainer` 的内存开销估算
- 两个 Target 共享代码的策略：通过 Target Membership 直接共享、还是抽取 Framework？
- 是否需要 `ModelContainer` 的轻量级初始化模式？
- 建议增加内存 budget 分配表（例：SwiftData ~30MB, SwiftUI ~20MB, 业务逻辑 ~10MB, 系统开销 ~40MB, 余量 ~20MB）

---

#### Issue-11: M3-E2-T2 月度配额的用户等级来源不清

**待明确**：
- 未登录用户算什么等级？按 Free 处理还是不限制本地保存？
- 用户等级信息存储位置：App Group UserDefaults？Keychain？SwiftData？
- 离线时如何判断用户等级？如果本地没有缓存的订阅状态怎么办？
- 卸载重装后 App Group UserDefaults 会被清除，月度计数会重置——这是期望行为还是 bug？
- 如果是 bug，是否需要将配额计数同步到后端作为 source of truth？

---

#### Issue-12: M4-E1-T1 Markdown 渲染引擎任务粒度过大

**问题**：单个任务要求实现所有 Markdown 元素渲染 + 10 种语言语法高亮 + 表格 + 图片自适应，实际工作量相当于 3-4 个独立任务。

**具体问题**：
- `swift-markdown` 库负责解析，但不提供 SwiftUI 渲染——渲染层需完全自定义实现
- 语法高亮：`swift-markdown` 不支持代码高亮。需要额外方案：
  - 方案 A：引入 `Splash` 或 `Highlightr` 等高亮库
  - 方案 B：使用 WKWebView + highlight.js（但与原生渲染混用有性能问题）
  - 方案 C：自定义正则高亮（工作量大）
  - **当前未选定方案**
- 建议拆分为：基础渲染（文本/列表/引用/链接）→ 代码块 + 高亮 → 表格 → 图片

---

#### Issue-13: M5-E1-T1 FTS5 直接操作 SQLite 存在技术风险

**问题**：任务要求「获取 SwiftData 底层 SQLite 数据库路径，直接操作 SQLite API」。

**风险**：
- SwiftData（iOS 17）不官方支持直接操作底层 SQLite，数据库路径可能随系统更新变化
- 并发访问 SwiftData ORM 和原生 SQLite 可能导致数据库锁定（`SQLITE_BUSY`）
- WAL 模式下的并发读写需要小心处理

**需补充**：
- 指定使用的 Swift SQLite 库：`GRDB`（推荐，社区成熟）/ `SQLite.swift` / 原生 C API？
- 并发安全策略：是否使用独立的 `DatabasePool`？写操作是否需要与 SwiftData 串行化？
- 备选方案：如果直接操作 SQLite 不可行，是否考虑独立的 FTS 数据库文件（不共用 SwiftData 的 .store 文件）？
- 需在 M0 或 M1 阶段进行技术验证（Spike），确认方案可行性

---

#### Issue-14: M6-E5-T1 和 M6-E5-T2 缺少测试段落

**问题**：这两个任务（Reader 客户端、AI 服务集成）没有 `**测试**` 段落，不符合文档开头「自验证协议」的要求。全文档 70 个任务中仅此两处缺失。

**需补充**：

M6-E5-T1（Reader 客户端）建议测试：
- `TestReaderClient_Scrape_Success()` — 正常抓取返回 Markdown + 元数据
- `TestReaderClient_Scrape_Timeout()` — 超时返回错误
- `TestReaderClient_Scrape_InvalidURL()` — 无效 URL 返回错误
- `TestDetectSource_Wechat()` — 微信链接识别
- `TestDetectSource_Twitter()` — Twitter/X 链接识别
- `TestDetectSource_Web()` — 普通链接识别

M6-E5-T2（AI 服务集成）建议测试：

Go 客户端：
- `TestAIClient_Analyze_Success()` — 正常返回分类 + 标签 + 摘要
- `TestAIClient_Analyze_Timeout()` — 超时返回错误
- `TestAIClient_Analyze_InvalidResponse()` — 非法 JSON 返回解码错误

Python AI 服务：
- `test_pipeline_success()` — 完整流水线返回正确结构
- `test_pipeline_truncation()` — 超 4000 字内容被截断
- `test_pipeline_cache_hit()` — 相同内容命中 Redis 缓存
- `test_pipeline_invalid_category()` — 无效分类回退到默认
- `test_prompt_output_format()` — 输出符合 JSON Schema
- `test_analyze_endpoint()` — POST /api/analyze 返回 200 + 完整字段

---

#### Issue-15: M7-E1-T1 APIClient 缺少测试段落

**问题**：与 Issue-14 类似，APIClient 没有测试定义。Token 刷新竞态、401 自动重试等复杂逻辑无测试覆盖是高风险。

**需补充**：
- `testRequest_Success()` — 正常请求返回正确响应
- `testRequest_401_AutoRefresh()` — 收到 401 后自动刷新 Token 并重试原请求
- `testRequest_401_RefreshFailed()` — 刷新 Token 也失败时抛出认证错误
- `testRequest_ConcurrentRefresh()` — 多个并发请求同时 401 时只触发一次刷新
- `testRequest_NetworkError()` — 网络不可用时返回友好错误
- `testRequest_DecodingError()` — JSON 解码失败时返回解码错误
- `testRequest_SnakeCaseToCamelCase()` — JSON key 自动转换正确
- `testTokenStorage_SaveAndLoad()` — Token 存取 Keychain 正确

---

#### Issue-16: M7-E3-T1 轮询策略不够健壮

**问题**：任务描述「轮询间隔 2 秒，最多 30 次」（最长 60 秒）。

**待明确**：
- PRD 目标抓取端到端 < 15 秒，为何需要轮询 60 秒？建议调整为：前 10 次间隔 1 秒，后续间隔 3 秒，最多 20 次（~40 秒）
- 30 次轮询后仍未完成的处理方案：标记 failed？切到后台继续轮询？还是停止轮询等推送通知？
- 多篇文章同时处理时的并发轮询策略（串行逐篇？并行但限制并发数？）
- 是否考虑用推送通知替代轮询（后端处理完成后发 APNs 通知 iOS 拉取结果）？
- App 在轮询过程中被切到后台怎么办？中断轮询？还是利用 BGTask 继续？

---

### 三、任务描述不明确（🟠 需产品决策）

#### Issue-17: M2-E6-T1 「紧凑视图」未定义

**问题**：任务描述「两指捏合在列表/紧凑视图间切换」，但「紧凑视图」在所有设计文档中均无定义。

**待明确**：
- 「紧凑视图」的具体样式：只显示标题？缩小卡片间距？去掉摘要和标签？
- 与 M2-E5-T1 时间线视图的关系：列表总共有几种视图模式？（列表/时间线/紧凑 = 3 种？还是列表/紧凑 = 2 种 + 时间线独立切换？）
- 视图模式切换的状态持久化：`@AppStorage` 记住用户上次选择？
- 如果「紧凑视图」定义不清，建议 MVP 阶段砍掉捏合手势，只保留列表/时间线两种视图的按钮切换

---

#### Issue-18: M4-E3-T1 阅读偏好触发方式过于隐蔽

**问题**：唯一触发入口是「长按文章标题区域」，可发现性极低。

**待明确**：
- 是否增加其他入口？如：右上角 `[···]` 菜单中的「阅读偏好」选项、底部工具栏的 `[Aa]` 按钮
- 是否需要首次进入阅读页时的操作提示（Tooltip / Coach Mark）？
- 交互文档中是否有更好的入口定义？如果有，需更新任务描述

---

#### Issue-19: M7-E2-T1 未登录模式边界不清

**问题**：任务提到「支持'稍后再说'跳过登录（本地功能可用，AI 功能不可用）」，但多个场景的行为未定义。

**待明确**：
- 未登录时 Share Extension 是否可用？（可保存到本地但不触发后端处理？）
- 未登录用户后来登录后，之前本地保存的 pending 文章是否自动提交到后端？
- 未登录用户的月度配额：不限制本地保存？还是按 Free 30 篇限制？
- 设置页未登录状态的 UI：显示什么？账号区域显示「未登录」+ [登录] 按钮？
- 未登录时「搜索」Tab 中的热门标签来源（没有 AI 标签，只有用户手动创建的？）
- 需要在 M3-E2-T1、M3-E2-T2、M7-E2-T1、M8-E1-T1 中分别补充未登录状态的行为定义

---

#### Issue-20: M8-E2-T1 订阅价格与 PRD 不一致

**问题**：计划新增了月付方案（`com.folio.pro.monthly` ¥9/月），但 PRD 只定义了年付价格（Pro ¥68/年、Pro+ ¥128/年）。

**待确认**：
- 月付方案是计划作者新增的还是 PRD 遗漏的？
- 如果新增月付，PRD 和交互文档需同步更新
- 月付定价（¥9/月 vs ¥68/年 ≈ ¥5.7/月）是否合理？通常月付应该更贵以鼓励年付
- 如果 MVP 只做年付，需从任务中删除两个月付 Product ID

---

#### Issue-21: M8-E2-T3 App Store Server API 验证实现细节不足

**问题**：任务仅 4 行描述，但 App Store Server API v2 验证实现非常复杂。

**需补充**：
- Go 语言没有 Apple 官方 SDK，用什么库？自行实现 JWT 签名 + JWKS 验证？还是社区库如 `awa/go-iap`？
- Sandbox vs Production 环境切换策略及配置
- 收据验证失败后的降级逻辑（用户已付费但验证失败时不应降级功能）
- App Store Server-to-Server 通知的处理（续订、退款、撤销、账单重试）——是否需要新增 Webhook 端点？
- 需补充测试用例覆盖 Sandbox 签名验证

---

### 四、架构层面遗漏（🟡 需补充任务或决策）

#### Issue-22: 没有日志 / 埋点 / 监控任务

**问题**：PRD 明确要求追踪关键事件（首次打开、首次收藏、抓取成功/失败、搜索行为、D7 留存、Paywall 曝光、购买转化等），但 70 个任务中无任何 Analytics 相关内容。

**待明确**：
- MVP 是否集成埋点？如果是，用什么方案（自建？Mixpanel？Amplitude？Firebase Analytics？）
- 如果 MVP 不做，需显式标注「埋点推迟到 V1.1」
- 后端 Go 服务的日志和监控：`slog` 日志收集到哪里？是否需要告警？
- 错误追踪（Crash Report）：Xcode Organizer？Sentry？Firebase Crashlytics？

---

#### Issue-23: 没有数据库迁移版本管理策略

**问题**：M0-E5-T2 创建了 `001_init` 迁移文件，但缺乏后续迁移管理方案。

**待明确**：
- 后端 `golang-migrate`：生产环境是手动执行还是 App 启动自动迁移？
- 迁移文件编号规则：时间戳？递增数字？
- iOS 端 SwiftData：是否使用 `VersionedSchema` + `SchemaMigrationPlan`？如果 V1.1 需要加字段怎么迁移？
- 建议在 M0 中新增 `M0-E5-Tn: 数据库迁移执行策略` 任务

---

#### Issue-24: 没有 CI/CD 任务

**问题**：70 个任务中无持续集成 / 持续部署配置。

**建议评估是否需要**：
- GitHub Actions：iOS 构建 + 测试、Go 测试、Python 测试
- Xcode Cloud 或 Fastlane：自动化 TestFlight / App Store 分发
- Docker 镜像自动构建和推送
- 如果 MVP 阶段跳过，需显式标注

---

#### Issue-25: iOS 端 Category 模型缺少 `slug` 字段

**问题**：M1-E2-T1 的 iOS `Category` 模型定义了 `id`、`name`、`icon`、`articleCount`、`createdAt`，但后端 Category 有 `slug` 字段（如 `tech`、`product`）用于 API 通信。

**影响**：M7 前后端对接时，iOS 收到后端返回的 `category: "tech"`（slug），无法映射到本地 Category 实体。

**建议**：在 M1-E2-T1 的 `Category` 模型中增加 `slug: String` 字段，并确保 9 条预置分类的 slug 与后端 `migrations/001_init.up.sql` 一致。

---

#### Issue-26: iCloud 同步无实现任务但 UI 中存在

**问题**：M8-E1-T1 设置页有「iCloud 同步开关（仅 Pro+ 可用）」，M8-E3-T1 `FeatureGate` 有 `canUseiCloudSync` 权限，但整个计划中没有 CloudKit 同步实现任务。

**待明确**：
- iCloud 同步是 MVP 范围内还是范围外？
- 如果范围外：设置页中应该移除此选项，或显示为「即将推出」灰色状态
- 如果范围内：需新增至少 2-3 个任务（CloudKit 容器配置、同步状态机、冲突解决策略）
- 建议 MVP 阶段标记为「即将推出」，不实现同步逻辑

---

### 五、测试策略薄弱环节（🟡 需加强）

#### Issue-27: 大量 UI 任务缺少功能测试

**问题**：以下任务仅有 `xcodebuild build` 编译检查，没有 ViewModel 或逻辑层测试：

| 任务 ID | 任务名称 | 建议补充 |
|---------|---------|---------|
| M2-E1-T1 | 三 Tab 导航框架 | 验证 Tab 切换状态保持 |
| M2-E3-T3 | 空状态视图 | 验证空状态显示条件判断逻辑 |
| M2-E5-T1 | 时间线视图 | 验证按月/日分组逻辑、折叠/展开状态 |
| M2-E6-T1 | 列表手势操作 | 验证删除确认、已读切换状态变更 |
| M3-E1-T1 | 欢迎引导页 | 验证 `@AppStorage("hasCompletedOnboarding")` 状态流转 |
| M3-E1-T2 | 通知权限请求 | 验证权限请求结果处理 |
| M4-E1-T2 | 图片查看器 | 验证缩放范围限制（min/max zoom） |
| M4-E2-T2 | 原文 WebView | 验证 URL 加载和导航状态管理 |

至少 M2-E5-T1（时间线分组）和 M2-E6-T1（手势操作引发的数据变更）应该补充 ViewModel 单元测试。

---

#### Issue-28: 端到端集成测试缺失

**问题**：自验证协议表格中列出了「端到端集成」类型使用 `scripts/e2e-test.sh`，但全文没有任何任务创建这个脚本或定义 E2E 测试用例。

**核心链路缺少 E2E 覆盖**：
1. Share Extension 保存 URL → iOS 本地 SwiftData 写入 → 后端提交 → Reader 抓取 → AI 处理 → 结果回写 iOS → FTS5 索引更新 → 列表显示
2. 用户搜索 → FTS5 查询 → 结果展示 → 点击进入阅读页 → Markdown 渲染

**建议**：在 M7 或 M8 中新增 `Mn-En-Tn: 端到端集成测试脚本` 任务，至少覆盖后端链路：`POST /articles` → 轮询 task → `GET /articles/{id}` 验证结果完整。

---

### 问题统计

| 类别 | 数量 | 风险等级 |
|------|------|---------|
| 🔴 缺失的关键任务 | 7 | **高** — 需新增任务 |
| 🟡 边界模糊的任务 | 9 | **高** — 需补充细节后才能开始实现 |
| 🟠 描述不明确的任务 | 5 | **中** — 需产品决策 |
| 🟡 架构层面遗漏 | 5 | **中** — 需决策是否纳入 MVP |
| 🟡 测试策略薄弱 | 2 | **中** — 需补充测试定义 |
| **合计** | **28** | |

**建议处理顺序**：先处理🟠产品决策类（Issue-17/18/19/20/21/22/26），因为它们影响任务定义；再补充🔴缺失任务（Issue-01~07）；最后细化🟡模糊边界（Issue-08~16/23~25/27/28）。

---

## 更新记录

| 日期 | 版本 | 变更 |
|------|------|------|
| 2026-02-20 | 1.0 | 创建 MVP 全栈任务规划，9 个里程碑，70 个任务 |
| 2026-02-20 | 1.1 | 新增「待解决问题清单」，交叉审查发现 28 个待解决问题 |
| 2026-02-20 | 2.0 | **重构为双 Agent 并行执行计划**：拆为 Agent iOS（50 任务）+ Agent Backend（22 任务），定义 4 个 Phase + 3 个同步点，添加 Backend 空闲期补充任务列表，更新任务总览和依赖关系图 |
