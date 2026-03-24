# Smart Retrieval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build LLM-powered retrieval infrastructure (query expansion + keyword recall + LLM judgment) to unlock semantic search, RAG upgrade, and related articles — with zero new infrastructure (no pgvector, no embedding model).

**Architecture:** Three-stage pipeline: (1) LLM query expansion generates 10-15 bilingual keywords, (2) pg_trgm + semantic_keywords array broad recall fetches Top 50 candidates, (3) LLM judges relevance for final ranking. RAG reuses stages 1-2 then feeds directly to existing RAG prompt. Related articles precompute at ingestion via semantic_keywords generated during AI analysis.

**Tech Stack:** Go 1.24, PostgreSQL 16 (pg_trgm), DeepSeek Chat API, asynq worker queue

**Spec:** `docs/superpowers/specs/2026-03-24-smart-retrieval-design.md`

---

## Task 1: Database Migration + Domain Model Updates

**Files:**
- Create: `server/migrations/012_smart_retrieval.up.sql`
- Create: `server/migrations/012_smart_retrieval.down.sql`
- Modify: `server/internal/domain/article.go:29-63`
- Modify: `server/internal/domain/rag.go:5-12`

- [ ] **Step 1: Create migration up file**

Create `server/migrations/012_smart_retrieval.up.sql`:
```sql
-- 1. Semantic keywords column
ALTER TABLE articles ADD COLUMN semantic_keywords TEXT[] DEFAULT '{}';
CREATE INDEX idx_articles_semantic_keywords ON articles USING GIN (semantic_keywords);

-- 2. Summary trigram index (broad recall needs it)
CREATE INDEX idx_articles_summary_trgm ON articles USING GIN (summary gin_trgm_ops);

-- 3. Related articles cache table
CREATE TABLE article_relations (
    source_article_id  UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    related_article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    relevance_reason   TEXT,
    score              SMALLINT NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source_article_id, related_article_id)
);
CREATE INDEX idx_article_relations_source ON article_relations (source_article_id, score);

-- 4. Drop unused placeholder table from migration 008
DROP TABLE IF EXISTS article_embeddings;
```

- [ ] **Step 2: Create migration down file**

Create `server/migrations/012_smart_retrieval.down.sql`:
```sql
DROP TABLE IF EXISTS article_relations;
DROP INDEX IF EXISTS idx_articles_summary_trgm;
ALTER TABLE articles DROP COLUMN IF EXISTS semantic_keywords;
```

- [ ] **Step 3: Apply migration to dev database**

```bash
cd server && docker compose -f docker-compose.local.yml exec -T postgres psql -U folio -d folio < migrations/012_smart_retrieval.up.sql
```

- [ ] **Step 4: Add SemanticKeywords to Article domain struct**

In `server/internal/domain/article.go`, add to the `Article` struct (after `Language` field around line 50):
```go
SemanticKeywords []string   `json:"semantic_keywords,omitempty"`
```

- [ ] **Step 5: Add KeyPoints to RAGSource struct**

In `server/internal/domain/rag.go`, modify `RAGSource` struct (lines 5-12) — add `KeyPoints` after `Summary`:
```go
type RAGSource struct {
	ArticleID string
	Title     string
	SiteName  *string
	Summary   *string
	KeyPoints []string  // NEW: for BroadRecall output, gives LLM more context
	CreatedAt time.Time
	Relevance float64
}
```

- [ ] **Step 6: Build to verify compilation**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 7: Commit**

```bash
cd server && git add migrations/012_smart_retrieval.up.sql migrations/012_smart_retrieval.down.sql internal/domain/article.go internal/domain/rag.go
git commit -m "feat: add smart retrieval migration and domain model updates

- Add semantic_keywords TEXT[] column with GIN index
- Add summary trigram index for broad recall
- Add article_relations cache table
- Drop unused article_embeddings placeholder
- Add SemanticKeywords to Article, KeyPoints to RAGSource"
```

---

## Task 2: AI Client — Analyzer Interface + New Methods

**Files:**
- Modify: `server/internal/client/ai.go:22-45` (interface + response struct)
- Modify: `server/internal/client/ai.go:189-217` (Analyze prompt)
- Modify: `server/internal/client/ai_mock.go`

This task adds `SemanticKeywords` to the Analyze output, and adds three new Analyzer methods: `ExpandQuery`, `RerankArticles`, `SelectRelatedArticles`.

- [ ] **Step 1: Extend AnalyzeResponse and Analyzer interface**

In `server/internal/client/ai.go`:

Add `SemanticKeywords` to `AnalyzeResponse` (line 44, before closing brace):
```go
type AnalyzeResponse struct {
	Category         string   `json:"category"`
	CategoryName     string   `json:"category_name"`
	Confidence       float64  `json:"confidence"`
	Tags             []string `json:"tags"`
	Summary          string   `json:"summary"`
	KeyPoints        []string `json:"key_points"`
	Language         string   `json:"language"`
	SemanticKeywords []string `json:"semantic_keywords"` // NEW
}
```

Add new methods to `Analyzer` interface (lines 22-26):
```go
type Analyzer interface {
	Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error)
	GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error)
	GenerateRAGAnswer(ctx context.Context, systemPrompt, userPrompt string) (*RAGResult, error)
	ExpandQuery(ctx context.Context, question string) ([]string, error)                                                          // NEW
	RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error)                    // NEW
	SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error) // NEW
}
```

Add the new types after `AnalyzeResponse`:
```go
// RerankCandidate represents an article candidate for LLM reranking.
type RerankCandidate struct {
	Index     int
	Title     string
	Summary   string
	KeyPoints []string
}

// RerankResult represents a reranked article with relevance level.
type RerankResult struct {
	Index     int    `json:"index"`
	Relevance string `json:"relevance"` // "high" | "medium"
}

// RelatedResult represents a related article selected by LLM.
type RelatedResult struct {
	Index  int    `json:"index"`
	Reason string `json:"reason"`
}
```

- [ ] **Step 2: Add semantic_keywords to Analyze prompt**

In `server/internal/client/ai.go`, modify `buildSystemPrompt()` (around line 199-217). Add rule 7 before the JSON output format, and add `semantic_keywords` to the output JSON:

Add after rule 6 (key_points):
```
7. **semantic_keywords**：生成 10-15 个语义关键词（全部小写），用于后续检索匹配。包含核心概念的中英文双语表达、同义词、上下位概念。可以与 tags 有部分重叠。
```

Update the output JSON template to include:
```
  "semantic_keywords": ["keyword1", "关键词2", ...]
```

- [ ] **Step 3: Implement ExpandQuery on DeepSeekAnalyzer**

Add to `server/internal/client/ai.go`:

```go
func (d *DeepSeekAnalyzer) ExpandQuery(ctx context.Context, question string) ([]string, error) {
	prompt := fmt.Sprintf(`给定用户问题，生成 10-15 个搜索关键词，用于在文章库中检索相关内容。

要求：
1. 包含原始问题中的核心词
2. 包含同义词和近义表达
3. 包含中英文双语翻译（如问题是中文，补英文关键词；反之亦然）
4. 包含上下位概念（如"React"→ 补"前端框架"）
5. 所有关键词输出为小写（英文小写，中文无影响）
6. 不要解释，直接输出 JSON 数组

用户问题：%s

输出格式：["关键词1", "keyword2", ...]`, question)

	body := chatRequest{
		Model:       "deepseek-chat",
		Temperature: 0,
		MaxTokens:   200,
		Messages: []message{
			{Role: "user", Content: prompt},
		},
		ResponseFormat: &responseFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, body)
	if err != nil {
		return nil, fmt.Errorf("expand query: %w", err)
	}

	content := respBody.Choices[0].Message.Content
	var keywords []string
	if err := json.Unmarshal([]byte(content), &keywords); err != nil {
		// Try wrapping in case the model returns {"keywords": [...]}
		var wrapper map[string][]string
		if err2 := json.Unmarshal([]byte(content), &wrapper); err2 == nil {
			for _, v := range wrapper {
				keywords = v
				break
			}
		} else {
			return nil, fmt.Errorf("parse expand query response: %w", err)
		}
	}

	// Normalize to lowercase
	for i, kw := range keywords {
		keywords[i] = strings.ToLower(kw)
	}

	return keywords, nil
}
```

- [ ] **Step 4: Implement RerankArticles on DeepSeekAnalyzer**

Add to `server/internal/client/ai.go`:

```go
func (d *DeepSeekAnalyzer) RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "用户问题：%s\n\n以下是候选文章列表。判断每篇与用户问题的相关程度，返回最相关的 Top 10。\n\n候选文章：\n", question)
	for _, c := range candidates {
		kp := strings.Join(c.KeyPoints, "; ")
		fmt.Fprintf(&b, "[%d] 《%s》: %s | 关键点: %s\n", c.Index, c.Title, c.Summary, kp)
	}
	b.WriteString(`
输出 JSON（不要 markdown 代码块）：
[{"index": 1, "relevance": "high"}, {"index": 5, "relevance": "medium"}, ...]

规则：
1. 只返回与问题相关的文章（最多 10 篇）
2. relevance: "high" = 直接相关, "medium" = 间接相关
3. 按相关程度从高到低排列
4. 不相关的不要返回`)

	body := chatRequest{
		Model:       "deepseek-chat",
		Temperature: 0,
		MaxTokens:   512,
		Messages: []message{
			{Role: "user", Content: b.String()},
		},
		ResponseFormat: &responseFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, body)
	if err != nil {
		return nil, fmt.Errorf("rerank articles: %w", err)
	}

	content := respBody.Choices[0].Message.Content
	var results []RerankResult
	if err := json.Unmarshal([]byte(content), &results); err != nil {
		// Try unwrapping {"results": [...]}
		var wrapper map[string][]RerankResult
		if err2 := json.Unmarshal([]byte(content), &wrapper); err2 == nil {
			for _, v := range wrapper {
				results = v
				break
			}
		} else {
			return nil, fmt.Errorf("parse rerank response: %w", err)
		}
	}

	// Filter out invalid indices
	maxIdx := len(candidates)
	filtered := results[:0]
	for _, r := range results {
		if r.Index >= 1 && r.Index <= maxIdx {
			filtered = append(filtered, r)
		}
	}

	return filtered, nil
}
```

- [ ] **Step 5: Implement SelectRelatedArticles on DeepSeekAnalyzer**

Add to `server/internal/client/ai.go`:

```go
func (d *DeepSeekAnalyzer) SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "本文：《%s》\n摘要：%s\n\n候选文章：\n", sourceTitle, sourceSummary)
	for _, c := range candidates {
		fmt.Fprintf(&b, "[%d] 《%s》: %s\n", c.Index, c.Title, c.Summary)
	}
	b.WriteString(`
从候选中选出与本文最相关的 5 篇（不超过 5 篇），输出 JSON：
[{"index": 1, "reason": "一句话说明关联"}, ...]

规则：
1. 关联可以是主题相关、观点互补、同一领域不同角度等
2. 优先选择跨领域的有趣关联，而非简单的主题重复
3. 没有相关的就少选，不要凑数`)

	body := chatRequest{
		Model:       "deepseek-chat",
		Temperature: 0,
		MaxTokens:   512,
		Messages: []message{
			{Role: "user", Content: b.String()},
		},
		ResponseFormat: &responseFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, body)
	if err != nil {
		return nil, fmt.Errorf("select related: %w", err)
	}

	content := respBody.Choices[0].Message.Content
	var results []RelatedResult
	if err := json.Unmarshal([]byte(content), &results); err != nil {
		var wrapper map[string][]RelatedResult
		if err2 := json.Unmarshal([]byte(content), &wrapper); err2 == nil {
			for _, v := range wrapper {
				results = v
				break
			}
		} else {
			return nil, fmt.Errorf("parse related response: %w", err)
		}
	}

	maxIdx := len(candidates)
	filtered := results[:0]
	for _, r := range results {
		if r.Index >= 1 && r.Index <= maxIdx {
			filtered = append(filtered, r)
		}
	}

	return filtered, nil
}
```

- [ ] **Step 6: Update MockAnalyzer**

In `server/internal/client/ai_mock.go`:

1. Add `SemanticKeywords` to mock `Analyze` return (around line 113, in the return `&AnalyzeResponse{}`):
```go
SemanticKeywords: []string{strings.ToLower(req.Title), "mock", "keyword"},
```

2. Add three new mock methods:
```go
func (m *MockAnalyzer) ExpandQuery(_ context.Context, question string) ([]string, error) {
	words := strings.Fields(question)
	keywords := make([]string, 0, len(words)+2)
	for _, w := range words {
		keywords = append(keywords, strings.ToLower(w))
	}
	keywords = append(keywords, "mock-expanded-1", "mock-expanded-2")
	return keywords, nil
}

func (m *MockAnalyzer) RerankArticles(_ context.Context, _ string, candidates []RerankCandidate) ([]RerankResult, error) {
	results := make([]RerankResult, 0, min(len(candidates), 5))
	for i := range min(len(candidates), 5) {
		results = append(results, RerankResult{Index: candidates[i].Index, Relevance: "high"})
	}
	return results, nil
}

func (m *MockAnalyzer) SelectRelatedArticles(_ context.Context, _, _ string, candidates []RerankCandidate) ([]RelatedResult, error) {
	results := make([]RelatedResult, 0, min(len(candidates), 3))
	for i := range min(len(candidates), 3) {
		results = append(results, RelatedResult{Index: candidates[i].Index, Reason: "mock related"})
	}
	return results, nil
}
```

- [ ] **Step 7: Build to verify compilation**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 8: Commit**

```bash
cd server && git add internal/client/ai.go internal/client/ai_mock.go
git commit -m "feat: extend Analyzer interface with ExpandQuery, RerankArticles, SelectRelatedArticles

- Add SemanticKeywords to AnalyzeResponse and Analyze prompt
- ExpandQuery: generates 10-15 bilingual keywords for broad recall
- RerankArticles: LLM judges relevance of candidates (semantic search)
- SelectRelatedArticles: LLM picks top 5 related articles (relate worker)
- All methods have robust JSON parsing with wrapper fallback
- MockAnalyzer implements all new methods with deterministic output"
```

---

## Task 3: Repository — BroadRecall + UpdateAIResult + Relations

**Files:**
- Modify: `server/internal/repository/article.go:313-338` (AIResult + UpdateAIResult)
- Modify: `server/internal/repository/rag.go` (add BroadRecallSummaries)
- Create: `server/internal/repository/relation.go`

- [ ] **Step 1: Extend AIResult and UpdateAIResult to include semantic_keywords**

In `server/internal/repository/article.go`, modify `AIResult` struct (lines 313-319):
```go
type AIResult struct {
	CategoryID       string
	Summary          string
	KeyPoints        []string
	Confidence       float64
	Language         string
	SemanticKeywords []string // NEW
}
```

Modify `UpdateAIResult` method (lines 321-338) to write semantic_keywords:
```go
func (r *ArticleRepo) UpdateAIResult(ctx context.Context, id string, ai AIResult) error {
	kp := ai.KeyPoints
	if kp == nil {
		kp = []string{}
	}
	keyPointsJSON, _ := json.Marshal(kp)

	sk := ai.SemanticKeywords
	if sk == nil {
		sk = []string{}
	}

	_, err := r.pool.Exec(ctx, `
		UPDATE articles SET
			category_id = $1,
			summary = $2, key_points = $3, ai_confidence = $4, language = $5,
			semantic_keywords = $6,
			status = 'ready'
		WHERE id = $7`,
		ai.CategoryID, ai.Summary, keyPointsJSON, ai.Confidence, ai.Language,
		sk, id)
	if err != nil {
		return fmt.Errorf("update ai result: %w", err)
	}
	return nil
}
```

- [ ] **Step 2: Add escapeILIKE helper and BroadRecallArticles to ArticleRepo**

Add to `server/internal/repository/article.go`:

```go
// escapeILIKE escapes ILIKE wildcard characters in a keyword.
func escapeILIKE(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `%`, `\%`)
	s = strings.ReplaceAll(s, `_`, `\_`)
	return s
}

// BroadRecallArticles performs three-path broad recall returning full Article objects.
// Used by semantic search. excludeID is optional (pass "" to skip).
func (r *ArticleRepo) BroadRecallArticles(ctx context.Context, userID string, keywords []string, excludeID string, limit int) ([]domain.Article, error) {
	escaped := make([]string, len(keywords))
	for i, kw := range keywords {
		escaped[i] = escapeILIKE(kw)
	}

	var excludeUUID *string
	if excludeID != "" {
		excludeUUID = &excludeID
	}

	rows, err := r.pool.Query(ctx, `
		SELECT set_config('pg_trgm.similarity_threshold', '0.1', true);

		WITH keyword_matches AS (
			SELECT DISTINCT ON (a.id)
				a.id, a.user_id, a.url, a.title, a.summary, a.site_name,
				a.source_type, a.cover_image_url, a.created_at,
				CASE
					WHEN a.semantic_keywords && $2::text[] THEN 1.0
					WHEN a.title % kw.word THEN similarity(a.title, kw.word) + 0.5
					ELSE 0.1
				END AS score
			FROM articles a
			CROSS JOIN unnest($2::text[]) AS kw(word)
			WHERE a.user_id = $1
			  AND a.status = 'ready'
			  AND a.deleted_at IS NULL
			  AND ($4::uuid IS NULL OR a.id != $4)
			  AND (
				  a.semantic_keywords && $2::text[]
				  OR a.title % kw.word
				  OR a.summary ILIKE '%' || kw.word || '%'
				  OR a.key_points::text ILIKE '%' || kw.word || '%'
			  )
			ORDER BY a.id, score DESC
		)
		SELECT id, user_id, url, title, summary, site_name, source_type, cover_image_url, created_at
		FROM keyword_matches
		ORDER BY score DESC
		LIMIT $3`,
		userID, keywords, limit, excludeUUID)
	if err != nil {
		return nil, fmt.Errorf("broad recall articles: %w", err)
	}
	defer rows.Close()

	articles := make([]domain.Article, 0)
	for rows.Next() {
		var a domain.Article
		if err := rows.Scan(&a.ID, &a.UserID, &a.URL, &a.Title, &a.Summary,
			&a.SiteName, &a.SourceType, &a.CoverImageURL, &a.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan broad recall article: %w", err)
		}
		a.KeyPoints = []string{}
		articles = append(articles, a)
	}
	return articles, nil
}
```

**Note:** The `set_config` + multi-statement approach may not work via pgx in a single `Query`. If compilation or runtime fails, split into two calls: first `Exec` the `set_config`, then run the CTE query. Test this in Step 5.

- [ ] **Step 3: Add BroadRecallSummaries to RAGRepo**

Add to `server/internal/repository/rag.go`:

```go
// BroadRecallSummaries performs three-path broad recall returning RAGSource summaries.
// Used by RAG service and relate worker. excludeID is optional (pass "" to skip).
func (r *RAGRepo) BroadRecallSummaries(ctx context.Context, userID string, keywords []string, excludeID string, limit int) ([]domain.RAGSource, error) {
	var excludeUUID *string
	if excludeID != "" {
		excludeUUID = &excludeID
	}

	// Set low trigram threshold for this transaction
	_, _ = r.db.Exec(ctx, "SELECT set_config('pg_trgm.similarity_threshold', '0.1', true)")

	rows, err := r.db.Query(ctx, `
		WITH keyword_matches AS (
			SELECT DISTINCT ON (a.id)
				a.id, a.title, a.summary, a.key_points, a.site_name, a.created_at,
				CASE
					WHEN a.semantic_keywords && $2::text[] THEN 1.0
					WHEN a.title % kw.word THEN similarity(a.title, kw.word) + 0.5
					ELSE 0.1
				END AS score
			FROM articles a
			CROSS JOIN unnest($2::text[]) AS kw(word)
			WHERE a.user_id = $1
			  AND a.status = 'ready'
			  AND a.deleted_at IS NULL
			  AND ($4::uuid IS NULL OR a.id != $4)
			  AND (
				  a.semantic_keywords && $2::text[]
				  OR a.title % kw.word
				  OR a.summary ILIKE '%' || kw.word || '%'
				  OR a.key_points::text ILIKE '%' || kw.word || '%'
			  )
			ORDER BY a.id, score DESC
		)
		SELECT id, title, summary, key_points, site_name, created_at
		FROM keyword_matches
		ORDER BY score DESC
		LIMIT $3`,
		userID, keywords, limit, excludeUUID)
	if err != nil {
		return nil, fmt.Errorf("broad recall summaries: %w", err)
	}
	defer rows.Close()

	sources := make([]domain.RAGSource, 0)
	for rows.Next() {
		var s domain.RAGSource
		var keyPointsJSON []byte
		if err := rows.Scan(&s.ArticleID, &s.Title, &s.Summary, &keyPointsJSON, &s.SiteName, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan broad recall summary: %w", err)
		}
		if len(keyPointsJSON) > 0 {
			json.Unmarshal(keyPointsJSON, &s.KeyPoints)
		}
		if s.KeyPoints == nil {
			s.KeyPoints = []string{}
		}
		sources = append(sources, s)
	}
	return sources, nil
}
```

- [ ] **Step 4: Create relation repository**

Create `server/internal/repository/relation.go`:

```go
package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ArticleRelation struct {
	SourceArticleID  string
	RelatedArticleID string
	RelevanceReason  string
	Score            int
}

type RelatedArticle struct {
	ID              string
	Title           *string
	Summary         *string
	SiteName        *string
	CoverImageURL   *string
	RelevanceReason string
}

type RelationRepo struct {
	db *pgxpool.Pool
}

func NewRelationRepo(db *pgxpool.Pool) *RelationRepo {
	return &RelationRepo{db: db}
}

// ReplaceForSource deletes existing relations and inserts new ones (idempotent).
func (r *RelationRepo) ReplaceForSource(ctx context.Context, sourceID string, relations []ArticleRelation) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, "DELETE FROM article_relations WHERE source_article_id = $1", sourceID)
	if err != nil {
		return fmt.Errorf("delete old relations: %w", err)
	}

	for _, rel := range relations {
		_, err = tx.Exec(ctx,
			`INSERT INTO article_relations (source_article_id, related_article_id, relevance_reason, score)
			 VALUES ($1, $2, $3, $4)`,
			rel.SourceArticleID, rel.RelatedArticleID, rel.RelevanceReason, rel.Score)
		if err != nil {
			return fmt.Errorf("insert relation: %w", err)
		}
	}

	return tx.Commit(ctx)
}

// ListBySource returns related articles for a given source article, ordered by score DESC.
func (r *RelationRepo) ListBySource(ctx context.Context, sourceID string) ([]RelatedArticle, error) {
	rows, err := r.db.Query(ctx, `
		SELECT a.id, a.title, a.summary, a.site_name, a.cover_image_url, ar.relevance_reason
		FROM article_relations ar
		JOIN articles a ON a.id = ar.related_article_id
		WHERE ar.source_article_id = $1
		  AND a.deleted_at IS NULL
		ORDER BY ar.score DESC
		LIMIT 5`,
		sourceID)
	if err != nil {
		return nil, fmt.Errorf("list relations: %w", err)
	}
	defer rows.Close()

	var results []RelatedArticle
	for rows.Next() {
		var r RelatedArticle
		if err := rows.Scan(&r.ID, &r.Title, &r.Summary, &r.SiteName, &r.CoverImageURL, &r.RelevanceReason); err != nil {
			return nil, fmt.Errorf("scan relation: %w", err)
		}
		results = append(results, r)
	}
	return results, nil
}
```

- [ ] **Step 5: Build to verify compilation**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 6: Commit**

```bash
cd server && git add internal/repository/article.go internal/repository/rag.go internal/repository/relation.go
git commit -m "feat: add BroadRecall repository methods and relation CRUD

- Extend AIResult/UpdateAIResult to persist semantic_keywords
- BroadRecallSummaries (RAGRepo): three-path recall returning RAGSource
- BroadRecallArticles (ArticleRepo): three-path recall returning Article
- RelationRepo: ReplaceForSource (idempotent) + ListBySource
- escapeILIKE helper for ILIKE wildcard safety"
```

---

## Task 4: RAG Service Upgrade

**Files:**
- Modify: `server/internal/service/rag.go:155-194` (applyTokenBudget)

- [ ] **Step 1: Modify applyTokenBudget to use ExpandQuery + BroadRecall for large collections**

In `server/internal/service/rag.go`, replace the `applyTokenBudget` method (lines 155-194):

```go
func (s *RAGService) applyTokenBudget(ctx context.Context, userID, question string, articles []domain.RAGSource) []domain.RAGSource {
	if len(articles) > ragArticleFallbackCap {
		// Smart retrieval: LLM query expansion → broad recall
		keywords, err := s.aiClient.ExpandQuery(ctx, question)
		if err != nil {
			slog.Warn("query expansion failed, falling back to pg_trgm", "error", err)
			searched, _ := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
			if searched != nil {
				return searched
			}
			return articles[:ragSearchFallbackSize]
		}
		recalled, err := s.ragRepo.BroadRecallSummaries(ctx, userID, keywords, "", ragSearchFallbackSize)
		if err != nil || len(recalled) == 0 {
			slog.Warn("broad recall failed or empty, falling back to pg_trgm", "error", err)
			searched, _ := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
			if searched != nil {
				return searched
			}
			return articles[:ragSearchFallbackSize]
		}
		return recalled
	}

	// < 500 articles: existing token budget logic unchanged
	var selected []domain.RAGSource
	var estimatedTokens int

	for _, a := range articles {
		summary := derefString(a.Summary)
		summary = truncateRunes(summary, ragMaxSummaryRunes)

		title := a.Title
		tokens := estimateTokens(title) + estimateTokens(summary)

		if estimatedTokens+tokens > ragTokenBudget {
			searched, err := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
			if err != nil {
				slog.Warn("search fallback failed after budget exceeded", "error", err)
				break
			}
			return searched
		}

		estimatedTokens += tokens
		selected = append(selected, a)
	}

	if len(selected) == 0 {
		return articles
	}
	return selected
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd server && go build ./... && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
cd server && git add internal/service/rag.go
git commit -m "feat: upgrade RAG retrieval with LLM query expansion + broad recall

For collections >= 500 articles, uses ExpandQuery + BroadRecallSummaries
instead of simple pg_trgm fallback. Graceful degradation to existing
pg_trgm search if expansion or recall fails."
```

---

## Task 5: Semantic Search — Service + Handler

**Files:**
- Modify: `server/internal/service/article.go:15-40`
- Modify: `server/internal/api/handler/search.go`

- [ ] **Step 1: Add aiClient to ArticleService**

In `server/internal/service/article.go`, add `aiClient` field and update constructor:

```go
type ArticleService struct {
	articleRepo  articleCreator
	taskRepo     taskCreator
	tagRepo      tagAttacher
	categoryRepo categoryGetter
	quotaService quotaChecker
	asynqClient  taskEnqueuer
	aiClient     client.Analyzer // NEW
}

func NewArticleService(
	articleRepo *repository.ArticleRepo,
	taskRepo *repository.TaskRepo,
	tagRepo *repository.TagRepo,
	categoryRepo *repository.CategoryRepo,
	quotaService *QuotaService,
	asynqClient *asynq.Client,
	aiClient client.Analyzer, // NEW
) *ArticleService {
	return &ArticleService{
		articleRepo:  articleRepo,
		taskRepo:     taskRepo,
		tagRepo:      tagRepo,
		categoryRepo: categoryRepo,
		quotaService: quotaService,
		asynqClient:  asynqClient,
		aiClient:     aiClient, // NEW
	}
}
```

Add the import for `"folio-server/internal/client"` if not already present.

- [ ] **Step 2: Add SemanticSearch method to ArticleService**

Add to `server/internal/service/article.go`:

```go
// SemanticSearch performs LLM-powered semantic search: expand query → broad recall → rerank.
func (s *ArticleService) SemanticSearch(ctx context.Context, userID, question string, page, perPage int) (*ListArticlesResult, error) {
	// 1. Expand query
	keywords, err := s.aiClient.ExpandQuery(ctx, question)
	if err != nil {
		slog.Warn("semantic search: expand failed, falling back to keyword", "error", err)
		return s.Search(ctx, userID, question, page, perPage)
	}

	// 2. Broad recall
	candidates, err := s.articleRepo.(interface {
		BroadRecallArticles(ctx context.Context, userID string, keywords []string, excludeID string, limit int) ([]domain.Article, error)
	}).BroadRecallArticles(ctx, userID, keywords, "", 50)
	if err != nil || len(candidates) == 0 {
		slog.Warn("semantic search: broad recall failed, falling back to keyword", "error", err)
		return s.Search(ctx, userID, question, page, perPage)
	}

	// 3. Rerank with LLM
	rerankCandidates := make([]client.RerankCandidate, len(candidates))
	for i, a := range candidates {
		summary := ""
		if a.Summary != nil {
			summary = *a.Summary
		}
		rerankCandidates[i] = client.RerankCandidate{
			Index:     i + 1,
			Title:     derefStr(a.Title),
			Summary:   summary,
			KeyPoints: a.KeyPoints,
		}
	}

	ranked, err := s.aiClient.RerankArticles(ctx, question, rerankCandidates)
	if err != nil {
		slog.Warn("semantic search: rerank failed, returning broad recall order", "error", err)
		// Fallback: return candidates in recall order with pagination
		total := len(candidates)
		start := (page - 1) * perPage
		end := start + perPage
		if start >= total {
			return &ListArticlesResult{Articles: []domain.Article{}, Total: total}, nil
		}
		if end > total {
			end = total
		}
		return &ListArticlesResult{Articles: candidates[start:end], Total: total}, nil
	}

	// 4. Map ranked indices back to articles
	result := make([]domain.Article, 0, len(ranked))
	for _, r := range ranked {
		idx := r.Index - 1
		if idx >= 0 && idx < len(candidates) {
			result = append(result, candidates[idx])
		}
	}

	// 5. Paginate
	total := len(result)
	start := (page - 1) * perPage
	end := start + perPage
	if start >= total {
		return &ListArticlesResult{Articles: []domain.Article{}, Total: total}, nil
	}
	if end > total {
		end = total
	}
	return &ListArticlesResult{Articles: result[start:end], Total: total}, nil
}

func derefStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
```

**Note:** The `articleRepo` is typed as the `articleCreator` interface, which doesn't have `BroadRecallArticles`. The type assertion in the code above is a workaround. A cleaner approach is to add `BroadRecallArticles` to the `articleCreator` interface or create a new interface. During implementation, choose whichever fits the existing pattern better — likely adding it to the interface.

- [ ] **Step 3: Upgrade HandleSearch to support mode=semantic**

Replace `server/internal/api/handler/search.go`:

```go
package handler

import (
	"net/http"
	"strconv"

	"folio-server/internal/api/middleware"
	"folio-server/internal/service"
)

type SearchHandler struct {
	articleService *service.ArticleService
	userRepo       userRepoForQuota // for Pro check
}

func NewSearchHandler(articleService *service.ArticleService, userRepo userRepoForQuota) *SearchHandler {
	return &SearchHandler{articleService: articleService, userRepo: userRepo}
}

func (h *SearchHandler) HandleSearch(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	query := r.URL.Query().Get("q")
	if query == "" {
		writeError(w, http.StatusBadRequest, "q parameter is required")
		return
	}

	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
	if page < 1 {
		page = defaultPage
	}
	if perPage < 1 {
		perPage = defaultPerPage
	}
	if perPage > maxPerPage {
		perPage = maxPerPage
	}

	mode := r.URL.Query().Get("mode")

	var result *service.ListArticlesResult
	var err error

	switch mode {
	case "semantic":
		// Pro-only: check subscription
		user, userErr := h.userRepo.GetByID(r.Context(), userID)
		if userErr != nil || user == nil || user.Subscription == "free" {
			writeError(w, http.StatusForbidden, "semantic search requires Pro subscription")
			return
		}
		result, err = h.articleService.SemanticSearch(r.Context(), userID, query, page, perPage)
	default:
		result, err = h.articleService.Search(r.Context(), userID, query, page, perPage)
	}

	if err != nil {
		handleServiceError(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, ListResponse{
		Data: result.Articles,
		Pagination: PaginationResponse{
			Page:    page,
			PerPage: perPage,
			Total:   result.Total,
		},
	})
}
```

**Note:** `userRepoForQuota` interface needs to be defined or use the existing user repo interface pattern in the handler package. Check existing handler patterns (e.g., `article_handler.go`) for how `userRepo` is referenced. You may need to use `*repository.UserRepo` directly.

- [ ] **Step 4: Build to verify compilation**

```bash
cd server && go build ./... && echo "OK"
```

Expect compilation errors from `NewSearchHandler` call site in `main.go` — that gets fixed in Task 8 (wiring).

- [ ] **Step 5: Commit (even if build fails — wiring fix comes in Task 8)**

```bash
cd server && git add internal/service/article.go internal/api/handler/search.go
git commit -m "feat: add semantic search service and handler

- ArticleService gets aiClient dependency for ExpandQuery + RerankArticles
- SemanticSearch: expand → broad recall → LLM rerank → paginate
- HandleSearch: mode=semantic routes to SemanticSearch (Pro-only)
- Graceful degradation at every stage"
```

---

## Task 6: Related Articles Worker

**Files:**
- Modify: `server/internal/worker/tasks.go:10-15` (new task type + payload)
- Create: `server/internal/worker/relate_handler.go`
- Modify: `server/internal/worker/ai_handler.go:214-223` (enqueue relate task)
- Modify: `server/internal/worker/server.go:12` (register handler)

- [ ] **Step 1: Add relate task type and payload to tasks.go**

In `server/internal/worker/tasks.go`, add after line 15 (after `TypePushEcho`):
```go
TypeArticleRelate = "article:relate"
```

Add payload struct and constructor after `NewImageUploadTask`:
```go
type RelatePayload struct {
	ArticleID string `json:"article_id"`
	UserID    string `json:"user_id"`
}

func NewRelateTask(articleID, userID string) *asynq.Task {
	payload, _ := json.Marshal(RelatePayload{
		ArticleID: articleID,
		UserID:    userID,
	})
	return asynq.NewTask(TypeArticleRelate, payload,
		asynq.Queue(QueueLow),
		asynq.MaxRetry(2),
		asynq.Timeout(60*time.Second),
	)
}
```

- [ ] **Step 2: Create relate_handler.go**

Create `server/internal/worker/relate_handler.go`:

```go
package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

type relateArticleRepo interface {
	GetByID(ctx context.Context, id string) (*domain.Article, error)
}

type relateRAGRepo interface {
	BroadRecallSummaries(ctx context.Context, userID string, keywords []string, excludeID string, limit int) ([]domain.RAGSource, error)
}

type RelateHandler struct {
	aiClient     client.Analyzer
	articleRepo  relateArticleRepo
	ragRepo      relateRAGRepo
	relationRepo *repository.RelationRepo
}

func NewRelateHandler(
	aiClient client.Analyzer,
	articleRepo *repository.ArticleRepo,
	ragRepo *repository.RAGRepo,
	relationRepo *repository.RelationRepo,
) *RelateHandler {
	return &RelateHandler{
		aiClient:     aiClient,
		articleRepo:  articleRepo,
		ragRepo:      ragRepo,
		relationRepo: relationRepo,
	}
}

func (h *RelateHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p RelatePayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal relate payload: %w", err)
	}

	start := time.Now()

	// 1. Get the source article
	article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
	if err != nil || article == nil {
		return fmt.Errorf("get article for relate: %w", err)
	}

	// Need semantic_keywords to do recall
	if len(article.SemanticKeywords) == 0 {
		slog.Info("relate: article has no semantic_keywords, skipping", "article_id", p.ArticleID)
		return nil
	}

	// 2. Broad recall using semantic_keywords, exclude self
	candidates, err := h.ragRepo.BroadRecallSummaries(ctx, p.UserID, article.SemanticKeywords, p.ArticleID, 30)
	if err != nil || len(candidates) == 0 {
		slog.Info("relate: no candidates found", "article_id", p.ArticleID, "error", err)
		return nil // Not an error — just no related articles
	}

	// 3. Build rerank candidates
	rerankCandidates := make([]client.RerankCandidate, len(candidates))
	for i, c := range candidates {
		summary := ""
		if c.Summary != nil {
			summary = *c.Summary
		}
		rerankCandidates[i] = client.RerankCandidate{
			Index:   i + 1,
			Title:   c.Title,
			Summary: summary,
		}
	}

	// 4. Ask LLM to select related articles
	title := ""
	if article.Title != nil {
		title = *article.Title
	}
	summary := ""
	if article.Summary != nil {
		summary = *article.Summary
	}

	related, err := h.aiClient.SelectRelatedArticles(ctx, title, summary, rerankCandidates)
	if err != nil {
		return fmt.Errorf("select related articles: %w", err)
	}

	if len(related) == 0 {
		slog.Info("relate: LLM found no related articles", "article_id", p.ArticleID)
		return nil
	}

	// 5. Build relations (score = 5,4,3,2,1 by position)
	relations := make([]repository.ArticleRelation, 0, len(related))
	for i, r := range related {
		idx := r.Index - 1
		if idx < 0 || idx >= len(candidates) {
			continue
		}
		relations = append(relations, repository.ArticleRelation{
			SourceArticleID:  p.ArticleID,
			RelatedArticleID: candidates[idx].ArticleID,
			RelevanceReason:  r.Reason,
			Score:            5 - i,
		})
	}

	// 6. Replace (idempotent: DELETE + INSERT in transaction)
	if err := h.relationRepo.ReplaceForSource(ctx, p.ArticleID, relations); err != nil {
		return fmt.Errorf("save relations: %w", err)
	}

	slog.Info("relate task completed",
		"article_id", p.ArticleID,
		"relations", len(relations),
		"duration_ms", time.Since(start).Milliseconds(),
	)

	return nil
}
```

- [ ] **Step 3: Enqueue article:relate in AI handler**

In `server/internal/worker/ai_handler.go`, after the echo enqueue block (after line 223), add:

```go
	// Enqueue related article computation (non-blocking)
	relateTask := NewRelateTask(p.ArticleID, p.UserID)
	if _, err := h.asynqClient.EnqueueContext(ctx, relateTask); err != nil {
		slog.Error("[RELATE] failed to enqueue for article",
			"article_id", p.ArticleID,
			"error", err,
		)
	}
```

- [ ] **Step 4: Register relate handler in worker server**

In `server/internal/worker/server.go`, update `NewWorkerServer` signature (line 12) to accept `relate *RelateHandler`:

```go
func NewWorkerServer(redisAddr string, crawl *CrawlHandler, ai *AIHandler, image *ImageHandler, echo *EchoHandler, push *PushHandler, relate *RelateHandler) *WorkerServer {
```

Add registration after the push handler block (around line 36):
```go
	if relate != nil {
		mux.HandleFunc(TypeArticleRelate, relate.ProcessTask)
	}
```

- [ ] **Step 5: Build to verify compilation**

```bash
cd server && go build ./... && echo "OK"
```

Expect build failure from `main.go` — `NewWorkerServer` now takes extra param. Fixed in Task 8.

- [ ] **Step 6: Commit**

```bash
cd server && git add internal/worker/tasks.go internal/worker/relate_handler.go internal/worker/ai_handler.go internal/worker/server.go
git commit -m "feat: add article:relate worker for computing related articles

- RelateHandler: reads semantic_keywords → broad recall → LLM selection → cache
- Enqueued after article:ai completes (alongside echo:generate)
- Idempotent: DELETE + INSERT in transaction for retry safety
- Score by position (5,4,3,2,1) for ordering"
```

---

## Task 7: Related Articles API

**Files:**
- Create: `server/internal/api/handler/relation.go`
- Modify: `server/internal/api/router.go`

- [ ] **Step 1: Create relation handler**

Create `server/internal/api/handler/relation.go`:

```go
package handler

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/api/middleware"
	"folio-server/internal/repository"
)

type RelationHandler struct {
	relationRepo *repository.RelationRepo
}

func NewRelationHandler(relationRepo *repository.RelationRepo) *RelationHandler {
	return &RelationHandler{relationRepo: relationRepo}
}

func (h *RelationHandler) HandleGetRelated(w http.ResponseWriter, r *http.Request) {
	_ = middleware.UserIDFromContext(r.Context()) // auth check
	articleID := chi.URLParam(r, "id")
	if articleID == "" {
		writeError(w, http.StatusBadRequest, "article id is required")
		return
	}

	related, err := h.relationRepo.ListBySource(r.Context(), articleID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get related articles")
		return
	}

	if related == nil {
		related = []repository.RelatedArticle{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"articles": related})
}
```

- [ ] **Step 2: Register route in router**

In `server/internal/api/router.go`, find where article routes are registered (around line 69-75). Add after the existing article routes:

```go
r.Get("/articles/{id}/related", deps.RelationHandler.HandleGetRelated)
```

Also add `RelationHandler *handler.RelationHandler` to the `RouterDeps` struct.

- [ ] **Step 3: Commit**

```bash
cd server && git add internal/api/handler/relation.go internal/api/router.go
git commit -m "feat: add GET /articles/{id}/related API endpoint

Returns precomputed related articles from article_relations cache table."
```

---

## Task 8: Wiring — main.go

**Files:**
- Modify: `server/cmd/server/main.go`

This task updates all constructor calls to pass new dependencies.

- [ ] **Step 1: Update service and handler initialization in main.go**

Changes needed:

1. **ArticleService** (line 94-97): add `aiAnalyzer` parameter:
```go
articleService := service.NewArticleService(
	articleRepo, taskRepo, tagRepo, categoryRepo,
	quotaService, asynqClient, aiAnalyzer,
)
```

2. **SearchHandler** (line 103): add `userRepo` parameter:
```go
searchHandler := handler.NewSearchHandler(articleService, userRepo)
```

3. **RelationRepo + RelationHandler** (add after highlightHandler, around line 128):
```go
relationRepo := repository.NewRelationRepo(pool)
relationHandler := handler.NewRelationHandler(relationRepo)
```

4. **RouterDeps** (line 146-160): add `RelationHandler`:
```go
RelationHandler: relationHandler,
```

5. **RelateHandler** (add after echoHandler, around line 166):
```go
relateHandler := worker.NewRelateHandler(aiAnalyzer, articleRepo, ragRepo, relationRepo)
```

6. **WorkerServer** calls (lines 172-174): add `relateHandler`:
```go
if r2Client != nil {
	imageHandler := worker.NewImageHandler(r2Client, articleRepo)
	workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, imageHandler, echoHandler, pushHandler, relateHandler)
} else {
	workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, nil, echoHandler, pushHandler, relateHandler)
}
```

- [ ] **Step 2: Build to verify full compilation**

```bash
cd server && go build ./... && echo "OK"
```

This should now compile successfully with all tasks wired together.

- [ ] **Step 3: Commit**

```bash
cd server && git add cmd/server/main.go
git commit -m "feat: wire smart retrieval dependencies in main.go

- ArticleService receives aiClient for semantic search
- SearchHandler receives userRepo for Pro subscription check
- RelationRepo + RelationHandler initialized and registered
- RelateHandler wired into WorkerServer"
```

---

## Task 9: Smoke Test

- [ ] **Step 1: Rebuild and restart dev server**

```bash
cd server && docker compose -f docker-compose.local.yml up --build -d app
```

- [ ] **Step 2: Verify migration applied**

```bash
cd server && docker compose -f docker-compose.local.yml exec postgres psql -U folio -d folio -c "\d articles" | grep semantic_keywords
cd server && docker compose -f docker-compose.local.yml exec postgres psql -U folio -d folio -c "\d article_relations"
```

Expected: `semantic_keywords` column visible, `article_relations` table exists.

- [ ] **Step 3: Test related articles endpoint**

```bash
# Should return empty array for any article (no relations computed yet)
curl -s http://localhost:8080/api/v1/articles/SOME_ARTICLE_ID/related -H "Authorization: Bearer TOKEN" | jq .
```

- [ ] **Step 4: Test semantic search endpoint**

```bash
# Should work (or gracefully degrade) for Pro users
curl -s "http://localhost:8080/api/v1/articles/search?q=test&mode=semantic" -H "Authorization: Bearer TOKEN" | jq .
```

- [ ] **Step 5: Check logs for new AI analysis output**

Submit a new article and watch for `semantic_keywords` in the AI analysis:
```bash
cd server && docker compose -f docker-compose.local.yml logs -f app | grep -E 'semantic|relate'
```

- [ ] **Step 6: Commit any fixes from smoke testing**

---

## Task 10: E2E Tests (optional, post-launch)

**Files:**
- Create: `server/tests/e2e/test_smart_retrieval.py`

Detailed test implementation per spec Section 16. Covers:
1. Semantic search: create articles → AI analysis → `GET /articles/search?mode=semantic`
2. Related articles: create related articles → wait for relate worker → `GET /articles/{id}/related`
3. Degradation: verify keyword fallback when mode=semantic and expansion fails

This task can be done after the core functionality is verified working.
