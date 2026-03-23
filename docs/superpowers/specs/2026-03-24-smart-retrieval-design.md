# Smart Retrieval — 语义检索基础设施设计

> **日期**: 2026-03-24
> **状态**: Draft
> **解锁功能**: 语义搜索、RAG 问答升级、相关文章推荐

## 1. 背景与动机

Folio v3.0 剩余 8 个功能中，有 3 个依赖检索基础设施：语义搜索、RAG 问答质量提升、Reader 底部相关文章。原计划使用向量嵌入（pgvector + embedding 模型），但经过调研和评估，决定采用更简洁高效的方案。

### 为什么不用 Embedding

1. **精度天花板**：纯 embedding cosine similarity 是信息压缩后的近似匹配，在 BRIGHT benchmark 上，GPT-4 rerank (17.4 nDCG@10) 远优于专用 cross-encoder (13.1)。
2. **基础设施开销**：需要 pgvector 扩展、embedding 模型 API、新 worker 任务、新 Docker 镜像。
3. **Folio 的天然优势**：每篇文章已有 DeepSeek 生成的 summary + key_points，这本质上是预计算好的 contextual chunk，不需要再做分块或 embedding。
4. **规模匹配**：个人知识库 100-5000 篇，不需要企业级向量检索。

### 核心设计原则

**关键词负责召回，LLM 负责理解**。

- LLM 参与整个检索链路：查询扩展（补语义鸿沟）→ 生成语义指纹（入库时）→ 精排判断（搜索时）。
- 关键词基础设施（pg_trgm）只负责快速过滤，不承担语义理解。
- 每个 LLM 调用失败都有关键词降级路径。

## 2. 架构总览

```
┌──────────────────────────────────────────────────────┐
│  入库时                                               │
│                                                      │
│  DeepSeek Analyze（已有）                              │
│    → 原有输出: category, tags, summary, key_points    │
│    → 新增输出: semantic_keywords (10-15 个)            │
│                       ↓                              │
│          async article:relate worker                 │
│    semantic_keywords 跨库召回 Top 30（BroadRecallSummaries）         │
│    → DeepSeek 挑 Top 5 → 缓存到 article_relations    │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  查询时                                               │
│                                                      │
│  [RAG 问答]                                           │
│    < 500 篇: 全量摘要塞 prompt（现有逻辑，不变）         │
│    ≥ 500 篇: ExpandQuery → BroadRecall 50             │
│              → 直接喂现有 RAG prompt → 生成回答         │
│    LLM 调用: 2 次（扩展 + 回答）                       │
│                                                      │
│  [语义搜索]                                           │
│    ExpandQuery → BroadRecall 50 → RerankArticles      │
│    → 返回排序后的文章列表                               │
│    LLM 调用: 2 次（扩展 + 精排）                       │
│                                                      │
│  [相关文章]                                           │
│    GET /articles/{id}/related → 读 article_relations  │
│    LLM 调用: 0 次（已预计算）                          │
└──────────────────────────────────────────────────────┘
```

## 3. 宽召回层 — BroadRecall

### 目标

高召回率（宁可多捞不要漏掉），精度交给 LLM。

### 输入

一组扩展后的关键词（10-15 个 `text[]`）。

### 输出

Top 50 候选文章（id, title, summary, key_points, site_name, created_at）。

### SQL 策略

三路召回取 union：semantic_keywords 精确匹配（最高优先级）、title 三元组模糊匹配、summary/key_points 子串匹配。

> **设计决策**：pg_trgm `similarity()` / `%` 操作符适合短字符串（如标题）的模糊匹配，但对长文本（如 summary）效果很差——长文本的三元组集合庞大，短关键词的相似度分数被稀释到接近 0。因此 summary 使用 ILIKE 子串匹配而非三元组；`semantic_keywords` 使用数组精确匹配（GIN 索引）。

> **大小写策略**：`semantic_keywords` 存储为小写（`lower()`），`ExpandQuery` 返回小写关键词。中文无大小写问题，英文通过小写归一化解决。

```sql
SELECT set_config('pg_trgm.similarity_threshold', '0.1', true);

WITH keyword_matches AS (
    SELECT DISTINCT ON (a.id)
        a.id, a.title, a.summary, a.key_points, a.site_name, a.created_at,
        CASE
            -- 最高优先级: semantic_keywords 精确命中
            WHEN a.semantic_keywords && $2::text[] THEN 1.0
            -- 次优先级: 标题三元组匹配（短字符串，pg_trgm 最佳场景）
            WHEN a.title % kw.word THEN similarity(a.title, kw.word) + 0.5
            -- 兜底: summary/key_points 子串命中
            ELSE 0.1
        END AS score
    FROM articles a
    CROSS JOIN unnest($2::text[]) AS kw(word)
    WHERE a.user_id = $1
      AND a.status = 'ready'
      AND a.deleted_at IS NULL
      AND (
          a.semantic_keywords && $2::text[]              -- 数组重叠（GIN 索引）
          OR a.title % kw.word                           -- 标题三元组（GIN 索引）
          OR a.summary ILIKE '%' || kw.word || '%'       -- 摘要子串
          OR a.key_points::text ILIKE '%' || kw.word || '%'  -- 关键点子串
      )
    ORDER BY a.id, score DESC
)
SELECT id, title, summary, key_points, site_name, created_at
FROM keyword_matches
ORDER BY score DESC
LIMIT $3
```

### 设计要点

- **三路召回，各取所长**：
  - `semantic_keywords && $2::text[]`：数组重叠操作符，走 GIN 索引，O(1) 查找。最精准的语义匹配。
  - `title % kw.word`：pg_trgm 操作符，走 GIN trigram 索引。标题短、三元组匹配效果好。
  - `summary ILIKE` / `key_points::text ILIKE`：子串匹配。summary 有 GIN trigram 索引（migration 012 新增），PostgreSQL GIN `gin_trgm_ops` 支持 `ILIKE` infix 查询加速。key_points 为 JSONB 转 text，走顺序扫描但 5000 行下足够快。
- **评分层级**：semantic_keywords 命中 = 1.0（最高），title 三元组 = 0.5+similarity，ILIKE = 0.1。确保语义匹配的文章排在最前。
- `DISTINCT ON (id)` 确保同篇文章只出现一次，取最高分。
- 返回 `key_points` 给下游 LLM 更多上下文。
- **预期性能**：semantic_keywords GIN + title GIN 两路索引扫描 + 5000 行 ILIKE 顺序扫描，合计 < 100ms。

### ILIKE 通配符转义

LLM 生成的关键词可能包含 `%` 或 `_`（ILIKE 通配符）。Go 代码在构建查询前必须转义：

```go
func escapeILIKE(s string) string {
    s = strings.ReplaceAll(s, `\`, `\\`)
    s = strings.ReplaceAll(s, `%`, `\%`)
    s = strings.ReplaceAll(s, `_`, `\_`)
    return s
}
// 对 $2::text[] 中的每个关键词调用 escapeILIKE
// semantic_keywords && 和 title % 不受影响（不使用 ILIKE 语法）
```

### BroadRecall 自排除

relate worker 需要从结果中排除当前文章。BroadRecall 新增可选参数 `excludeID`：

```sql
AND ($4::uuid IS NULL OR a.id != $4)  -- $4 = 排除的文章 ID，搜索时传 NULL
```

### 索引依赖

- `idx_articles_title_trgm`（已存在，migration 001）
- `idx_articles_summary_trgm`（新增，migration 012）

## 4. LLM 查询扩展 — ExpandQuery

### 触发条件

- RAG 问答：仅 ≥ 500 篇文章时调用
- 语义搜索：始终调用

### Analyzer 接口新增

```go
ExpandQuery(ctx context.Context, question string) ([]string, error)
```

### Prompt

```
给定用户问题，生成 10-15 个搜索关键词，用于在文章库中检索相关内容。

要求：
1. 包含原始问题中的核心词
2. 包含同义词和近义表达
3. 包含中英文双语翻译（如问题是中文，补英文关键词；反之亦然）
4. 包含上下位概念（如"React"→ 补"前端框架"）
5. 所有关键词输出为小写（英文小写，中文无影响）
6. 不要解释，直接输出 JSON 数组

用户问题：{question}

输出格式：["关键词1", "keyword2", ...]
```

### 模型参数

- model: `deepseek-chat`
- temperature: 0
- max_tokens: 200
- response_format: JSON

### 性能

- 预期延迟：~300ms
- 预期成本：~$0.0001/次

### 降级

失败时回退到原始问题作为单一关键词做 pg_trgm 搜索（现有 `SearchArticleSummaries` 逻辑）。

## 5. LLM 精排 — RerankArticles

### 用途

仅用于**语义搜索**（返回排序后的文章列表）。RAG 不使用此方法——RAG prompt 自身已隐式完成精排。

### Analyzer 接口新增

```go
RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error)

type RerankCandidate struct {
    Index     int
    Title     string
    Summary   string
    KeyPoints []string
}

type RerankResult struct {
    Index     int    // 对应候选列表的序号
    Relevance string // "high" | "medium"
}
```

### Prompt

```
用户问题：{question}

以下是候选文章列表。判断每篇与用户问题的相关程度，返回最相关的 Top 10。

候选文章：
[1] 《标题》: 摘要内容 | 关键点: ...
[2] 《标题》: 摘要内容 | 关键点: ...
...

输出 JSON（不要 markdown 代码块）：
[{"index": 1, "relevance": "high"}, {"index": 5, "relevance": "medium"}, ...]

规则：
1. 只返回与问题相关的文章（最多 10 篇）
2. relevance: "high" = 直接相关, "medium" = 间接相关
3. 按相关程度从高到低排列
4. 不相关的不要返回
```

### 模型参数

- model: `deepseek-chat`
- temperature: 0
- max_tokens: 512
- response_format: JSON

### 性能

- 输入 token：50 篇 × ~80 字 ≈ 3K tokens
- 预期延迟：~1s
- 预期成本：~$0.001/次

### 降级

失败时返回 BroadRecall 的原始排序（按 pg_trgm score 降序）。

## 6. AI 分析扩展 — semantic_keywords

### 修改现有 Analyze

在 AI 分析 prompt 的输出规则中新增：

```
8. semantic_keywords: 生成 10-15 个语义关键词（全部小写），用于后续检索匹配。
   要求：包含核心概念的中英文双语表达、同义词、上下位概念。
   可以与 tags 有部分重叠。目的是让未来的关键词搜索能找到这篇文章。
```

### 数据变更

- `AnalyzeResponse` struct 新增 `SemanticKeywords []string`
- `AIResult` struct 新增 `SemanticKeywords []string`
- `UpdateAIResult` SQL 更新 `semantic_keywords` 列
- Mock 分析器返回基于 URL 模式的确定性 semantic_keywords

### 存储

articles 表新增 `semantic_keywords TEXT[]` 列 + GIN 索引。

### 零额外成本

搭载现有 Analyze 调用，不增加 LLM 调用次数。prompt 增加约 20 tokens 输出。

## 7. 相关文章 Worker — article:relate

### 触发

`article:ai` handler 完成后入队（与 `echo:generate` 并行）。

> **时序约束**：`UpdateAIResult` 必须先将 `semantic_keywords` 持久化到 DB，然后才能入队 `article:relate`。当前代码中 `UpdateAIResult` 在 line 131-144 执行，echo 入队在 line 214-223，所以 relate 入队放在同一位置即可满足约束。

### Analyzer 接口新增

relate worker 使用独立方法（不复用 `RerankArticles`，因为 prompt 结构不同）：

```go
SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error)

type RelatedResult struct {
    Index  int    // 对应候选列表的序号
    Reason string // 关联理由
}
```

### 逻辑

1. 读取本文的 `semantic_keywords`
2. 调用 `BroadRecallSummaries`（复用宽召回层），传 `excludeID=本文 ID`，Top 30
3. 将 30 篇候选摘要 + 本文摘要送 DeepSeek（`SelectRelatedArticles`）
4. 先 `DELETE FROM article_relations WHERE source_article_id = X`（幂等：重试安全）
5. 批量 `INSERT` 结果到 `article_relations`，`score` = 按返回顺序递减（第 1 篇=5，第 2 篇=4...）

### 队列配置

- Queue: Low
- MaxRetry: 2
- Timeout: 60s

### Prompt

```
本文：《{title}》
摘要：{summary}

候选文章：
[1] 《标题》: 摘要
[2] 《标题》: 摘要
...

从候选中选出与本文最相关的 5 篇（不超过 5 篇），输出 JSON：
[{"index": 1, "reason": "一句话说明关联"}, ...]

规则：
1. 关联可以是主题相关、观点互补、同一领域不同角度等
2. 优先选择跨领域的有趣关联，而非简单的主题重复
3. 没有相关的就少选，不要凑数
```

### 更新策略

- **新文章入库**：为新文章计算关联
- **反向更新**：不在入库时做。可选：每日 cron 低优先级刷新（v1 不做，后续看需求）
- **文章删除**：CASCADE 自动清理

### API

```
GET /api/v1/articles/{id}/related
→ 200: { "articles": [{ "id", "title", "summary", "site_name", "cover_image_url", "relevance_reason" }] }
→ 200: { "articles": [] }  // 无关联时返回空数组
```

## 8. RAG Service 升级

### 改动范围

仅修改 `applyTokenBudget` 方法。

### 新逻辑

```go
func (s *RAGService) applyTokenBudget(ctx context.Context, userID, question string, articles []domain.RAGSource) []domain.RAGSource {
    if len(articles) > ragArticleFallbackCap {
        // 新: LLM 查询扩展 → 多关键词宽召回
        keywords, err := s.aiClient.ExpandQuery(ctx, question)
        if err != nil {
            slog.Warn("query expansion failed, falling back to pg_trgm", "error", err)
            searched, _ := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
            if searched != nil {
                return searched
            }
            return articles[:ragSearchFallbackSize]
        }
        recalled, err := s.ragRepo.BroadRecallSummaries(ctx, userID, keywords, ragSearchFallbackSize)
        if err != nil || len(recalled) == 0 {
            slog.Warn("broad recall failed, falling back to pg_trgm", "error", err)
            searched, _ := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
            if searched != nil {
                return searched
            }
            return articles[:ragSearchFallbackSize]
        }
        return recalled
    }

    // < 500 篇: 原有 token budget 逻辑完全不变
    var selected []domain.RAGSource
    var estimatedTokens int
    for _, a := range articles {
        // ... 现有逻辑 ...
    }
    return selected
}
```

### 不变的部分

- RAG system prompt / user prompt 模板
- 对话存储逻辑
- Quota 检查逻辑
- < 500 篇的全量摘要逻辑

## 9. 语义搜索 API

### 端点

升级现有 `GET /api/v1/articles/search`，新增 `mode` 查询参数。

| 参数 | 值 | 行为 |
|------|-----|------|
| `mode` 缺省或 `keyword` | 现有 ILIKE 搜索（不变） |
| `mode=semantic` | 查询扩展 → 宽召回 → LLM rerank |

### Handler

```go
// 注意：现有方法名是 HandleSearch，非 Search
func (h *SearchHandler) HandleSearch(w http.ResponseWriter, r *http.Request) {
    mode := r.URL.Query().Get("mode")
    switch mode {
    case "semantic":
        // Pro-only check
        // s.articleService.SemanticSearch(...)
    default:
        // 现有关键词搜索逻辑
    }
}
```

### Service

> **依赖注入变更**：`ArticleService` 当前不持有 `aiClient`。需要在 `NewArticleService` 构造函数中新增 `aiClient client.Analyzer` 参数，并在 `cmd/server/main.go` 的服务初始化处传入。

```go
func (s *ArticleService) SemanticSearch(ctx context.Context, userID, question string, page, perPage int) (*ListArticlesResult, error) {
    // 1. ExpandQuery
    keywords, err := s.aiClient.ExpandQuery(ctx, question)
    if err != nil {
        return s.Search(ctx, userID, question, page, perPage) // 降级
    }
    // 2. BroadRecall
    candidates, err := s.articleRepo.BroadRecallFull(ctx, userID, keywords, 50)
    if err != nil || len(candidates) == 0 {
        return s.Search(ctx, userID, question, page, perPage) // 降级
    }
    // 3. RerankArticles
    ranked, err := s.aiClient.RerankArticles(ctx, question, toRerankCandidates(candidates))
    if err != nil {
        return &ListArticlesResult{Articles: candidates, Total: len(candidates)}, nil // 降级到召回排序
    }
    // 4. Map ranked indices back to articles, paginate
    return mapAndPaginate(ranked, candidates, page, perPage), nil
}
```

### 权限

- `mode=semantic`：Pro 用户专属。Free 用户调用返回 403 + 升级提示。
- `mode=keyword`：所有用户。

### iOS 对接（本轮不实现，仅预留）

- 本地 FTS5 关键词搜索保持即时响应
- 语义搜索作为异步补充，结果到达后追加展示在"AI 推荐"分区下
- debounce 500ms 后调用 semantic search API

## 10. 数据库 Migration

```sql
-- 012_smart_retrieval.up.sql

-- 1. 语义关键词列
ALTER TABLE articles ADD COLUMN semantic_keywords TEXT[] DEFAULT '{}';
CREATE INDEX idx_articles_semantic_keywords ON articles USING GIN (semantic_keywords);

-- 2. 摘要 trigram 索引（宽召回需要）
CREATE INDEX idx_articles_summary_trgm ON articles USING GIN (summary gin_trgm_ops);

-- 3. 相关文章缓存表
CREATE TABLE article_relations (
    source_article_id  UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    related_article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    relevance_reason   TEXT,
    score              SMALLINT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_article_id, related_article_id)
);
CREATE INDEX idx_article_relations_source ON article_relations (source_article_id, score);

-- 4. 清理废弃的占位表（migration 008 创建，从未使用）
DROP TABLE IF EXISTS article_embeddings;
```

```sql
-- 012_smart_retrieval.down.sql

DROP TABLE IF EXISTS article_relations;
DROP INDEX IF EXISTS idx_articles_summary_trgm;
DROP INDEX IF EXISTS idx_articles_semantic_keywords;
ALTER TABLE articles DROP COLUMN IF EXISTS semantic_keywords;

-- 恢复 article_embeddings 不做（原本就是空占位表）
```

## 11. 完整改动清单

| 层 | 文件 | 改动类型 | 说明 |
|---|------|---------|------|
| Domain | `domain/article.go` | 修改 | `Article` struct 加 `SemanticKeywords []string` |
| Domain | `domain/rag.go` | 修改 | `RAGSource` 加 `KeyPoints []string`（BroadRecall 输出用，RAG prompt 可选使用） |
| Client | `client/ai.go` | 修改 | `AnalyzeResponse` 加 `SemanticKeywords`；`Analyzer` 接口新增 `ExpandQuery`、`RerankArticles`、`SelectRelatedArticles` |
| Client | `client/ai_mock.go` | 修改 | 四个新方法/字段的 mock 实现（SemanticKeywords + ExpandQuery + RerankArticles + SelectRelatedArticles） |
| Repository | `repository/article.go` | 修改 | `UpdateAIResult` 写入 semantic_keywords；新增 `BroadRecallArticles`（返回 Article，语义搜索用） |
| Repository | `repository/rag.go` | 修改 | 新增 `BroadRecallSummaries`（返回 RAGSource，RAG + relate worker 用）|
| Repository | 新文件 `repository/relation.go` | 新增 | article_relations CRUD（Save batch、ListBySource、DeleteBySource） |
| Service | `service/rag.go` | 修改 | `applyTokenBudget` 替换 ≥500 篇逻辑 |
| Service | `service/article.go` | 修改 | `NewArticleService` 加 `aiClient` 依赖；新增 `SemanticSearch` 方法 |
| Handler | `handler/search.go` | 修改 | `HandleSearch` 读取 `mode` 参数，分流 |
| Handler | 新文件 `handler/relation.go` | 新增 | `GET /articles/{id}/related` |
| Router | `api/router.go` | 修改 | 注册 related 端点 |
| Worker | `worker/ai_handler.go` | 修改 | AI 完成后入队 `article:relate`（在 `UpdateAIResult` 之后） |
| Worker | 新文件 `worker/relate_handler.go` | 新增 | 相关文章计算逻辑 |
| Worker | `worker/tasks.go` | 修改 | 新增 `RelatePayload`、`NewRelateTask` |
| Worker | `worker/server.go`（或 worker mux 注册处） | 修改 | 注册 `article:relate` handler 到 asynq mux |
| Entrypoint | `cmd/server/main.go` | 修改 | `ArticleService` 构造传入 `aiClient`；relate handler 初始化 |
| Migration | `migrations/012_smart_retrieval` | 新增 | up + down |

## 12. 不改的部分

- **iOS 端**：FTS5、搜索 UI、Reader（语义搜索 iOS 对接放下一轮）
- **RAG prompt 模板**：`buildRAGSystemPrompt`、`buildRAGUserPrompt` 不变
- **RAG 对话存储 / quota**：不变
- **现有关键词搜索**：`mode` 缺省时行为完全不变
- **Docker 镜像**：不需要新服务或新镜像
- **配置**：复用现有 DeepSeek 配置，无新环境变量

## 13. 成本估算

| 操作 | LLM 调用 | 成本/次 | 频率 |
|------|---------|--------|------|
| 文章入库 AI 分析 | 0 次额外（搭车） | +$0（prompt 多 ~20 tokens 输出） | 每篇文章 |
| 相关文章计算 | 1 次 | ~$0.001 | 每篇文章入库时 |
| RAG 问答（<500 篇） | 0 次额外 | 不变 | 每次查询 |
| RAG 问答（≥500 篇） | 1 次额外（扩展） | ~$0.0001 | 每次查询 |
| 语义搜索 | 2 次（扩展 + 精排） | ~$0.0012 | 每次搜索 |

## 14. 延迟预算

| 操作 | 步骤 | 延迟 |
|------|------|------|
| RAG（<500 篇） | 全量摘要 → 生成回答 | ~2s（不变） |
| RAG（≥500 篇） | 扩展 300ms → SQL 100ms → 生成回答 2s | ~2.5s |
| 语义搜索 | 扩展 300ms → SQL 100ms → 精排 1s | ~1.5s |
| 相关文章查询 | 读缓存表 | < 10ms |

## 15. 存量数据回填

Migration 后所有已有文章的 `semantic_keywords` 为空数组 `{}`。BroadRecall 的语义召回路径对这些文章无效，退化为 title trigram + ILIKE（与当前 pg_trgm 搜索效果相当）。

### 回填策略

新增一次性 worker 任务 `article:backfill-keywords`：

1. 查询所有 `status = 'ready' AND semantic_keywords = '{}'` 的文章
2. 对每篇文章，用现有 `summary + key_points` 构造一个轻量 prompt：
   ```
   基于以下文章摘要和关键点，生成 10-15 个语义检索关键词（全部小写）。
   标题：{title}
   摘要：{summary}
   关键点：{key_points}
   输出 JSON 数组：["keyword1", "关键词2", ...]
   ```
3. 写入 `semantic_keywords` 列
4. 入队 `article:relate`（为老文章也生成关联）

### 执行方式

- 手动触发（CLI 命令或一次性 API 端点），不自动运行
- Low 队列，逐篇处理，rate limit 避免打满 DeepSeek API
- 预估：1000 篇 × ~$0.0001/篇 = ~$0.10，可忽略

### 优先级

非上线阻塞。可在功能上线后按需执行。上线时新文章自动生成 semantic_keywords，老文章走 title trigram + ILIKE 降级路径。

## 16. 测试策略

### 单元测试

| 测试目标 | 文件 | 覆盖内容 |
|---------|------|---------|
| BroadRecall SQL | `repository/article_test.go` | 三路召回各自命中、评分层级、DISTINCT 去重、自排除、ILIKE 通配符转义 |
| ExpandQuery | `client/ai_test.go` | JSON 解析、小写归一化、降级到原始问题 |
| RerankArticles | `client/ai_test.go` | JSON 解析、index 越界保护、空结果处理 |
| SelectRelatedArticles | `client/ai_test.go` | JSON 解析、score 赋值、reason 提取 |
| article:relate 幂等性 | `worker/relate_handler_test.go` | 重复执行不报错（DELETE + INSERT） |
| SemanticSearch 降级链 | `service/article_test.go` | ExpandQuery 失败 → keyword 降级；Rerank 失败 → 召回排序降级 |

### E2E 测试

新增 `server/tests/e2e/test_smart_retrieval.py`：

1. **语义搜索**：创建 3 篇不同主题文章 → 等待 AI 分析完成 → `GET /articles/search?q=...&mode=semantic` → 验证返回相关文章
2. **相关文章**：创建 2 篇相关主题文章 → 等待 relate worker 完成 → `GET /articles/{id}/related` → 验证返回关联
3. **RAG 升级**：（需要 >500 篇文章，E2E 中可调低 `ragArticleFallbackCap` 常量来模拟）
4. **降级路径**：mock DeepSeek 返回错误 → 验证降级到关键词搜索

### Mock 分析器覆盖

`ai_mock.go` 的新方法需要返回确定性结果：
- `ExpandQuery`：基于问题关键词返回固定扩展列表
- `RerankArticles`：按 index 顺序返回前 N 个（简单直通）
- `SelectRelatedArticles`：返回前 3 个候选作为关联
