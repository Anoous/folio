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

```sql
-- articles.url: NOT NULL → nullable
ALTER TABLE articles ALTER COLUMN url DROP NOT NULL;

-- 唯一约束改为 partial index（仅对有 URL 的记录生效）
DROP INDEX articles_user_id_url_idx;  -- 移除原有唯一约束
CREATE UNIQUE INDEX articles_user_id_url_idx ON articles (user_id, url) WHERE url IS NOT NULL;

-- source_type 新增 'manual' 值（无需 DDL，VARCHAR 列直接写入）
```

### iOS SwiftData (Article.swift)

- `url: String` → `String?`（可选）
- `SourceType` 枚举新增 `.manual` case
- 保存校验：`url` 和 `markdownContent` 至少有一个非空

### Go 后端 (domain/article.go)

- `Article.URL`: `string` → `*string`
- `SourceType` 新增常量 `SourceTypeManual = "manual"`

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
  → 校验 content 非空
  → 配额检查（与 URL 文章共享月度配额）
  → 创建 Article:
      url = NULL
      source_type = 'manual'
      markdown_content = content
      title = 用户提供 或 NULL
      status = 'pending'
  → 创建 crawl_task
  → 入队 article:ai（跳过 article:crawl，直接进 AI 分析）
  → 返回 articleId + taskId
```

### Worker 改动

`crawl_handler` 现有逻辑已支持：当 `markdown_content` 非空时跳过 Reader 服务直接进 AI 分析。对于 manual 条目，直接入队 `article:ai` 任务，Worker 几乎无需改动。

AI 服务返回分类、标签、摘要后，更新 Article：
- 若用户未提供 title → 用 AI 生成的 summary 首句或 key_points 第一条作为标题
- `status` → `'ready'`

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
| 未激活 | 单行，显示 placeholder，⬆️ 按钮隐藏或置灰 |
| 激活（有焦点） | 键盘弹起，输入区自动扩展（最高约 6 行），超出可滚动 |
| 有内容 | ⬆️ 按钮高亮可点击 |

**输入时的双重行为**：

```
用户打字
  ├── 实时搜索：上方文章列表过滤为匹配结果
  │   └── 点击结果 → 进入文章详情（搜索完成，输入栏清空）
  │
  └── 按 ⬆️ 发送：
      ├── 内容是单个 URL → POST /api/v1/articles（现有流程）
      └── 纯文本 → POST /api/v1/articles/manual（新流程）
```

**URL 检测逻辑**：使用 `NSDataDetector(.link)` 检测。仅当整段输入是一个 URL（或只含一个 URL 且无其他有意义文本）时走链接流程，否则走文本保存。

**发送后反馈**：
- 输入栏清空，键盘收起
- 新条目立即出现在列表顶部（`status: .pending`，本地先存 SwiftData）
- AI 分析完成后异步更新分类/标签/摘要

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

### 保存流程（纯文本场景）

1. `SharedDataManager` 扩展：新增 `saveManualContent(content:)` 方法
2. 本地创建 Article：`url=nil, sourceType=.manual, markdownContent=content, status=.pending`
3. 跳过客户端内容提取（已有内容）
4. 网络可用时通过 `SyncService` 同步到后端 `POST /api/v1/articles/manual`

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
- 差异：隐藏「在浏览器中打开」按钮（无 URL）

### 搜索

- SQLite FTS5 全文搜索直接覆盖 `markdown_content`，无需额外适配
- 统一输入栏的实时搜索同样命中 manual 条目

## 六、不做的事

- 不做富文本编辑（纯文本输入，Markdown 渲染）
- 不做保存后内容编辑
- 不做图片/文件附件
- 不做笔记间双向链接
- 不做专门的「笔记」分区或筛选器（统一在文章列表中）

## 七、改动范围总结

| 层 | 改动 |
|----|------|
| DB | 1 个 migration：url nullable + partial unique index |
| Go 后端 | 1 个新 handler + service 方法，domain 类型小改 |
| Worker | 几乎不变（复用 AI 分析流程） |
| iOS Model | Article.url 可选，SourceType 新增 .manual |
| iOS UI | 新增 UnifiedInputBar，移除 .searchable()，HomeView 改造 |
| Share Extension | 新增纯文本类型识别 + 保存逻辑 |
| E2E 测试 | 新增 manual content 提交 + AI 分析测试用例 |
