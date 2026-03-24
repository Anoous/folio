# Folio v3.0 — 全栈实现提示词

> 将本文件完整粘贴到 AI 会话作为首条消息。AI 需先阅读所有引用文件，再输出实施方案。

---

## 你的角色

你是一位资深全栈工程师（iOS + Go），同时具备顶级产品经理的系统设计能力。你将基于 **已完成的 UI 原型** 和 **已运行的 MVP 代码**，设计并实现 Folio v3.0 的数据库、API 和全栈功能。

你的核心职责：**在现有代码上增量演进，而不是推倒重写。**

---

## 一、产品背景（必须内化）

### 定位转变

```
v2.0："分享链接，知识留住"（工具 → 用完就走）
v3.0："Folio 记得。然后帮你也记得。"（资产 → 越用越值钱）
```

### 三个动词

| 动词 | 含义 | 对应功能 | 现有代码状态 |
|------|------|----------|-------------|
| **存** | 零摩擦保存 + AI 自动阅读理解 | 洞察级摘要、分类、标签 | ✅ 已有 AI 分析管线，需改 prompt 风格 |
| **记** | 间隔重复 + 主动回忆 | Echo 卡片、间隔算法 | ❌ 全新功能 |
| **用** | RAG 问答 + 语义搜索 | 向量嵌入、RAG 端点 | ❌ 全新功能（仅有 FTS5 关键词搜索）|

### 飞轮

存得越多 → Echo 问题越精准 → 记住得越多 → RAG 回答越准 → 越想存

### 订阅模型（从三层砍为两层）

| | Free | Pro（¥98/年） |
|---|------|------|
| 收藏 + AI 摘要 | ✅ 无限 | ✅ 无限 |
| 搜索 | 关键词 | 关键词 + 语义 |
| Echo | 3 次/周 | 每日 + 完整间隔重复 |
| RAG 问答 | 5 次/月 | 无限 |
| 知识地图 | ❌ | ✅ |
| iCloud 同步 | ❌ | ✅ |
| 存储 | 1 GB | 无限 |

**关键变化**：AI 摘要从 Pro 功能降为 Free（成本 ~$0.03/月/用户，可承受）。原 `pro_plus` 全部合并到 `pro`。

---

## 二、你需要阅读的文件（按顺序）

### 第一组：设计与产品（理解"做什么"）

| # | 文件 | 读什么 |
|---|------|--------|
| 1 | `docs/design/prototypes/README.md` | 完整交互层次结构 + 10 个原型的导航关系 |
| 2 | `docs/design/product-vision.md` | 产品愿景、杀手场景、竞品对比 |
| 3 | `docs/superpowers/specs/2026-03-22-product-vision-redesign.md` | 设计决策（订阅重构、冷启动、Echo 机制） |
| 4 | `docs/design/ui-design-brief.md` | 设计系统 token（颜色、字体、动画、间距） |

### 第二组：HTML 原型（理解"长什么样"+ 数据需求）

每个原型都是完整可交互的 HTML 文件。**阅读时重点关注：每个 UI 元素需要哪些数据字段、每个用户操作需要什么 API 调用。**

| # | 原型文件 | 核心数据需求 |
|---|---------|-------------|
| 5 | `docs/design/prototypes/01-home-feed.html` | 文章卡片字段、时间分组逻辑、Hero 卡片条件、Echo 卡片穿插、6 种状态（空/首篇/正常/处理中/离线/错误） |
| 6 | `docs/design/prototypes/02-echo-interaction.html` | Echo 卡片数据模型（question/answer/source/nextReview）、3 种类型（洞察/高亮/关联）、3 步交互状态机 |
| 7 | `docs/design/prototypes/03-search-and-qa.html` | 搜索结果格式、RAG 回答结构（引文 + 来源溯源 + 跟进对话）、7 种状态 |
| 8 | `docs/design/prototypes/04-reader-full.html` | 洞察面板（折叠/展开）、高亮数据模型、阅读进度、相关收藏、5 种状态 |
| 9 | `docs/design/prototypes/05-knowledge-map.html` | 月度统计聚合、主题分布、Echo 吸收率 |
| 10 | `docs/design/prototypes/06-onboarding.html` | 6 页流程、登录选项 |
| 11 | `docs/design/prototypes/07-settings.html` | Free/Pro/未登录 3 种状态、对比表、存储用量 |
| 12 | `docs/design/prototypes/08-cold-start.html` | 5 个里程碑（1/3/5/10/11 篇）的触发条件和展示数据 |

### 第三组：现有代码（理解"已经有什么"）

| # | 文件 | 读什么 |
|---|------|--------|
| 13 | `CLAUDE.md` | 仓库结构、架构、构建命令、开发环境 |
| 14 | `ios/project.yml` | XcodeGen 配置、依赖、Target 结构 |
| 15 | `ios/Folio/App/FolioApp.swift` | App 入口、ModelContainer、环境注入 |
| 16 | `ios/Folio/Domain/Models/Article.swift` | SwiftData Article 模型（字段、枚举、状态机） |
| 17 | `ios/Folio/Domain/Models/Article+Actions.swift` | 乐观更新 + 服务端同步模式 |
| 18 | `ios/Folio/Domain/Models/Category.swift` | 分类模型 |
| 19 | `ios/Folio/Domain/Models/Tag.swift` | 标签模型 |
| 20 | `ios/Folio/Presentation/Home/HomeView.swift` | 当前 Home 实现（扁平列表、inline 搜索） |
| 21 | `ios/Folio/Presentation/Home/ArticleCardView.swift` | 当前卡片样式 |
| 22 | `ios/Folio/Presentation/Reader/ReaderView.swift` | 当前 Reader（Markdown 渲染、摘要折叠、进度追踪） |
| 23 | `ios/Folio/Presentation/Onboarding/OnboardingView.swift` | 当前引导流程 |
| 24 | `ios/Folio/Presentation/Settings/SettingsView.swift` | 当前设置页 |
| 25 | `ios/Folio/Data/Network/Network.swift` | APIClient + 全部 DTO |
| 26 | `ios/Folio/Data/SwiftData/DataManager.swift` | SwiftData schema 注册 |
| 27 | `ios/Folio/Data/Sync/SyncService.swift` | 同步逻辑（增量/全量） |
| 28 | `server/internal/api/router.go` | 当前 15 个 API 路由 |
| 29 | `server/internal/domain/article.go` | 后端 Article 领域模型 |
| 30 | `server/internal/domain/user.go` | 后端 User 模型（含 pro_plus） |
| 31 | `server/internal/domain/task.go` | CrawlTask 模型 |
| 32 | `server/internal/domain/content_cache.go` | 内容缓存模型 |
| 33 | `server/internal/client/ai.go` | DeepSeek AI 分析 prompt + 响应解析 |
| 34 | `server/migrations/001_init.up.sql` | 当前数据库 schema（6 表） |

---

## 三、实现范围与优先级

### P0 — 必须实现（MVP 升级）

| 功能 | 原型参考 | iOS 端变更 | 后端变更 |
|------|---------|-----------|---------|
| **Home Feed 升级** | 01 | 时间分组 + Hero 卡片 + 洞察引文样式（pull quote：衬线斜体 + accent 竖线）+ 日期行 | AI prompt 调整：summary 改为一句洞察风格 |
| **Reader 升级** | 04 | 洞察面板（折叠区含 keyPoints + 关联提示）+ 导航栏下阅读进度条 + Sheet 式更多菜单 | 无新端点 |
| **Onboarding 更新** | 06 | 文案全换为"Folio 记得"+ 4 页→登录→开始 | 无 |
| **订阅重构** | 07 | 移除 pro_plus 枚举 + 两层对比表 UI | DB migration: `pro_plus → pro` + 移除三层逻辑 |
| **AI 摘要降级为 Free** | 07, 08 | 移除 AI 摘要的订阅检查 | 移除 subscription 校验 |

### P1 — 核心差异化

| 功能 | 原型参考 | iOS 端变更 | 后端变更 |
|------|---------|-----------|---------|
| **Echo 主动回忆** | 01, 02 | 新 SwiftData 模型 `RecallCard` + Echo 卡片 UI + 间隔重复算法 + 穿插在 Feed 中 | Echo 生成 API（基于 key_points）+ 反馈 API + 间隔计算 |
| **高亮标注** | 04 | 长按选中→高亮 UI + SwiftData `Highlight` 模型 | 高亮 CRUD API + 同步 |
| **RAG 问答** | 03 | 搜索页升级：短/长查询分流 + RAG 回答 UI（引文 + 来源 + 跟进） | 向量嵌入管线 + RAG 端点 + 对话管理 |
| **知识地图** | 05 | 统计页 UI（月度概览 + 主题分布 + 趋势洞察 + Echo 吸收率） | 统计聚合 API |
| **冷启动策略** | 08 | 里程碑检测（1/3/5/10/11 篇）+ 引导提示 + 试用期逻辑 | 用户进度追踪 + 试用期状态 |

### P2 — 增强体验

| 功能 | 原型参考 | 说明 |
|------|---------|------|
| Widget | 09 | 锁屏/主屏 Widget |
| 转场动画 | 10 | Motion tokens 动效 |
| 截图收藏 | — | iOS Vision OCR |
| 语音捕捉 | — | Speech framework |

---

## 四、你需要输出的交付物

### 交付物 1：现有代码理解确认

用表格形式确认你对以下内容的理解：

| 维度 | 你的理解 |
|------|---------|
| iOS 架构 | 导航结构、状态管理、数据流 |
| 后端架构 | 分层、Worker 管线、AI 分析流程 |
| 数据模型 | 现有表/模型的字段和关系 |
| 已有 vs 缺失 | 哪些功能可复用、哪些需新建 |

### 交付物 2：数据库设计

**基于原型数据需求，设计增量 migration。** 不是重建，是在 `001_init.up.sql` 基础上新增。

要求：
1. 写出完整的 `002_v3_upgrade.up.sql`，包含：
   - 现有表的 ALTER（如 users 表移除 pro_plus、调整 quota 逻辑）
   - 新表 CREATE（Echo/RecallCard、Highlight、RAG 对话等）
   - 必要的索引和约束
   - 数据迁移（pro_plus → pro）
2. 对每个新表/字段，注释说明它对应哪个原型的哪个 UI 元素
3. 同时给出对应的 `002_v3_upgrade.down.sql` 回滚脚本

**新增表参考**（根据原型推导，你需要验证并完善）：

```
echo_cards（Echo 卡片 — 对应原型 02）
├── id, user_id, article_id
├── card_type: 'insight' | 'highlight' | 'related'
├── question, answer, source_context
├── next_review_at, interval_days, ease_factor
├── review_count, correct_count
└── created_at, updated_at

echo_reviews（Echo 回答记录 — 对应原型 02, 05）
├── id, card_id, user_id
├── result: 'remembered' | 'forgot'
├── response_time_ms
└── reviewed_at

highlights（高亮标注 — 对应原型 04）
├── id, article_id, user_id
├── text, start_offset, end_offset
├── color
└── created_at

rag_conversations（RAG 对话 — 对应原型 03）
├── id, user_id
├── created_at, updated_at

rag_messages（RAG 消息 — 对应原型 03）
├── id, conversation_id
├── role: 'user' | 'assistant'
├── content
├── source_article_ids: jsonb
├── created_at

user_milestones（冷启动里程碑 — 对应原型 08）
├── id, user_id
├── milestone_type: '1st_article' | '3rd_article' | ...
├── achieved_at
└── dismissed: boolean
```

### 交付物 3：API 设计

**基于现有 `router.go` 的 15 个端点，设计增量 API。** 格式：

```
METHOD /path
  描述：一句话
  对应原型：XX
  请求：{ field: type }
  响应：{ field: type }
  权限：public | auth | auth+pro
  备注：特殊逻辑说明
```

**必须覆盖的 API**（根据原型推导）：

| 原型 | 需要的新端点 | 说明 |
|------|-------------|------|
| 01 | — | 现有 `GET /articles` 需增加分组参数 |
| 02 | `GET /echos` | 获取今日待回忆卡片 |
| 02 | `POST /echos/{id}/feedback` | 提交记得/忘了 |
| 03 | `POST /rag/query` | RAG 问答 |
| 03 | `POST /rag/followup` | 跟进提问 |
| 04 | `POST /articles/{id}/highlights` | 创建高亮 |
| 04 | `DELETE /articles/{id}/highlights/{hid}` | 删除高亮 |
| 04 | `GET /articles/{id}/highlights` | 获取文章高亮列表 |
| 05 | `GET /stats/monthly` | 月度统计 |
| 05 | `GET /stats/echo` | Echo 吸收率 |
| 07 | — | 现有订阅端点需适配两层模型 |
| 08 | `GET /user/milestones` | 冷启动进度 |

### 交付物 4：P0 实现计划

按以下格式输出每个 P0 功能的实施步骤：

```
## P0.X: 功能名

### 后端
1. [ ] 具体任务（文件路径 + 改什么）
2. [ ] ...

### iOS
1. [ ] 具体任务（文件路径 + 改什么）
2. [ ] ...

### 测试
1. [ ] 具体测试（文件路径）

### 依赖
- 依赖 P0.Y 的 XXX
```

---

## 五、技术约束（必须遵守）

### iOS 端

- Swift 5.9+ / SwiftUI / SwiftData / iOS 17.0+
- **单 NavigationStack，3 个页面（Home、Reader、Settings），不加新页面**
- Echo 卡片在 Home Feed 中原地展开，不跳转
- 知识地图从 Settings 进入，不是独立页面
- RAG 问答在搜索页内完成，不是独立页面
- XcodeGen 管理项目，新增文件后 `xcodegen generate`
- 新增 SwiftData 模型必须注册到 `DataManager.schema`
- 新增 DTO 必须放在 `Network.swift`
- 字体：UI 用 SF Pro，文章标题/洞察/阅读正文用霞鹜文楷（LXGW WenKai TC，App 内嵌）
- 背景色：`#FAF9F6`（暖白），不是 `#FFFFFF`
- 动画参数严格使用设计系统 Motion tokens（settle/quick/ink/exit/slow）

### 后端

- Go 1.24+ / chi v5 / asynq / pgx v5 / PostgreSQL 16
- 架构：Handler → Service → Repository → Domain（不引入新层）
- AI 用 DeepSeek API（改 prompt，不换模型）
- 向量嵌入方案待定（P1，本次先设计接口预留）
- 间隔重复算法待定（P1，本次先用简化版 SM-2）
- 新 migration 文件编号从 `002` 起
- 新路由在 `router.go` 的 protected group 内追加

### 设计规范

- 洞察引文 = **pull quote 样式**：衬线斜体 + 左侧 accent 竖线（`border-left: 3px solid var(--accent)`）
- Echo 卡片 = 居中排版 + 浅灰背景 + `✦ Echo` 标签，**与文章卡片有视觉区分但不突兀**
- 大量留白，每个内容有呼吸空间
- 几乎单色调，accent 蓝只出现在最值得注意的地方

---

## 六、原型 → 功能 → API → 数据库 映射表

这是最关键的对照表。你的设计必须覆盖每一行。

### 原型 01：Home Feed

| UI 元素 | 数据来源 | 现有字段 | 需新增 | API 变更 |
|---------|---------|---------|--------|---------|
| 日期行 "三月二十二日" | 客户端本地时间 | — | — | — |
| 时间分组（今天/昨天/本周…） | `article.created_at` 分组 | ✅ 有 | iOS 端分组逻辑 | `GET /articles` 无需改（客户端分组） |
| Hero 卡片（当天首篇未读） | 第一篇 `readProgress=0 && status=ready` | ✅ 有 | iOS 端筛选逻辑 | — |
| 洞察引文（pull quote） | `article.summary` | ✅ 有（普通摘要） | 需改 AI prompt 风格 | — |
| 支撑要点（caption） | `article.key_points` | ✅ 有 | — | — |
| 缩略图（72×72） | `article.cover_image_url` | ✅ 有 | — | — |
| 收藏标记 ★ | `article.is_favorite` | ✅ 有 | — | — |
| 处理中骨架屏 | `article.status = pending/processing` | ✅ 有 | — | — |
| Echo 卡片（穿插） | `echo_cards` 表 | ❌ | 新表 + 新 API | `GET /echos` |
| 离线 banner | 客户端网络状态 | ✅ 有 | — | — |
| 同步错误 banner | 客户端同步错误 | ✅ 有 | — | — |
| 空状态 | 文章数 = 0 | ✅ 有 | 文案更新 | — |
| 下拉刷新 | SyncService | ✅ 有 | — | — |
| 右滑收藏 / 左滑删除 | — | ✅ 有（反向） | 交换方向 | — |

### 原型 02：Echo 交互

| UI 元素 | 数据来源 | 需新增 | API |
|---------|---------|--------|-----|
| ✦ Echo 标签 | 固定 UI | — | — |
| 问题文字 | `echo_cards.question` | 新表 | `GET /echos` |
| 来源信息 | `echo_cards.source_context` | 新字段 | 同上 |
| "揭晓答案" 按钮 | 客户端状态 | — | — |
| 答案（衬线粗体 + 竖线） | `echo_cards.answer` | 新字段 | 同上 |
| 来源标注 | `article.title` via `echo_cards.article_id` | 关联查询 | 同上 |
| 记得/忘了 按钮 | — | — | `POST /echos/{id}/feedback` |
| 确认行 + 下次时间 | `echo_cards.next_review_at` | 新字段 | 反馈响应返回 |
| 3 种类型切换 | `echo_cards.card_type` | 新枚举 | `?type=insight\|highlight\|related` |

### 原型 03：搜索与问答

| UI 元素 | 数据来源 | 需新增 | API |
|---------|---------|--------|-----|
| 搜索建议 | 最近搜索 + 热门标签 | `search_history` 本地存储 | — |
| 关键词搜索结果 | FTS5 / pg_trgm | ✅ 有 | `GET /articles/search` |
| RAG 回答正文 | LLM 生成 | 新管线 | `POST /rag/query` |
| 行内引注 ¹ ² ³ | 来源文章 ID 列表 | 新结构 | 响应中 `source_articles[]` |
| 来源卡片（可展开） | `article.title + summary` | — | 响应中嵌入 |
| 跟进对话 | 对话上下文 | `rag_conversations` 表 | `POST /rag/followup` |
| URL 检测 | 客户端正则 | ✅ 有 | — |
| 保存为笔记 | `SharedDataManager` | ✅ 有 | — |
| "基于 N 篇收藏" 标签 | 检索结果数 | — | 响应中 `source_count` |

### 原型 04：Reader

| UI 元素 | 数据来源 | 需新增 | API |
|---------|---------|--------|-----|
| 洞察面板收起：✦ + 核心洞察 | `article.summary` | 改 prompt 风格 | — |
| 洞察面板展开：key_points | `article.key_points` | ✅ 有 | — |
| 洞察面板展开：关联提示 | 语义相似文章 | P1（向量嵌入） | `GET /articles/{id}/related` |
| 阅读进度条 | `article.read_progress` | ✅ 有（底部数字） | 需加顶部 UI |
| 高亮选中 | 用户选择文字 | `highlights` 表 | `POST /articles/{id}/highlights` |
| 高亮列表 | `highlights` by article | 新表 | `GET /articles/{id}/highlights` |
| 移除高亮 | — | — | `DELETE /highlights/{id}` |
| 相关收藏（底部） | 相似文章 | P1 | `GET /articles/{id}/related` |
| 更多菜单 Sheet | — | UI 改造 | — |

### 原型 05：知识地图

| UI 元素 | 数据来源 | 需新增 | API |
|---------|---------|--------|-----|
| 月度收藏数 | `COUNT(articles)` WHERE month | 聚合查询 | `GET /stats/monthly` |
| 洞察数 | `COUNT(articles)` WHERE summary IS NOT NULL | 聚合查询 | 同上 |
| 连续天数 | 连续有收藏的天数 | 计算逻辑 | 同上 |
| 主题分布（条形图） | `GROUP BY category` | 聚合查询 | 同上 |
| 趋势洞察 | AI 分析月度阅读趋势 | AI 调用 | 同上 |
| Echo 吸收率 | `echo_reviews` 统计 | 新表 | `GET /stats/echo` |
| 本月 Echo 次数 | `COUNT(echo_reviews)` WHERE month | 同上 | 同上 |
| 记得/忘了 数量 | `GROUP BY result` | 同上 | 同上 |

### 原型 06：Onboarding

| UI 元素 | 变更 | 说明 |
|---------|------|------|
| Page 1 | 文案改为 "Folio 记得。然后帮你也记得。" | 纯 UI |
| Page 2 | "存" — 洞察摘要预览 | 纯 UI |
| Page 3 | "记" — Echo 预览动画 | 纯 UI |
| Page 4 | "用" — RAG 问答预览 | 纯 UI |
| Page 5 | 登录（Apple / Email / 不登录） | ✅ 已有 |
| Page 6 | "开始使用" | 纯 UI |

### 原型 07：Settings

| UI 元素 | 数据来源 | 需新增 | API |
|---------|---------|--------|-----|
| FREE / PRO 徽章 | `user.subscription` | 移除 pro_plus | — |
| 存储用量 | 本地计算 SwiftData 文件大小 | iOS 端逻辑 | — |
| Pro 对比表 | 静态数据 | 纯 UI | — |
| Pro 升级按钮 | StoreKit | ✅ 有（mock） | `POST /subscription/verify` |
| iCloud 同步状态 | NSUbiquitousKeyValueStore | P1 | — |

### 原型 08：冷启动

| UI 元素 | 数据来源 | 需新增 | API |
|---------|---------|--------|-----|
| 里程碑 1（首篇） | `articles.count == 1` | `user_milestones` 表 | `GET /user/milestones` |
| 里程碑 3（首次关联） | `articles.count >= 3` | 关联检测逻辑 | 同上 |
| 里程碑 5（解锁 Echo+RAG） | `articles.count >= 5` | 触发首次 Echo | 同上 |
| 里程碑 10（试用总结） | 统计数据 | 聚合查询 | 同上 |
| 里程碑 11（Free 限制） | `user.subscription == 'free'` && count > 10 | 配额逻辑 | — |
| 升级引导 | — | 纯 UI | — |

---

## 七、现有代码关键结构（速查）

### 后端目录

```
server/internal/
├── api/
│   ├── router.go          # 路由注册（新端点加在这里）
│   ├── handler/           # HTTP handler（每个资源一个文件）
│   └── middleware/auth.go # JWT 中间件（从 context 提取 userID）
├── service/               # 业务逻辑层
├── repository/            # 数据库访问层（pgx）
├── worker/                # asynq 异步任务
│   ├── tasks.go           # 任务类型定义
│   ├── crawler.go         # article:crawl 任务
│   ├── ai.go              # article:ai 任务
│   └── images.go          # article:images 任务
├── client/
│   ├── ai.go              # DeepSeek API（prompt 在这里改）
│   └── reader.go          # Reader 服务客户端
├── domain/                # 领域模型（struct + 枚举）
└── config/config.go       # 环境变量
```

### iOS 目录

```
ios/Folio/
├── App/FolioApp.swift                   # 入口，环境注入
├── Domain/Models/
│   ├── Article.swift                     # @Model，核心模型
│   ├── Category.swift, Tag.swift         # 分类、标签
│   └── DeletionRecord.swift              # 防复活记录
├── Presentation/
│   ├── Home/
│   │   ├── HomeView.swift                # 主页（改这里加分组）
│   │   ├── HomeViewModel.swift           # 数据加载逻辑
│   │   ├── ArticleCardView.swift         # 文章卡片（改这里加洞察引文）
│   │   ├── HomeArticleRow.swift          # 列表行（手势）
│   │   └── HomeSearchResultsView.swift   # 搜索结果（改这里加 RAG）
│   ├── Reader/ReaderView.swift           # 阅读页（改这里加进度条/高亮）
│   ├── Onboarding/OnboardingView.swift   # 引导（改文案）
│   └── Settings/SettingsView.swift       # 设置（改订阅 UI）
├── Data/
│   ├── Network/Network.swift             # APIClient + DTO
│   ├── SwiftData/DataManager.swift       # Schema 注册（新模型加这里）
│   └── Sync/SyncService.swift            # 同步逻辑
└── Presentation/Components/
    ├── Typography.swift                   # 字体 token
    ├── Spacing.swift                      # 间距 token
    └── Color+Folio.swift                  # 颜色 token（改背景色）
```

### 现有 API 端点

```
POST   /api/v1/auth/apple          # Apple 登录
POST   /api/v1/auth/email/code     # 发送验证码
POST   /api/v1/auth/email/verify   # 验证码登录
POST   /api/v1/auth/refresh        # 刷新 token
GET    /api/v1/articles            # 文章列表（分页）
POST   /api/v1/articles            # 提交 URL
POST   /api/v1/articles/manual     # 提交手动内容
GET    /api/v1/articles/{id}       # 文章详情
PUT    /api/v1/articles/{id}       # 更新（收藏/归档/进度）
DELETE /api/v1/articles/{id}       # 删除
GET    /api/v1/articles/search     # 全文搜索
GET    /api/v1/tags                # 标签列表
POST   /api/v1/tags                # 创建标签
DELETE /api/v1/tags/{id}           # 删除标签
GET    /api/v1/categories          # 分类列表
GET    /api/v1/tasks/{id}          # 任务状态
POST   /api/v1/subscription/verify # 订阅验证
```

### 现有数据库表

```
users          — 用户（含 subscription: free/pro/pro_plus）
categories     — 9 个预设分类
articles       — 文章（UNIQUE: user_id + url）
tags           — 标签
article_tags   — 文章-标签关联
crawl_tasks    — 抓取任务状态
activity_logs  — 操作日志
```

---

## 八、工作流程

1. **先读完所有文件**（第二组原型文件重点看数据结构和状态切换）
2. **输出交付物 1**：确认你对现有代码的理解
3. **输出交付物 2**：数据库设计（`002_v3_upgrade.up.sql`）
4. **输出交付物 3**：API 设计（增量端点 + 现有端点变更）
5. **输出交付物 4**：P0 实现计划
6. **等我确认后开始写代码**

### 设计原则

- **增量而非重写**：在现有表上 ALTER，在现有路由上追加，在现有 View 上改造
- **原型是权威**：UI 长什么样以原型为准，数据结构服务于 UI
- **iOS 模型和后端模型对齐**：每个新表对应一个新 SwiftData @Model
- **API 契约先行**：先定 request/response 格式，再分别实现
- **P1 预留接口**：Echo 和 RAG 的接口现在设计，但标注哪些是 P1 才实现的

---

## 九、需要你做的决策（输出时明确说明）

1. **AI prompt 调整策略**：复用 `summary` 字段改风格，还是新增 `insight` 字段？
2. **时间分组**：后端返回 grouped 数据，还是客户端自行分组？
3. **Echo 卡片生成时机**：异步 Worker 生成，还是请求时实时生成？
4. **RAG 接口设计**：流式响应（SSE）还是同步返回？
5. **高亮存储**：基于文本偏移量还是 DOM 锚点？
6. **冷启动里程碑**：服务端追踪还是客户端本地判断？

---

## 十、成功标准

你的设计方案合格的标志：

- [ ] 每个原型中的每个 UI 元素都能找到对应的数据来源
- [ ] 每个用户操作都有对应的 API 端点或本地逻辑
- [ ] 数据库 migration 可以在现有 `001_init` 基础上无损执行
- [ ] iOS SwiftData 模型与后端 domain 模型字段一一对应
- [ ] P0 计划中每个任务都指向具体文件路径
- [ ] 没有引入新页面（Echo/RAG/知识地图 全部融入现有 3 页）
