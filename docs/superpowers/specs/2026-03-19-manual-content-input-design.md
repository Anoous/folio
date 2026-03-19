# Manual Content Input — Design Spec

**Date**: 2026-03-19
**Status**: Draft
**Scope**: 支持用户直接粘贴文章内容或记录想法，无需提供 URL

## 背景

Folio 当前的内容收集流程完全围绕 URL：用户分享链接 → 后端抓取 → AI 分析。但有两类场景无法覆盖：

1. **粘贴内容**：用户从微信群、邮件、PDF 等处复制了一段文章，没有可抓取的链接
2. **个人想法**：用户想快速记录一个灵感或思考，作为知识库的一部分

这两类内容的生命周期与文章一致（保存 → AI 分类/标签/摘要 → 搜索），无需新建实体。

## 设计原则

- **极简输入**：从想法到保存只需两步——打字 + 发送
- **零模式切换**：系统自动识别输入类型（URL / 文本），用户不需要选择
- **统一展示**：所有内容（URL 文章、粘贴内容、想法）在同一列表中呈现，走同一条 AI pipeline
- **不做笔记编辑器**：只有输入和保存，没有富文本编辑、保存后修改、版本历史等功能

## 一、数据模型变更

### PostgreSQL

迁移文件：`server/migrations/002_manual_content.up.sql`

```sql
-- articles.url: NOT NULL → nullable
ALTER TABLE articles ALTER COLUMN url DROP NOT NULL;

-- 唯一约束改为 partial index（仅对有 URL 的记录生效）
DROP INDEX idx_articles_user_url;
CREATE UNIQUE INDEX idx_articles_user_url ON articles (user_id, url) WHERE url IS NOT NULL;

-- crawl_tasks.url: NOT NULL → nullable（manual 条目无 URL）
ALTER TABLE crawl_tasks ALTER COLUMN url DROP NOT NULL;
```

回滚文件：`server/migrations/002_manual_content.down.sql`

```sql
-- 删除无 URL 的记录（回滚前需清理）
DELETE FROM crawl_tasks WHERE url IS NULL;
DELETE FROM articles WHERE url IS NULL;

ALTER TABLE crawl_tasks ALTER COLUMN url SET NOT NULL;

DROP INDEX idx_articles_user_url;
CREATE UNIQUE INDEX idx_articles_user_url ON articles (user_id, url);

ALTER TABLE articles ALTER COLUMN url SET NOT NULL;
```

**Manual 条目不做去重**：同一用户可保存多条内容相同的想法，这是合理的（不同时间的相同想法可能有不同语境）。去重仅对 URL 文章保留。

### iOS SwiftData (Article.swift)

- `url: String` → `String?`（可选）
- `SourceType` 枚举新增 `.manual` case，SF Symbol 图标 `"square.and.pencil"`
- 保存校验：`url` 和 `markdownContent` 至少有一个非空
- **SwiftData 迁移**：required → optional 属于轻量级迁移，SwiftData 自动处理，无需手写 migration plan
- **`displayTitle` 适配**：当 `title` 和 `url` 均为 nil 时（manual 条目 AI 未处理前），回退到 `markdownContent` 前 50 字符作为显示标题；若 `markdownContent` 也为空则返回本地化字符串 "Untitled"
- **`SourceType.displayName` 适配**：`.manual` 的 displayName 固定返回通用值（如 "手动输入"）。「我的想法 / 粘贴内容」的区分逻辑放在 `ArticleCardView` 中，根据 `article.wordCount` 判断（因为 `SourceType` 枚举无法访问 Article 的 `wordCount` 属性）
- **`SourceType.detect(from:)` 调用点**：`SharedDataManager` 和 `ArticleRepository` 中创建 manual 条目时直接传 `.manual`，不调用 `detect(from:)`
- **代码影响**：`Article.url` 从 `String` 变为 `String?` 后，所有引用点（`displayTitle` 中的 `URL(string: url)`、`SharedDataManager` 中的 predicate、`SyncService` 中的 `submitArticle` 调用等）需要 optional chaining 适配。约 100+ 处引用，实现时逐一处理
- 新增便捷初始化器：`Article(content: String, title: String?, sourceType: .manual)` — 用于 manual 条目创建，`url` 默认为 nil

### Go 后端 (domain/article.go)

- `Article.URL`: `string` → `*string`
- `SourceType` 新增常量 `SourceTypeManual = "manual"`
- **Repository 影响**：
  - 所有 Scan 调用（`GetByID`、`ListByUser`、`Search` 等）需将 `&a.URL` 改为 pgx nullable 扫描
  - `CreateArticleParams.URL` 和 `CreateTaskParams.URL` 均需从 `string` 改为 `*string`，对应 INSERT 语句适配
  - **Content cache**：`ai_handler.go` 中写入 content cache 时，若 `article.URL == nil` 则跳过缓存写入（manual 内容是用户私有的，不应跨用户缓存）

## 二、API 端点

### 新增：`POST /api/v1/articles/manual`

独立于现有 `POST /api/v1/articles`（URL 提交端点），职责分离，互不干扰。

**Request**:
```json
{
  "content": "碎片化阅读的问题不在于碎片化...",
  "title": "关于阅读习惯的思考",
  "tagIds": ["uuid-1"]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `content` | string | 是 | 文本内容，作为 `markdown_content` 存储 |
| `title` | string | 否 | 不填则由 AI 生成 |
| `tagIds` | string[] | 否 | 关联标签 |

**内容校验**：
- `content` 不能为空或纯空白字符（trim 后检查）
- 最大长度：500KB（与现有 `maxMarkdownContentBytes` 一致，超出则截断并保留 UTF-8 边界）
- 最小长度：1 个非空白字符

**HTTP 响应码**（与现有 `HandleSubmitURL` 一致）：
- `202 Accepted`：成功创建，AI 分析异步进行
- `400 Bad Request`：content 为空 / 纯空白 / 格式错误
- `429 Too Many Requests`：月度配额已满

**Response**（复用现有结构）:
```json
{
  "articleId": "uuid",
  "taskId": "uuid"
}
```

### 后端处理流程

```
POST /api/v1/articles/manual
  → 校验 content 非空（trim 后）、不超过 500KB
  → 配额检查（与 URL 文章共享月度配额）
  → 创建 Article:
      url = NULL
      source_type = 'manual'
      markdown_content = content
      title = 用户提供 或 NULL
      word_count = countWords(content)  // 复用现有 countWords()，正确处理 CJK 字符
      status = 'pending'
  → 创建 crawl_task（url = NULL，用于任务追踪和客户端轮询）
  → 入队 article:ai（跳过 article:crawl，直接进 AI 分析）
  → 返回 articleId + taskId
```

### Worker 改动

**AI Handler 标题回填**：在 `ai_handler.go` 的 `ProcessTask` 方法中，`UpdateAIResult` 之后新增逻辑：

```
if article.Title == nil || *article.Title == "" {
    if len(result.KeyPoints) > 0 {
        title = result.KeyPoints[0]  // 取第一条 key point
    } else {
        title = truncate(result.Summary, 50)  // 取 summary 前 50 字符，在词边界截断
    }
    → UPDATE articles SET title = $1 WHERE id = $2
}
```

仅当 title 为空时才回填，不覆盖用户提供的标题。

**Mock AI 服务**：`mock_ai_service.py` 需更新——当请求无 `source` 字段或 source 为空时，基于 `title` 或 `content` 前 100 字符做关键词匹配，返回确定性响应。

## 三、iOS 统一输入栏

### HomeView 改造

- **移除**顶部 `.searchable()` 搜索栏
- **新增**底部常驻输入栏 `UnifiedInputBar`，锚定在键盘上方

### UnifiedInputBar 组件

```
┌─────────────────────────────────┐
│ 搜索、写想法，或粘贴链接... ⬆️  │
└─────────────────────────────────┘
```

**状态与行为**：

| 状态 | 表现 |
|------|------|
| 未激活 | 单行，显示 placeholder，⬆️ 按钮隐藏 |
| 激活（有焦点） | 键盘弹起，输入区自动扩展（最高约 6 行），超出可滚动 |
| 有内容 | ⬆️ 按钮高亮可点击 |

**输入时的双重行为**：

```
用户打字
  ├── 实时搜索：上方文章列表过滤为匹配结果（300ms debounce）
  │   └── 点击结果 → 进入文章详情（搜索完成，输入栏清空）
  │
  └── 按 ⬆️ 发送：
      ├── 内容是单个 URL → POST /api/v1/articles（现有流程）
      └── 纯文本 → POST /api/v1/articles/manual（新流程）
```

**URL 检测逻辑**：使用 `NSDataDetector(.link)` 检测。仅当整段输入 trim 后是一个 URL（或只含一个 URL 且无其他有意义文本）时走链接流程，否则走文本保存。

**误触保护**：搜索结果显示时，列表顶部出现搜索结果计数（如「找到 3 条结果」），让用户明确知道当前处于搜索状态。⬆️ 发送按钮始终可用——如果用户明确按了发送，视为有意保存，不需要确认弹窗。误保存的成本很低（可在列表中左滑删除），不值得增加摩擦。

**发送后反馈**：
- 输入栏清空，键盘收起
- 新条目立即出现在列表顶部（`status: .pending`，本地先存 SwiftData）
- AI 分析完成后异步更新分类/标签/摘要

### SyncService 路由

`SyncService.submitPendingArticles()` 需根据 `sourceType` 分流：

```swift
if article.sourceType == .manual {
    // 调用新端点
    apiClient.submitManualContent(content: article.markdownContent!, title: article.title)
} else {
    // 现有流程
    apiClient.submitArticle(url: article.url!, ...)
}
```

`APIClient` 新增 `submitManualContent(content:title:tagIds:)` 方法，对应 `POST /api/v1/articles/manual`。

## 四、Share Extension 支持纯文本

### 当前行为

仅识别 `NSExtensionItem` 中的 URL 类型（`public.url`）。

### 改造逻辑

```
Share Extension 收到内容
  ├── 类型是 URL → 现有流程不变
  ├── 类型是 Text，内容是一个 URL → 当作 URL 处理
  └── 类型是 Text，内容是纯文本 → 保存为 manual 条目
```

Text 中的 URL 检测复用与 UnifiedInputBar 相同的 `NSDataDetector(.link)` 逻辑。

### 保存流程（纯文本场景）

1. `SharedDataManager` 新增 `saveManualContent(content:)` 方法
2. 本地创建 Article：使用新的便捷初始化器 `Article(content:title:sourceType:)`，`url=nil, sourceType=.manual, markdownContent=content, status=.pending`
3. 跳过客户端内容提取（已有内容）
4. 网络可用时通过 `SyncService` 路由到 `POST /api/v1/articles/manual`

用户体验与分享链接完全一致：选中文字 → 分享 → 选 Folio → 完成。

## 五、展示与阅读

### 首页卡片

通过 `source_type` 显示不同来源标识，其他展示（分类、标签、摘要、时间）与普通文章一致：

| source_type | 来源显示 |
|-------------|---------|
| `.web` | 域名（如 `zettelkasten.com`） |
| `.wechat` | `微信` |
| `.manual` 短文本（<200字） | `我的想法` |
| `.manual` 长文本（≥200字） | `粘贴内容` |

### ReaderView

点击 manual 条目进入 ReaderView，与文章共用同一页面：
- 标题：用户填写的 / AI 生成的
- 内容：渲染 `markdown_content`
- 差异：隐藏「在浏览器中打开」按钮（`url == nil` 时隐藏）

### 搜索

- SQLite FTS5 全文搜索直接覆盖 `markdown_content`，无需额外适配
- 统一输入栏的实时搜索同样命中 manual 条目

## 六、不做的事

- 不做富文本编辑（纯文本输入，Markdown 渲染）
- 不做保存后内容编辑
- 不做图片/文件附件
- 不做笔记间双向链接
- 不做专门的「笔记」分区或筛选器（统一在文章列表中）
- 不做 manual 条目去重（同一内容可多次保存）

## 七、改动范围总结

| 层 | 改动 |
|----|------|
| DB | `002_manual_content.up/down.sql`：articles.url nullable、crawl_tasks.url nullable、partial unique index |
| Go Domain | `Article.URL` → `*string`，新增 `SourceTypeManual` |
| Go Repository | Scan 调用 + `CreateArticleParams` / `CreateTaskParams` 适配 nullable URL，AI handler 跳过 cache |
| Go Handler | 新增 `HandleSubmitManual` handler + 路由注册 |
| Go Service | 新增 `SubmitManualContent` 方法 |
| Go Worker | `ai_handler` 新增 title 回填逻辑（title 为空时从 AI 结果提取） |
| iOS Model | `Article.url` → `String?`，`SourceType` 新增 `.manual`，新增便捷初始化器 |
| iOS Network | `APIClient` 新增 `submitManualContent` 方法 + DTO |
| iOS Sync | `SyncService` 分流：manual → 新端点，URL → 现有端点 |
| iOS UI | 新增 `UnifiedInputBar`，移除 `.searchable()`，HomeView 底部输入栏改造 |
| iOS 全局 | `Article.url` optional 化：~100+ 处引用需 optional chaining 适配 |
| Share Extension | 新增 `public.plain-text` 类型识别 + `saveManualContent` 调用 |
| Mock AI | `mock_ai_service.py` 支持无 URL 请求的关键词匹配 |
| E2E 测试 | 新增 manual content 提交 + AI 分析 + 标题回填测试用例 |
