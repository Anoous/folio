# 爬取优化设计：内容缓存 + 客户端提取短路

## 问题

1. **客户端已提取内容仍重复爬取**：Share Extension 成功提取 Markdown 后，服务端仍无条件调 Reader 重新爬取，浪费资源
2. **跨用户零复用**：同一 URL 被 N 个用户收藏，触发 N 次独立 Reader 爬取 + N 次 AI 分析，所有字段完全重复存储

## 方案：content_cache 表 + 两层短路

新增 `content_cache` 表缓存已处理的 URL 内容和 AI 结果。`articles` 表不变，内容从缓存复制填充。

### content_cache 表结构

```sql
CREATE TABLE content_cache (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    url             TEXT NOT NULL UNIQUE,
    -- 爬取结果
    title           VARCHAR(500),
    author          VARCHAR(200),
    site_name       VARCHAR(200),
    favicon_url     VARCHAR(500),
    cover_image_url VARCHAR(500),
    markdown_content TEXT,
    word_count      INTEGER,
    language        VARCHAR(10),
    published_at    TIMESTAMPTZ,
    -- AI 分析结果
    category_slug   VARCHAR(50),
    summary         TEXT,
    key_points      JSONB,
    ai_confidence   DECIMAL(3,2),
    ai_tag_names    TEXT[],
    -- 时间戳（可观测性，不参与业务判断）
    crawled_at      TIMESTAMPTZ,
    ai_analyzed_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 处理流程

```
CrawlHandler.ProcessTask:
  │
  ├─ 1. 标记 task started, article status=processing
  │
  ├─ 2. 查 content_cache（按 URL）
  │     ├─ 全命中（有 markdown + 有 AI 结果）
  │     │   → 复制全部字段到 article
  │     │   → 为该用户创建 AI 标签（从 ai_tag_names）
  │     │   → article.status = ready, task.status = done
  │     │   → RETURN（秒级完成）
  │     │
  │     ├─ 部分命中（有 markdown，无 AI）
  │     │   → 复制内容字段到 article
  │     │   → 入队 article:ai
  │     │
  │     └─ 未命中 → 继续
  │
  ├─ 3. 检查 article 是否已有客户端提取的 markdown_content
  │     ├─ 有 → 跳过 Reader，直接入队 article:ai
  │     └─ 没有 → 调 Reader 爬取（现有逻辑）
  │           ├─ 成功 → 更新 article，入队 article:ai + article:images
  │           └─ 失败 → 客户端内容 fallback（现有逻辑）
  │
  └─ 结束

AIHandler.ProcessTask:
  │
  ├─ 正常 AI 分析（不变）
  │
  └─ AI 成功后 → isCacheWorthy() 检查
       ├─ 通过 → UPSERT content_cache
       └─ 不通过 → 不写缓存
```

### 缓存质量门槛

```go
func isCacheWorthy(content string, aiConfidence float64) bool {
    return len(content) >= 200
}
```

MVP 只检查内容长度。函数签名预留 aiConfidence 参数，未来可加更多信号（如 `aiConfidence < 0.3` 则不缓存），调用方不用改。

### 缓存策略

- **无 TTL**：文章是静态内容，发布后不变。缓存只增不删，命中就用
- **质量门槛**：只有通过 `isCacheWorthy` 的结果才写入缓存，避免垃圾内容污染
- **时间戳保留**：`crawled_at`、`ai_analyzed_at` 用于可观测性（排查问题），不参与业务判断
- **模型升级时**：清空 `content_cache` 表即可让所有内容重新处理

### 边界情况

**竞争条件**：两个用户同时保存同一 URL，两个 CrawlHandler 都 miss cache 都走 Reader。AI 完成后都 UPSERT，后写覆盖先写，内容相同无害。

**缓存命中 vs 客户端内容**：缓存优先。缓存是 Reader（无头浏览器）+ AI 的完整结果，质量通过 isCacheWorthy 验证，优于 Share Extension 的 8 秒/120MB 限制下的客户端提取。

**category_slug → category_id**：缓存存 slug，命中时用 `SELECT id FROM categories WHERE slug = $1` 解析，与 AIHandler 现有逻辑一致。

**标签创建**：缓存存 `ai_tag_names` 名称列表，命中时为当前用户创建独立的 tag 实体（UPSERT by user_id + name），与现有 AIHandler 标签逻辑一致。

### 代码改动范围

| 层 | 文件 | 改动 |
|---|---|---|
| 数据库 | `server/migrations/002_content_cache.up.sql` | 新增 content_cache 表 |
| Domain | `server/internal/domain/content_cache.go` | 新增 ContentCache 结构体 + isCacheWorthy |
| Repository | `server/internal/repository/content_cache.go` | 新增 ContentCacheRepo：GetByURL、Upsert |
| Worker | `server/internal/worker/crawl_handler.go` | 增加缓存查询 + 客户端内容短路 |
| Worker | `server/internal/worker/ai_handler.go` | AI 成功后调 contentCacheRepo.Upsert |
| Worker | `server/internal/worker/worker.go` | 注入 ContentCacheRepo 依赖 |
| 启动 | `server/cmd/server/main.go` | 实例化 ContentCacheRepo 并传入 Worker |

**不需要改的**：articles 表、所有 API Handler、所有 DTO、iOS 端。对外接口完全不变。
