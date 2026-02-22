# Folio API 契约

**Base URL**: `http://localhost:8080`
**Content-Type**: 所有请求和响应均使用 `application/json`
**鉴权**: 受保护端点需要 `Authorization: Bearer <access_token>` 请求头

---

## 通用错误响应

所有错误返回统一格式：

```json
{ "error": "<message>" }
```

| HTTP 状态码 | 含义 |
|-------------|------|
| 400 | 请求参数错误 / 校验失败 |
| 401 | 缺少或无效的 Token |
| 403 | 无权访问（所有权校验失败） |
| 404 | 资源不存在 |
| 429 | 月度配额已用尽 |
| 500 | 服务器内部错误 |
| 501 | 功能未实现 |

---

## 端点总览

| 方法 | 路径 | 鉴权 | 状态码 | 说明 |
|------|------|------|--------|------|
| GET | `/health` | 否 | 200 | 健康检查 |
| POST | `/api/v1/auth/apple` | 否 | 200 | Apple 登录 |
| POST | `/api/v1/auth/refresh` | 否 | 200 | 刷新令牌 |
| POST | `/api/v1/articles` | 是 | 202 | 提交 URL 收藏 |
| GET | `/api/v1/articles` | 是 | 200 | 文章列表（分页、筛选） |
| GET | `/api/v1/articles/search` | 是 | 200 | 搜索文章 |
| GET | `/api/v1/articles/{id}` | 是 | 200 | 获取文章详情 |
| PUT | `/api/v1/articles/{id}` | 是 | 200 | 更新文章属性 |
| DELETE | `/api/v1/articles/{id}` | 是 | 200 | 删除文章 |
| GET | `/api/v1/tags` | 是 | 200 | 标签列表 |
| POST | `/api/v1/tags` | 是 | 201 | 创建标签 |
| DELETE | `/api/v1/tags/{id}` | 是 | 200 | 删除标签 |
| GET | `/api/v1/categories` | 是 | 200 | 分类列表 |
| GET | `/api/v1/tasks/{id}` | 是 | 200 | 查询任务进度 |
| POST | `/api/v1/subscription/verify` | 是 | 501 | 订阅验证（桩） |

---

## 0. 健康检查

```
GET /health
```

**鉴权**: 无

**响应** `200`:

```json
{ "status": "ok" }
```

---

## 1. Apple 登录

```
POST /api/v1/auth/apple
```

**鉴权**: 无

### 请求

```json
{
  "identity_token": "string — 必填，Apple identity JWT",
  "email": "string | null — 可选，仅首次登录时由客户端传入",
  "nickname": "string | null — 可选，仅首次登录时由客户端传入"
}
```

### 响应 `200`

```json
{
  "access_token": "string — JWT，有效期 2 小时",
  "refresh_token": "string — JWT，有效期 90 天",
  "expires_in": 7200,
  "user": {
    "id": "uuid",
    "apple_id": "string",
    "email": "string | null",
    "nickname": "string | null",
    "avatar_url": "string | null",
    "subscription": "free | pro | pro_plus",
    "subscription_expires_at": "ISO8601 | null",
    "monthly_quota": 30,
    "current_month_count": 0,
    "quota_reset_at": "ISO8601 | null",
    "preferred_language": "string",
    "created_at": "ISO8601",
    "updated_at": "ISO8601"
  }
}
```

---

## 2. 刷新令牌

```
POST /api/v1/auth/refresh
```

**鉴权**: 无

### 请求

```json
{
  "refresh_token": "string — 必填"
}
```

### 响应 `200`

与 Apple 登录响应结构相同。

---

## 3. 提交 URL 收藏

```
POST /api/v1/articles
```

**鉴权**: 必需

### 请求

```json
{
  "url": "string — 必填",
  "tag_ids": ["uuid"],           // 可选，预绑定已有标签
  "title": "string",             // 可选，客户端提取的标题
  "author": "string",            // 可选，客户端提取的作者
  "site_name": "string",         // 可选，客户端提取的站点名
  "markdown_content": "string",  // 可选，客户端提取的正文 Markdown（超过 500KB 自动截断）
  "word_count": 1234             // 可选，客户端统计的字数
}
```

所有新增字段均为可选，不传时行为与原有逻辑一致（向后兼容）。

**客户端内容抓取行为**：
- `markdown_content` 非空时，后端在创建文章时填入内容字段
- 无论是否携带客户端内容，爬取任务始终入队
- 服务端爬取成功 → 覆盖客户端内容
- 服务端爬取失败但文章已有 `markdown_content` → 使用客户端内容进行 AI 分析

### 响应 `202`

```json
{
  "article_id": "uuid",
  "task_id": "uuid"
}
```

**特殊错误**: `429` 月度配额已用尽。

> 提交后后端异步执行：爬取 → AI 分析 → 图片托管。客户端可通过 `GET /api/v1/tasks/{task_id}` 轮询进度。

---

## 4. 文章列表

```
GET /api/v1/articles
```

**鉴权**: 必需

### 查询参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `page` | int | 1 | 页码 |
| `per_page` | int | 20 | 每页条数（最大 100） |
| `category` | string | — | 按分类 slug 筛选 |
| `status` | string | — | `pending` / `processing` / `ready` / `failed` |
| `favorite` | string | — | `true` / `false` |

### 响应 `200`

```json
{
  "data": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "url": "string",
      "title": "string | null",
      "summary": "string | null",
      "cover_image_url": "string | null",
      "site_name": "string | null",
      "source_type": "web | wechat | twitter | weibo | zhihu",
      "category_id": "uuid | null",
      "word_count": 0,
      "is_favorite": false,
      "is_archived": false,
      "read_progress": 0.0,
      "status": "pending | processing | ready | failed",
      "created_at": "ISO8601"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 42
  }
}
```

---

## 5. 文章详情

```
GET /api/v1/articles/{id}
```

**鉴权**: 必需（所有权校验）

### 响应 `200`

```json
{
  "id": "uuid",
  "user_id": "uuid",
  "url": "string",
  "title": "string | null",
  "author": "string | null",
  "site_name": "string | null",
  "favicon_url": "string | null",
  "cover_image_url": "string | null",
  "markdown_content": "string | null",
  "word_count": 1200,
  "language": "string | null",
  "category_id": "uuid | null",
  "summary": "string | null",
  "key_points": ["string"],
  "ai_confidence": 0.85,
  "status": "ready",
  "source_type": "web",
  "fetch_error": "string | null",
  "retry_count": 0,
  "is_favorite": false,
  "is_archived": false,
  "read_progress": 0.0,
  "last_read_at": "ISO8601 | null",
  "published_at": "ISO8601 | null",
  "created_at": "ISO8601",
  "updated_at": "ISO8601",
  "category": {
    "id": "uuid",
    "slug": "tech",
    "name_zh": "科技",
    "name_en": "Technology",
    "icon": "string | null",
    "sort_order": 1,
    "created_at": "ISO8601"
  },
  "tags": [
    {
      "id": "uuid",
      "name": "AI",
      "user_id": "uuid | null",
      "is_ai_generated": true,
      "article_count": 5,
      "created_at": "ISO8601"
    }
  ]
}
```

---

## 6. 更新文章

```
PUT /api/v1/articles/{id}
```

**鉴权**: 必需（所有权校验）

### 请求

所有字段可选，仅传入需要更新的字段：

```json
{
  "is_favorite": true,
  "is_archived": false,
  "read_progress": 0.75
}
```

### 响应 `200`

```json
{ "status": "updated" }
```

---

## 7. 删除文章

```
DELETE /api/v1/articles/{id}
```

**鉴权**: 必需（所有权校验）

### 响应 `200`

```json
{ "status": "deleted" }
```

---

## 8. 搜索文章

```
GET /api/v1/articles/search
```

**鉴权**: 必需

### 查询参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `q` | string | — | **必填**，搜索关键词（标题模糊匹配） |
| `page` | int | 1 | 页码 |
| `per_page` | int | 20 | 每页条数（最大 100） |

### 响应 `200`

```json
{
  "data": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "url": "string",
      "title": "string | null",
      "summary": "string | null",
      "site_name": "string | null",
      "source_type": "web",
      "created_at": "ISO8601"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 3
  }
}
```

---

## 9. 标签列表

```
GET /api/v1/tags
```

**鉴权**: 必需

### 响应 `200`

```json
{
  "data": [
    {
      "id": "uuid",
      "name": "AI",
      "user_id": "uuid",
      "is_ai_generated": false,
      "article_count": 12,
      "created_at": "ISO8601"
    }
  ]
}
```

> 按 `article_count` 降序排列。

---

## 10. 创建标签

```
POST /api/v1/tags
```

**鉴权**: 必需

### 请求

```json
{
  "name": "string — 必填"
}
```

### 响应 `201`

```json
{
  "id": "uuid",
  "name": "string",
  "user_id": "uuid",
  "is_ai_generated": false,
  "article_count": 0,
  "created_at": "ISO8601"
}
```

> 同名标签执行 upsert，不会创建重复项。

---

## 11. 删除标签

```
DELETE /api/v1/tags/{id}
```

**鉴权**: 必需（所有权校验）

### 响应 `200`

```json
{ "status": "deleted" }
```

---

## 12. 分类列表

```
GET /api/v1/categories
```

**鉴权**: 必需

### 响应 `200`

```json
{
  "data": [
    {
      "id": "uuid",
      "slug": "tech",
      "name_zh": "科技",
      "name_en": "Technology",
      "icon": "string | null",
      "sort_order": 1,
      "created_at": "ISO8601"
    }
  ]
}
```

> 按 `sort_order` 升序排列。分类为系统预设，客户端不可增删。

---

## 13. 查询任务进度

```
GET /api/v1/tasks/{id}
```

**鉴权**: 必需（所有权校验）

### 响应 `200`

```json
{
  "id": "uuid",
  "article_id": "uuid | null",
  "user_id": "uuid",
  "url": "string",
  "source_type": "string | null",
  "status": "queued | crawling | ai_processing | done | failed",
  "crawl_started_at": "ISO8601 | null",
  "crawl_finished_at": "ISO8601 | null",
  "ai_started_at": "ISO8601 | null",
  "ai_finished_at": "ISO8601 | null",
  "error_message": "string | null",
  "retry_count": 0,
  "created_at": "ISO8601",
  "updated_at": "ISO8601"
}
```

> 任务状态流转：`queued` → `crawling` → `ai_processing` → `done`。任意阶段失败则转为 `failed`。

---

## 14. 订阅验证（桩）

```
POST /api/v1/subscription/verify
```

**鉴权**: 必需

### 响应 `501`

```json
{ "error": "subscription verification not yet implemented" }
```

---

## JWT 令牌说明

| 字段 | Access Token | Refresh Token |
|------|-------------|---------------|
| 算法 | HS256 | HS256 |
| 有效期 | 2 小时 | 90 天 |
| Issuer | `folio` | `folio` |
| 自定义声明 | `uid` (用户 ID), `type: "access"` | `uid` (用户 ID), `type: "refresh"` |

---

## 异步处理流程

```
客户端 POST /articles
  → 配额检查 → 创建 article (pending) → 创建 crawl_task (queued)
  → 入队 article:crawl (critical 队列)
  → 返回 202 { article_id, task_id }

Worker: article:crawl
  → Reader 服务抓取 → 更新 article 内容字段
  → 入队 article:ai (default 队列)
  → 入队 article:images (low 队列)

Worker: article:ai
  → AI 服务分析 → 更新分类/摘要/关键点 → 创建 AI 标签
  → article.status = ready

Worker: article:images
  → 下载图片 → 上传至 R2 → 替换 markdown 中图片 URL
```
