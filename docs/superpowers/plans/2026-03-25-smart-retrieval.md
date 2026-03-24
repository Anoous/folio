# Smart Retrieval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build LLM-powered retrieval infrastructure that unlocks semantic search, RAG quality upgrade, and related article recommendations — without vector embeddings.

**Architecture:** Three-stage pipeline: LLM query expansion → multi-path keyword recall (semantic_keywords array + title trigram + summary/key_points ILIKE) → LLM relevance judgment. Existing pg_trgm handles fast filtering; DeepSeek LLM handles semantic understanding. Related articles are precomputed at ingestion time.

**Tech Stack:** Go 1.24, PostgreSQL 16 (pg_trgm), DeepSeek Chat API, asynq (Redis task queue), chi v5 router

**Spec:** `docs/superpowers/specs/2026-03-24-smart-retrieval-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `server/migrations/012_smart_retrieval.up.sql` | Add semantic_keywords column, summary trigram index, article_relations table, drop article_embeddings |
| `server/migrations/012_smart_retrieval.down.sql` | Reverse migration |
| `server/internal/repository/relation.go` | article_relations CRUD (SaveBatch, ListBySource, DeleteBySource) |
| `server/internal/worker/relate_handler.go` | article:relate worker — compute related articles for a new article |
| `server/internal/api/handler/relation.go` | GET /articles/{id}/related HTTP handler |

### Modified Files
| File | Changes |
|------|---------|
| `server/internal/client/ai.go:22-45` | Add `SemanticKeywords` to AnalyzeResponse; add `ExpandQuery`, `RerankArticles`, `SelectRelatedArticles` to Analyzer interface; implement on DeepSeekAnalyzer; update Analyze prompt |
| `server/internal/client/ai_mock.go:13+` | Mock implementations for all new methods + SemanticKeywords field |
| `server/internal/domain/article.go:29-58` | Add `SemanticKeywords []string` to Article struct |
| `server/internal/domain/rag.go:5-12` | Add `KeyPoints []string` to RAGSource struct |
| `server/internal/repository/article.go:313-338` | Add `SemanticKeywords` to AIResult struct and UpdateAIResult SQL; add `BroadRecallArticles` method |
| `server/internal/repository/rag.go:52-88` | Add `BroadRecallSummaries` method |
| `server/internal/service/rag.go:153-194` | Replace >500 fallback in `applyTokenBudget` with ExpandQuery → BroadRecallSummaries |
| `server/internal/service/article.go:15-40` | Add `aiClient` field + constructor param; add `SemanticSearch` method |
| `server/internal/api/handler/search.go:19-53` | Add `mode=semantic` routing in HandleSearch |
| `server/internal/worker/tasks.go:10-20` | Add `TypeRelateArticle` constant, `RelatePayload`, `NewRelateTask` |
| `server/internal/worker/ai_handler.go:214-223` | Enqueue article:relate after AI analysis |
| `server/internal/worker/server.go:12-39` | Add RelateHandler param and mux registration |
| `server/internal/api/router.go:15-113` | Add RelationHandler to RouterDeps; register GET route |
| `server/cmd/server/main.go:89-175` | Wire up new dependencies (aiClient → ArticleService, RelateHandler, RelationHandler) |

### Test Files
| File | Tests |
|------|-------|
| `server/internal/client/ai_test.go` | ExpandQuery JSON parse, RerankArticles parse, SelectRelatedArticles parse, escapeILIKE |
| `server/internal/worker/ai_handler_test.go` | Verify relate task enqueued after AI success |
| `server/tests/e2e/test_14_smart_retrieval.py` | Semantic search, related articles, degradation |

---

## Task 1: Database Migration

**Files:**
- Create: `server/migrations/012_smart_retrieval.up.sql`
- Create: `server/migrations/012_smart_retrieval.down.sql`

- [ ] **Step 1: Write up migration**

```sql
-- 012_smart_retrieval.up.sql

-- 1. Semantic keywords column for LLM-powered recall
ALTER TABLE articles ADD COLUMN semantic_keywords TEXT[] DEFAULT '{}';
CREATE INDEX idx_articles_semantic_keywords ON articles USING GIN (semantic_keywords);

-- 2. Summary trigram index for ILIKE acceleration
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

- [ ] **Step 2: Write down migration**

```sql
-- 012_smart_retrieval.down.sql

DROP TABLE IF EXISTS article_relations;
DROP INDEX IF EXISTS idx_articles_summary_trgm;
ALTER TABLE articles DROP COLUMN IF EXISTS semantic_keywords;
```

- [ ] **Step 3: Apply migration to dev database**

Run:
```bash
cd server && docker compose -f docker-compose.local.yml exec postgres \
  psql -U folio -d folio -f /dev/stdin < migrations/012_smart_retrieval.up.sql
```

Verify:
```bash
cd server && docker compose -f docker-compose.local.yml exec postgres \
  psql -U folio -d folio -c "\d articles" | grep semantic_keywords
```
Expected: `semantic_keywords | text[] | | | '{}'`

- [ ] **Step 4: Commit**

```bash
git add server/migrations/012_smart_retrieval.up.sql server/migrations/012_smart_retrieval.down.sql
git commit -m "feat: add migration 012 for smart retrieval (semantic_keywords, article_relations)"
```

---

## Task 2: Domain Model Updates

**Files:**
- Modify: `server/internal/domain/article.go:29-58`
- Modify: `server/internal/domain/rag.go:5-12`

- [ ] **Step 1: Add SemanticKeywords to Article struct**

In `server/internal/domain/article.go`, add after line 58 (`DeletedAt` field), before the `// Joined fields` comment:

```go
	SemanticKeywords []string `json:"semantic_keywords,omitempty"`
```

- [ ] **Step 2: Add KeyPoints to RAGSource struct**

In `server/internal/domain/rag.go`, add after the `Summary` field:

```go
	KeyPoints []string
```

- [ ] **Step 3: Verify build**

Run: `cd server && go build ./...`
Expected: clean build

- [ ] **Step 4: Commit**

```bash
git add server/internal/domain/article.go server/internal/domain/rag.go
git commit -m "feat: add SemanticKeywords to Article, KeyPoints to RAGSource"
```

---

## Task 3: AI Client — AnalyzeResponse + Prompt Update

**Files:**
- Modify: `server/internal/client/ai.go:37-45,183-217`
- Modify: `server/internal/client/ai_mock.go`
- Test: `server/internal/client/ai_test.go`

- [ ] **Step 1: Write test for SemanticKeywords in AnalyzeResponse**

Add to `server/internal/client/ai_test.go`:

```go
func TestValidateResponse_SemanticKeywords(t *testing.T) {
	resp := &AnalyzeResponse{
		Category:         "tech",
		CategoryName:     "Technology",
		Confidence:       0.9,
		Tags:             []string{"ai"},
		Summary:          "summary",
		KeyPoints:        []string{"point1"},
		Language:         "en",
		SemanticKeywords: []string{"AI", "Machine Learning"},
	}
	validateResponse(resp)

	// SemanticKeywords should be lowercased
	for _, kw := range resp.SemanticKeywords {
		if kw != strings.ToLower(kw) {
			t.Errorf("expected lowercase keyword, got %q", kw)
		}
	}

	// Empty SemanticKeywords should get default
	resp2 := &AnalyzeResponse{
		Category:     "tech",
		CategoryName: "Technology",
		Confidence:   0.9,
		Tags:         []string{"ai"},
		Summary:      "summary",
		KeyPoints:    []string{"point1"},
		Language:     "en",
	}
	validateResponse(resp2)
	if resp2.SemanticKeywords == nil {
		t.Error("expected SemanticKeywords to be initialized to empty slice, got nil")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/client/ -run TestValidateResponse_SemanticKeywords -v`
Expected: FAIL (SemanticKeywords field doesn't exist yet)

- [ ] **Step 3: Add SemanticKeywords to AnalyzeResponse struct**

In `server/internal/client/ai.go`, add to `AnalyzeResponse` struct (line 44, after Language):

```go
	SemanticKeywords []string `json:"semantic_keywords"`
```

- [ ] **Step 4: Update validateResponse to handle SemanticKeywords**

Find the `validateResponse` function in `ai.go` and add at the end:

```go
	// Lowercase all semantic keywords
	for i, kw := range resp.SemanticKeywords {
		resp.SemanticKeywords[i] = strings.ToLower(kw)
	}
	if resp.SemanticKeywords == nil {
		resp.SemanticKeywords = []string{}
	}
```

- [ ] **Step 5: Update Analyze prompt to request semantic_keywords**

In `server/internal/client/ai.go`, function `buildSystemPrompt()` (line 183). Update the prompt string — add rule 7 before the `**重要规则**` section:

```
7. **semantic_keywords**：生成 10-15 个语义关键词（全部小写），用于后续检索匹配。包含核心概念的中英文双语表达、同义词、上下位概念。
```

And update the JSON output format to include:

```json
  "semantic_keywords": ["keyword1", "关键词2", ...]
```

- [ ] **Step 6: Update MockAnalyzer.Analyze to return SemanticKeywords**

In `server/internal/client/ai_mock.go`, find the `Analyze` method. In the returned `AnalyzeResponse`, add:

```go
SemanticKeywords: []string{strings.ToLower(category), "article", "content"},
```

- [ ] **Step 7: Run tests**

Run: `cd server && go test ./internal/client/ -v`
Expected: ALL PASS

- [ ] **Step 8: Commit**

```bash
git add server/internal/client/ai.go server/internal/client/ai_mock.go server/internal/client/ai_test.go
git commit -m "feat: add semantic_keywords to AI analysis prompt and response"
```

---

## Task 4: AI Client — ExpandQuery Method

**Files:**
- Modify: `server/internal/client/ai.go:22-26`
- Modify: `server/internal/client/ai_mock.go`
- Test: `server/internal/client/ai_test.go`

- [ ] **Step 1: Write tests for ExpandQuery**

Add to `server/internal/client/ai_test.go`:

```go
func TestMockAnalyzer_ExpandQuery(t *testing.T) {
	m := &MockAnalyzer{}
	keywords, err := m.ExpandQuery(context.Background(), "经济衰退的应对策略")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(keywords) == 0 {
		t.Fatal("expected non-empty keywords")
	}
	// All keywords should be lowercase
	for _, kw := range keywords {
		if kw != strings.ToLower(kw) {
			t.Errorf("expected lowercase keyword, got %q", kw)
		}
	}
}

func TestEscapeILIKE(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello", "hello"},
		{"100%", `100\%`},
		{"under_score", `under\_score`},
		{`back\slash`, `back\\slash`},
		{"normal中文", "normal中文"},
	}
	for _, tt := range tests {
		got := EscapeILIKE(tt.input)
		if got != tt.expected {
			t.Errorf("EscapeILIKE(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && go test ./internal/client/ -run "TestMockAnalyzer_ExpandQuery|TestEscapeILIKE" -v`
Expected: FAIL

- [ ] **Step 3: Add ExpandQuery to Analyzer interface**

In `server/internal/client/ai.go`, update the `Analyzer` interface (line 22-26):

```go
type Analyzer interface {
	Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error)
	GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error)
	GenerateRAGAnswer(ctx context.Context, systemPrompt, userPrompt string) (*RAGResult, error)
	ExpandQuery(ctx context.Context, question string) ([]string, error)
	RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error)
	SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error)
}
```

- [ ] **Step 4: Add supporting types**

Add to `server/internal/client/ai.go` after the existing type definitions (after line 57):

```go
// RerankCandidate is an article summary passed to LLM for relevance judgment.
type RerankCandidate struct {
	Index     int
	Title     string
	Summary   string
	KeyPoints []string
}

// RerankResult is the LLM's relevance judgment for a candidate.
type RerankResult struct {
	Index     int    `json:"index"`
	Relevance string `json:"relevance"` // "high" or "medium"
}

// RelatedResult is the LLM's judgment of article relatedness.
type RelatedResult struct {
	Index  int    `json:"index"`
	Reason string `json:"reason"`
}

// EscapeILIKE escapes ILIKE wildcard characters in a keyword.
func EscapeILIKE(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `%`, `\%`)
	s = strings.ReplaceAll(s, `_`, `\_`)
	return s
}
```

- [ ] **Step 5: Implement ExpandQuery on DeepSeekAnalyzer**

Add to `server/internal/client/ai.go`:

```go
func (d *DeepSeekAnalyzer) ExpandQuery(ctx context.Context, question string) ([]string, error) {
	systemPrompt := `给定用户问题，生成 10-15 个搜索关键词，用于在文章库中检索相关内容。

要求：
1. 包含原始问题中的核心词
2. 包含同义词和近义表达
3. 包含中英文双语翻译（如问题是中文，补英文关键词；反之亦然）
4. 包含上下位概念（如"React"→ 补"前端框架"）
5. 所有关键词输出为小写（英文小写，中文无影响）
6. 不要解释，直接输出 JSON 数组

输出格式：["关键词1", "keyword2", ...]`

	userPrompt := fmt.Sprintf("用户问题：%s", sanitizeField(question))

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0,
		MaxTokens:      200,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("expand query: %w", err)
	}

	var keywords []string
	if err := json.Unmarshal(respBody, &keywords); err != nil {
		// Try parsing as {"keywords": [...]} wrapper
		var wrapper struct {
			Keywords []string `json:"keywords"`
		}
		if err2 := json.Unmarshal(respBody, &wrapper); err2 != nil {
			return nil, fmt.Errorf("parse expand query response: %w (raw: %s)", err, string(respBody))
		}
		keywords = wrapper.Keywords
	}

	// Ensure lowercase
	for i, kw := range keywords {
		keywords[i] = strings.ToLower(strings.TrimSpace(kw))
	}

	return keywords, nil
}
```

> **Note:** Add a `doRequest` helper for the new methods only. Do NOT refactor existing `Analyze`, `GenerateEchoCards`, or `GenerateRAGAnswer` to use it — they have method-specific timeout and parsing logic that would regress. Only `ExpandQuery`, `RerankArticles`, and `SelectRelatedArticles` use `doRequest`.

```go
// doRequest sends a chat request and returns the raw content string from the first choice.
func (d *DeepSeekAnalyzer) doRequest(ctx context.Context, chatReq chatRequest) ([]byte, error) {
	body, err := json.Marshal(chatReq)
	if err != nil {
		return nil, fmt.Errorf("marshal chat request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", d.baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+d.apiKey)

	resp, err := d.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("deepseek request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("deepseek api error: status %d, body: %s", resp.StatusCode, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, fmt.Errorf("decode chat response: %w", err)
	}
	if chatResp.Error != nil {
		return nil, fmt.Errorf("deepseek api error: %s", chatResp.Error.Message)
	}
	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("deepseek returned no choices")
	}

	return []byte(chatResp.Choices[0].Message.Content), nil
}
```

Leave existing `Analyze`, `GenerateEchoCards`, and `GenerateRAGAnswer` methods unchanged — they have their own timeout and parsing logic.

- [ ] **Step 6: Implement MockAnalyzer.ExpandQuery**

In `server/internal/client/ai_mock.go`:

```go
func (m *MockAnalyzer) ExpandQuery(_ context.Context, question string) ([]string, error) {
	// Extract Chinese characters and English words as mock keywords
	keywords := []string{}
	for _, match := range reChineseChunk.FindAllString(question, 5) {
		keywords = append(keywords, match)
	}
	for _, match := range reEnglishWord.FindAllString(question, 5) {
		keywords = append(keywords, strings.ToLower(match))
	}
	if len(keywords) == 0 {
		keywords = []string{"mock", "keyword"}
	}
	return keywords, nil
}
```

- [ ] **Step 7: Run tests**

Run: `cd server && go test ./internal/client/ -v`
Expected: ALL PASS

- [ ] **Step 8: Verify build**

Run: `cd server && go build ./...`
Expected: FAIL — `RerankArticles` and `SelectRelatedArticles` not yet implemented on DeepSeekAnalyzer/MockAnalyzer. Add stub implementations that return `nil, nil` to unblock the build. These will be fully implemented in Task 5 and Task 8.

- [ ] **Step 9: Commit**

```bash
git add server/internal/client/
git commit -m "feat: add ExpandQuery to Analyzer interface with DeepSeek implementation"
```

---

## Task 5: AI Client — RerankArticles + SelectRelatedArticles

**Files:**
- Modify: `server/internal/client/ai.go`
- Modify: `server/internal/client/ai_mock.go`
- Test: `server/internal/client/ai_test.go`

- [ ] **Step 1: Write tests**

Add to `server/internal/client/ai_test.go`:

```go
func TestMockAnalyzer_RerankArticles(t *testing.T) {
	m := &MockAnalyzer{}
	candidates := []RerankCandidate{
		{Index: 1, Title: "Article A", Summary: "About AI"},
		{Index: 2, Title: "Article B", Summary: "About cooking"},
		{Index: 3, Title: "Article C", Summary: "About ML"},
	}
	results, err := m.RerankArticles(context.Background(), "machine learning", candidates)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(results) == 0 {
		t.Fatal("expected non-empty results")
	}
	// All indices should be valid
	for _, r := range results {
		if r.Index < 1 || r.Index > len(candidates) {
			t.Errorf("invalid index %d", r.Index)
		}
		if r.Relevance != "high" && r.Relevance != "medium" {
			t.Errorf("invalid relevance %q", r.Relevance)
		}
	}
}

func TestMockAnalyzer_SelectRelatedArticles(t *testing.T) {
	m := &MockAnalyzer{}
	candidates := []RerankCandidate{
		{Index: 1, Title: "Article A", Summary: "About AI"},
		{Index: 2, Title: "Article B", Summary: "About cooking"},
	}
	results, err := m.SelectRelatedArticles(context.Background(), "Test Article", "About testing", candidates)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, r := range results {
		if r.Index < 1 || r.Index > len(candidates) {
			t.Errorf("invalid index %d", r.Index)
		}
		if r.Reason == "" {
			t.Error("expected non-empty reason")
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && go test ./internal/client/ -run "TestMockAnalyzer_Rerank|TestMockAnalyzer_SelectRelated" -v`
Expected: FAIL

- [ ] **Step 3: Implement RerankArticles on DeepSeekAnalyzer**

```go
func (d *DeepSeekAnalyzer) RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "用户问题：%s\n\n以下是候选文章列表。判断每篇与用户问题的相关程度，返回最相关的 Top 10。\n\n候选文章：\n", sanitizeField(question))
	for _, c := range candidates {
		kp := ""
		if len(c.KeyPoints) > 0 {
			kp = " | 关键点: " + strings.Join(c.KeyPoints, ", ")
		}
		fmt.Fprintf(&b, "[%d] 《%s》: %s%s\n", c.Index, c.Title, c.Summary, kp)
	}

	systemPrompt := `判断候选文章与用户问题的相关程度，返回最相关的 Top 10。

输出 JSON（不要 markdown 代码块）：
[{"index": 1, "relevance": "high"}, {"index": 5, "relevance": "medium"}, ...]

规则：
1. 只返回与问题相关的文章（最多 10 篇）
2. relevance: "high" = 直接相关, "medium" = 间接相关
3. 按相关程度从高到低排列
4. 不相关的不要返回`

	chatReq := chatRequest{
		Model:          "deepseek-chat",
		Messages:       []chatMessage{{Role: "system", Content: systemPrompt}, {Role: "user", Content: b.String()}},
		Temperature:    0,
		MaxTokens:      512,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("rerank articles: %w", err)
	}

	var results []RerankResult
	if err := json.Unmarshal(respBody, &results); err != nil {
		// Try wrapper format
		var wrapper struct {
			Results []RerankResult `json:"results"`
		}
		if err2 := json.Unmarshal(respBody, &wrapper); err2 != nil {
			return nil, fmt.Errorf("parse rerank response: %w (raw: %s)", err, string(respBody))
		}
		results = wrapper.Results
	}
	return results, nil
}
```

- [ ] **Step 4: Implement SelectRelatedArticles on DeepSeekAnalyzer**

```go
func (d *DeepSeekAnalyzer) SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "本文：《%s》\n摘要：%s\n\n候选文章：\n", sanitizeField(sourceTitle), sanitizeField(sourceSummary))
	for _, c := range candidates {
		fmt.Fprintf(&b, "[%d] 《%s》: %s\n", c.Index, c.Title, c.Summary)
	}

	systemPrompt := `从候选中选出与本文最相关的 5 篇（不超过 5 篇），输出 JSON：
[{"index": 1, "reason": "一句话说明关联"}, ...]

规则：
1. 关联可以是主题相关、观点互补、同一领域不同角度等
2. 优先选择跨领域的有趣关联，而非简单的主题重复
3. 没有相关的就少选，不要凑数`

	chatReq := chatRequest{
		Model:          "deepseek-chat",
		Messages:       []chatMessage{{Role: "system", Content: systemPrompt}, {Role: "user", Content: b.String()}},
		Temperature:    0,
		MaxTokens:      512,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("select related articles: %w", err)
	}

	var results []RelatedResult
	if err := json.Unmarshal(respBody, &results); err != nil {
		var wrapper struct {
			Results []RelatedResult `json:"results"`
		}
		if err2 := json.Unmarshal(respBody, &wrapper); err2 != nil {
			return nil, fmt.Errorf("parse related response: %w (raw: %s)", err, string(respBody))
		}
		results = wrapper.Results
	}
	return results, nil
}
```

- [ ] **Step 5: Implement mock versions**

In `server/internal/client/ai_mock.go`:

```go
func (m *MockAnalyzer) RerankArticles(_ context.Context, _ string, candidates []RerankCandidate) ([]RerankResult, error) {
	results := make([]RerankResult, 0, len(candidates))
	for i, c := range candidates {
		if i >= 5 {
			break
		}
		results = append(results, RerankResult{Index: c.Index, Relevance: "high"})
	}
	return results, nil
}

func (m *MockAnalyzer) SelectRelatedArticles(_ context.Context, _, _ string, candidates []RerankCandidate) ([]RelatedResult, error) {
	results := make([]RelatedResult, 0, len(candidates))
	for i, c := range candidates {
		if i >= 3 {
			break
		}
		results = append(results, RelatedResult{Index: c.Index, Reason: "mock: related topic"})
	}
	return results, nil
}
```

- [ ] **Step 6: Remove stub implementations from Task 4 Step 8 (if any)**

Replace the placeholder `nil, nil` stubs with the real implementations above.

- [ ] **Step 7: Run all tests + build**

Run: `cd server && go test ./internal/client/ -v && go build ./...`
Expected: ALL PASS, clean build

- [ ] **Step 8: Commit**

```bash
git add server/internal/client/
git commit -m "feat: add RerankArticles and SelectRelatedArticles to Analyzer"
```

---

## Task 6: Repository — UpdateAIResult + BroadRecall

**Files:**
- Modify: `server/internal/repository/article.go:313-338`
- Modify: `server/internal/repository/rag.go`

- [ ] **Step 1: Update AIResult struct and UpdateAIResult SQL**

In `server/internal/repository/article.go`, add to `AIResult` struct (line 313-319):

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

Update `UpdateAIResult` method (line 321-338) to write semantic_keywords:

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
		ai.CategoryID, ai.Summary, keyPointsJSON, ai.Confidence, ai.Language, sk, id)
	if err != nil {
		return fmt.Errorf("update ai result: %w", err)
	}
	return nil
}
```

- [ ] **Step 2: Add BroadRecallSummaries to RAGRepo**

In `server/internal/repository/rag.go`, add:

```go
// BroadRecallSummaries does multi-path keyword recall for RAG and related articles.
// Returns top-N articles matching any of the given keywords via semantic_keywords array overlap,
// title trigram similarity, or summary/key_points ILIKE.
func (r *RAGRepo) BroadRecallSummaries(ctx context.Context, userID string, keywords []string, limit int, excludeID string) ([]domain.RAGSource, error) {
	// Escape ILIKE wildcards in keywords
	escapedKeywords := make([]string, len(keywords))
	for i, kw := range keywords {
		escapedKeywords[i] = client.EscapeILIKE(kw)
	}

	rows, err := r.db.Query(ctx, `
		SELECT set_config('pg_trgm.similarity_threshold', '0.1', true);

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
				AND ($5::uuid IS NULL OR a.id != $5)
				AND (
					a.semantic_keywords && $2::text[]
					OR a.title % kw.word
					OR a.summary ILIKE '%' || $3[array_position($2::text[], kw.word)] || '%'
					OR a.key_points::text ILIKE '%' || $3[array_position($2::text[], kw.word)] || '%'
				)
			ORDER BY a.id, score DESC
		)
		SELECT id, title, summary, key_points, site_name, created_at
		FROM keyword_matches
		ORDER BY score DESC
		LIMIT $4`,
		userID, keywords, escapedKeywords, limit, nilIfEmpty(excludeID),
	)
	if err != nil {
		return nil, fmt.Errorf("broad recall summaries: %w", err)
	}
	defer rows.Close()

	sources := make([]domain.RAGSource, 0)
	for rows.Next() {
		var s domain.RAGSource
		var kpJSON []byte
		if err := rows.Scan(&s.ArticleID, &s.Title, &s.Summary, &kpJSON, &s.SiteName, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan broad recall result: %w", err)
		}
		if len(kpJSON) > 0 {
			json.Unmarshal(kpJSON, &s.KeyPoints)
		}
		sources = append(sources, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate broad recall results: %w", err)
	}
	return sources, nil
}

func nilIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
```

Use two arrays: `cleaned` (lowercase, for `&&` and `%`) and `escaped` (ILIKE-safe, for ILIKE). Add `set_config` to ensure low trigram threshold.

```go
func (r *RAGRepo) BroadRecallSummaries(ctx context.Context, userID string, keywords []string, limit int, excludeID string) ([]domain.RAGSource, error) {
	cleaned := make([]string, len(keywords))
	escaped := make([]string, len(keywords))
	for i, kw := range keywords {
		lc := strings.ToLower(strings.TrimSpace(kw))
		cleaned[i] = lc
		escaped[i] = client.EscapeILIKE(lc)
	}

	// Set low trigram threshold for broad recall (transaction-scoped)
	_, _ = r.db.Exec(ctx, `SELECT set_config('pg_trgm.similarity_threshold', '0.1', true)`)

	rows, err := r.db.Query(ctx, `
		WITH keyword_matches AS (
			SELECT DISTINCT ON (a.id)
				a.id, a.title, a.summary, a.key_points, a.site_name, a.created_at,
				CASE
					WHEN a.semantic_keywords && $2::text[] THEN 1.0
					WHEN EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw) THEN 0.6
					ELSE 0.1
				END AS score
			FROM articles a
			WHERE a.user_id = $1
				AND a.status = 'ready'
				AND a.deleted_at IS NULL
				AND ($5::uuid IS NULL OR a.id != $5)
				AND (
					a.semantic_keywords && $2::text[]
					OR EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw)
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.summary ILIKE '%' || esc || '%')
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.key_points::text ILIKE '%' || esc || '%')
				)
			ORDER BY a.id, score DESC
		)
		SELECT id, title, summary, key_points, site_name, created_at
		FROM keyword_matches
		ORDER BY score DESC
		LIMIT $4`,
		userID, cleaned, escaped, limit, nilIfEmpty(excludeID),
	)
	if err != nil {
		return nil, fmt.Errorf("broad recall summaries: %w", err)
	}
	defer rows.Close()

	sources := make([]domain.RAGSource, 0)
	for rows.Next() {
		var s domain.RAGSource
		var kpJSON []byte
		if err := rows.Scan(&s.ArticleID, &s.Title, &s.Summary, &kpJSON, &s.SiteName, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan broad recall: %w", err)
		}
		if len(kpJSON) > 0 {
			json.Unmarshal(kpJSON, &s.KeyPoints)
		}
		sources = append(sources, s)
	}
	return sources, rows.Err()
}
```

> **Key design decisions in this SQL:**
> - `$2` (`cleaned`) used for `&&` and `%` — these operators work with the raw keyword values.
> - `$3` (`escaped`) used for ILIKE — `%` and `_` characters in keywords are escaped to prevent wildcard injection.
> - `$5::uuid IS NULL` for self-exclusion — proper UUID cast, not text comparison.
> - `set_config` with threshold `0.1` ensures the `%` operator catches fuzzy matches (default 0.3 is too strict for recall).
> - `'%' || esc || '%'` — pgx does NOT use `%`-formatting, so literal `%` is correct (no `%%` doubling).

- [ ] **Step 3: Add imports to rag.go**

Add `"folio-server/internal/client"` and `"strings"` to the import block in `repository/rag.go`.

- [ ] **Step 4: Verify build**

Run: `cd server && go build ./...`
Expected: clean build

- [ ] **Step 5: Commit**

```bash
git add server/internal/repository/article.go server/internal/repository/rag.go
git commit -m "feat: add semantic_keywords to AIResult; add BroadRecallSummaries"
```

---

## Task 7: RAG Service Upgrade

**Files:**
- Modify: `server/internal/service/rag.go:153-194`

- [ ] **Step 1: Update RAGService to hold aiClient**

The `RAGService` at line 26-30 already has `aiClient client.Analyzer`. Good — no change needed.

- [ ] **Step 2: Update applyTokenBudget**

Replace the `>ragArticleFallbackCap` branch (lines 156-163) in `server/internal/service/rag.go`:

```go
func (s *RAGService) applyTokenBudget(ctx context.Context, userID, question string, articles []domain.RAGSource) []domain.RAGSource {
	if len(articles) > ragArticleFallbackCap {
		// Smart retrieval: LLM query expansion → multi-keyword broad recall
		keywords, err := s.aiClient.ExpandQuery(ctx, question)
		if err != nil {
			slog.Warn("query expansion failed, falling back to pg_trgm", "error", err)
			return s.fallbackSearch(ctx, userID, question, articles)
		}
		recalled, err := s.ragRepo.BroadRecallSummaries(ctx, userID, keywords, ragSearchFallbackSize, "")
		if err != nil || len(recalled) == 0 {
			slog.Warn("broad recall failed or empty, falling back to pg_trgm",
				"error", err, "recalled", len(recalled))
			return s.fallbackSearch(ctx, userID, question, articles)
		}
		return recalled
	}

	// < 500 articles: original token budget logic unchanged
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

// fallbackSearch is the degradation path when smart retrieval fails.
func (s *RAGService) fallbackSearch(ctx context.Context, userID, question string, articles []domain.RAGSource) []domain.RAGSource {
	searched, err := s.ragRepo.SearchArticleSummaries(ctx, userID, question, ragSearchFallbackSize)
	if err != nil || len(searched) == 0 {
		if len(articles) > ragSearchFallbackSize {
			return articles[:ragSearchFallbackSize]
		}
		return articles
	}
	return searched
}
```

- [ ] **Step 3: Verify build**

Run: `cd server && go build ./...`
Expected: clean build

- [ ] **Step 4: Commit**

```bash
git add server/internal/service/rag.go
git commit -m "feat: upgrade RAG to use ExpandQuery + BroadRecall for >500 articles"
```

---

## Task 8: Related Articles — Worker + Repository + API

**Files:**
- Create: `server/internal/repository/relation.go`
- Create: `server/internal/worker/relate_handler.go`
- Create: `server/internal/api/handler/relation.go`
- Modify: `server/internal/worker/tasks.go:10-20`
- Modify: `server/internal/worker/ai_handler.go:214-223`
- Modify: `server/internal/worker/server.go:12-39`
- Modify: `server/internal/api/router.go:15-113`
- Modify: `server/cmd/server/main.go:89-175`

- [ ] **Step 1: Add task type and payload**

In `server/internal/worker/tasks.go`, add the constant (line 15, after TypePushEcho):

```go
	TypeRelateArticle = "article:relate"
```

Add the payload struct and constructor after the existing ones:

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
	return asynq.NewTask(TypeRelateArticle, payload,
		asynq.Queue(QueueLow),
		asynq.MaxRetry(2),
		asynq.Timeout(60*time.Second),
	)
}
```

- [ ] **Step 2: Create relation repository**

Create `server/internal/repository/relation.go`:

```go
package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ArticleRelation struct {
	SourceArticleID  string
	RelatedArticleID string
	RelevanceReason  string
	Score            int
	CreatedAt        time.Time
}

type RelatedArticleRow struct {
	ID              string  `json:"id"`
	Title           string  `json:"title"`
	Summary         *string `json:"summary,omitempty"`
	SiteName        *string `json:"site_name,omitempty"`
	CoverImageURL   *string `json:"cover_image_url,omitempty"`
	RelevanceReason string  `json:"relevance_reason"`
}

type RelationRepo struct {
	pool *pgxpool.Pool
}

func NewRelationRepo(pool *pgxpool.Pool) *RelationRepo {
	return &RelationRepo{pool: pool}
}

// SaveBatch replaces all relations for a source article (idempotent).
func (r *RelationRepo) SaveBatch(ctx context.Context, sourceID string, relations []ArticleRelation) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `DELETE FROM article_relations WHERE source_article_id = $1`, sourceID)
	if err != nil {
		return fmt.Errorf("delete old relations: %w", err)
	}

	for _, rel := range relations {
		_, err = tx.Exec(ctx, `
			INSERT INTO article_relations (source_article_id, related_article_id, relevance_reason, score)
			VALUES ($1, $2, $3, $4)`,
			rel.SourceArticleID, rel.RelatedArticleID, rel.RelevanceReason, rel.Score)
		if err != nil {
			return fmt.Errorf("insert relation: %w", err)
		}
	}

	return tx.Commit(ctx)
}

// ListBySource returns related articles for a source article, ordered by score DESC.
func (r *RelationRepo) ListBySource(ctx context.Context, sourceID string) ([]RelatedArticleRow, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT a.id, a.title, a.summary, a.site_name, a.cover_image_url, ar.relevance_reason
		FROM article_relations ar
		JOIN articles a ON a.id = ar.related_article_id
		WHERE ar.source_article_id = $1
			AND a.deleted_at IS NULL
		ORDER BY ar.score DESC`,
		sourceID)
	if err != nil {
		return nil, fmt.Errorf("list relations: %w", err)
	}
	defer rows.Close()

	result := make([]RelatedArticleRow, 0)
	for rows.Next() {
		var r RelatedArticleRow
		if err := rows.Scan(&r.ID, &r.Title, &r.Summary, &r.SiteName, &r.CoverImageURL, &r.RelevanceReason); err != nil {
			return nil, fmt.Errorf("scan relation: %w", err)
		}
		result = append(result, r)
	}
	return result, rows.Err()
}
```

- [ ] **Step 3: Create relate handler**

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
	BroadRecallSummaries(ctx context.Context, userID string, keywords []string, limit int, excludeID string) ([]domain.RAGSource, error)
}

type relateSelector interface {
	SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []client.RerankCandidate) ([]client.RelatedResult, error)
}

type relateRelationRepo interface {
	SaveBatch(ctx context.Context, sourceID string, relations []repository.ArticleRelation) error
}

type RelateHandler struct {
	articleRepo  relateArticleRepo
	ragRepo      relateRAGRepo
	aiClient     relateSelector
	relationRepo relateRelationRepo
}

func NewRelateHandler(
	articleRepo relateArticleRepo,
	ragRepo relateRAGRepo,
	aiClient relateSelector,
	relationRepo relateRelationRepo,
) *RelateHandler {
	return &RelateHandler{
		articleRepo:  articleRepo,
		ragRepo:      ragRepo,
		aiClient:     aiClient,
		relationRepo: relationRepo,
	}
}

func (h *RelateHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p RelatePayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal relate payload: %w", err)
	}

	start := time.Now()

	article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
	if err != nil || article == nil {
		return fmt.Errorf("get article %s: %w", p.ArticleID, err)
	}

	// Need semantic_keywords to do recall
	if len(article.SemanticKeywords) == 0 {
		slog.Info("[RELATE] skipping — no semantic_keywords", "article_id", p.ArticleID)
		return nil
	}

	// Broad recall using article's semantic_keywords, excluding self
	candidates, err := h.ragRepo.BroadRecallSummaries(ctx, p.UserID, article.SemanticKeywords, 30, p.ArticleID)
	if err != nil || len(candidates) == 0 {
		slog.Info("[RELATE] no candidates found", "article_id", p.ArticleID, "error", err)
		return nil // Not an error — just no related articles
	}

	// Build RerankCandidate list
	rerankCandidates := make([]client.RerankCandidate, len(candidates))
	for i, c := range candidates {
		summary := ""
		if c.Summary != nil {
			summary = *c.Summary
		}
		rerankCandidates[i] = client.RerankCandidate{
			Index:     i + 1,
			Title:     c.Title,
			Summary:   summary,
			KeyPoints: c.KeyPoints,
		}
	}

	title := ""
	if article.Title != nil {
		title = *article.Title
	}
	summary := ""
	if article.Summary != nil {
		summary = *article.Summary
	}

	results, err := h.aiClient.SelectRelatedArticles(ctx, title, summary, rerankCandidates)
	if err != nil {
		slog.Error("[RELATE] LLM selection failed", "article_id", p.ArticleID, "error", err)
		return fmt.Errorf("select related articles: %w", err)
	}

	// Map results back to article IDs and save
	relations := make([]repository.ArticleRelation, 0, len(results))
	for rank, r := range results {
		idx := r.Index - 1
		if idx < 0 || idx >= len(candidates) {
			continue
		}
		relations = append(relations, repository.ArticleRelation{
			SourceArticleID:  p.ArticleID,
			RelatedArticleID: candidates[idx].ArticleID,
			RelevanceReason:  r.Reason,
			Score:            5 - rank, // 5, 4, 3, 2, 1
		})
	}

	if len(relations) > 0 {
		if err := h.relationRepo.SaveBatch(ctx, p.ArticleID, relations); err != nil {
			return fmt.Errorf("save relations: %w", err)
		}
	}

	slog.Info("[RELATE] completed",
		"article_id", p.ArticleID,
		"candidates", len(candidates),
		"related", len(relations),
		"duration_ms", time.Since(start).Milliseconds(),
	)
	return nil
}
```

- [ ] **Step 4: Enqueue relate task from AI handler**

In `server/internal/worker/ai_handler.go`, after the echo task enqueue block (line ~223), add:

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

- [ ] **Step 5: Register relate handler in worker server**

In `server/internal/worker/server.go`, update `NewWorkerServer` signature to accept `*RelateHandler`:

```go
func NewWorkerServer(redisAddr string, crawl *CrawlHandler, ai *AIHandler, image *ImageHandler, echo *EchoHandler, push *PushHandler, relate *RelateHandler) *WorkerServer {
```

Add to mux registration (after the push block):

```go
	if relate != nil {
		mux.HandleFunc(TypeRelateArticle, relate.ProcessTask)
	}
```

- [ ] **Step 6: Create relation API handler**

Create `server/internal/api/handler/relation.go`:

```go
package handler

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"folio-server/internal/repository"
)

type RelationHandler struct {
	relationRepo *repository.RelationRepo
}

func NewRelationHandler(relationRepo *repository.RelationRepo) *RelationHandler {
	return &RelationHandler{relationRepo: relationRepo}
}

func (h *RelationHandler) HandleGetRelated(w http.ResponseWriter, r *http.Request) {
	articleID := chi.URLParam(r, "id")
	if articleID == "" {
		writeError(w, http.StatusBadRequest, "article id required")
		return
	}

	related, err := h.relationRepo.ListBySource(r.Context(), articleID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get related articles")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"articles": related,
	})
}
```

- [ ] **Step 7: Register route**

In `server/internal/api/router.go`, add `RelationHandler` to `RouterDeps` (line 30, after DeviceHandler):

```go
	RelationHandler *handler.RelationHandler
```

Add route in protected group (after the highlights routes, line ~95):

```go
			// Related articles
			r.Get("/articles/{id}/related", deps.RelationHandler.HandleGetRelated)
```

- [ ] **Step 8: Wire everything in main.go**

In `server/cmd/server/main.go`, add after `ragRepo` initialization (line ~137):

```go
	relationRepo := repository.NewRelationRepo(pool)
```

Add RelationHandler after ragAPIHandler (line ~139):

```go
	relationHandler := handler.NewRelationHandler(relationRepo)
```

Add to RouterDeps (line ~160):

```go
		RelationHandler: relationHandler,
```

Create RelateHandler and update workerServer creation (lines ~164-175):

```go
	relateHandler := worker.NewRelateHandler(articleRepo, ragRepo, aiAnalyzer, relationRepo)
```

Update `NewWorkerServer` calls (both with and without imageHandler):

```go
	if r2Client != nil {
		imageHandler := worker.NewImageHandler(r2Client, articleRepo)
		workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, imageHandler, echoHandler, pushHandler, relateHandler)
	} else {
		workerServer = worker.NewWorkerServer(cfg.RedisAddr, crawlHandler, aiHandler, nil, echoHandler, pushHandler, relateHandler)
	}
```

- [ ] **Step 9: Update ArticleRepo.GetByID to scan semantic_keywords**

In `server/internal/repository/article.go:66-99`, the `GetByID` method does NOT select `semantic_keywords`. The relate handler depends on it. Add `semantic_keywords` to the SELECT (after `deleted_at`) and to the Scan (after `&a.DeletedAt`):

SELECT addition (line 74, after `deleted_at`):
```sql
		       created_at, updated_at, deleted_at, semantic_keywords
```

Scan addition (line 82, after `&a.DeletedAt`):
```go
		&a.CreatedAt, &a.UpdatedAt, &a.DeletedAt, &a.SemanticKeywords,
```

After Scan, initialize nil slice:
```go
	if a.SemanticKeywords == nil {
		a.SemanticKeywords = []string{}
	}
```

- [ ] **Step 10: Verify build**

Run: `cd server && go build ./...`
Expected: clean build

- [ ] **Step 11: Commit**

```bash
git add server/internal/repository/relation.go server/internal/worker/relate_handler.go \
  server/internal/api/handler/relation.go server/internal/worker/tasks.go \
  server/internal/worker/ai_handler.go server/internal/worker/server.go \
  server/internal/api/router.go server/cmd/server/main.go \
  server/internal/repository/article.go
git commit -m "feat: add article:relate worker, relation repo, and GET /articles/{id}/related"
```

---

## Task 9: Semantic Search API

**Files:**
- Modify: `server/internal/service/article.go:15-40`
- Modify: `server/internal/api/handler/search.go:19-53`
- Modify: `server/internal/repository/article.go` (add BroadRecallArticles)

- [ ] **Step 1: Add BroadRecallArticles to ArticleRepo**

In `server/internal/repository/article.go`, add a method that returns `[]domain.Article` instead of `[]domain.RAGSource`:

```go
// BroadRecallArticles does multi-path keyword recall returning full Article objects for semantic search.
// Same SQL logic as BroadRecallSummaries but returns domain.Article.
func (r *ArticleRepo) BroadRecallArticles(ctx context.Context, userID string, keywords []string, limit int) ([]domain.Article, error) {
	cleaned := make([]string, len(keywords))
	escaped := make([]string, len(keywords))
	for i, kw := range keywords {
		lc := strings.ToLower(strings.TrimSpace(kw))
		cleaned[i] = lc
		escaped[i] = client.EscapeILIKE(lc)
	}

	// Set low trigram threshold for broad recall
	_, _ = r.pool.Exec(ctx, `SELECT set_config('pg_trgm.similarity_threshold', '0.1', true)`)

	rows, err := r.pool.Query(ctx, `
		WITH keyword_matches AS (
			SELECT DISTINCT ON (a.id)
				a.id, a.user_id, a.url, a.title, a.summary, a.site_name, a.source_type, a.created_at,
				CASE
					WHEN a.semantic_keywords && $2::text[] THEN 1.0
					WHEN EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw) THEN 0.6
					ELSE 0.1
				END AS score
			FROM articles a
			WHERE a.user_id = $1
				AND a.status = 'ready'
				AND a.deleted_at IS NULL
				AND (
					a.semantic_keywords && $2::text[]
					OR EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw)
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.summary ILIKE '%' || esc || '%')
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.key_points::text ILIKE '%' || esc || '%')
				)
			ORDER BY a.id, score DESC
		)
		SELECT id, user_id, url, title, summary, site_name, source_type, created_at
		FROM keyword_matches
		ORDER BY score DESC
		LIMIT $4`,
		userID, cleaned, escaped, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("broad recall articles: %w", err)
	}
	defer rows.Close()

	articles := make([]domain.Article, 0)
	for rows.Next() {
		var a domain.Article
		if err := rows.Scan(&a.ID, &a.UserID, &a.URL, &a.Title, &a.Summary,
			&a.SiteName, &a.SourceType, &a.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan broad recall article: %w", err)
		}
		a.KeyPoints = []string{}
		articles = append(articles, a)
	}
	return articles, rows.Err()
}
```

- [ ] **Step 2: Add aiClient to ArticleService**

In `server/internal/service/article.go`, add local interfaces for the new methods needed:

```go
type queryExpander interface {
	ExpandQuery(ctx context.Context, question string) ([]string, error)
	RerankArticles(ctx context.Context, question string, candidates []client.RerankCandidate) ([]client.RerankResult, error)
}

type broadRecaller interface {
	BroadRecallArticles(ctx context.Context, userID string, keywords []string, limit int) ([]domain.Article, error)
}
```

Add fields to `ArticleService` struct:

```go
type ArticleService struct {
	articleRepo   articleCreator
	taskRepo      taskCreator
	tagRepo       tagAttacher
	categoryRepo  categoryGetter
	quotaService  quotaChecker
	asynqClient   taskEnqueuer
	aiClient      queryExpander  // NEW — for ExpandQuery + RerankArticles
	broadRecaller broadRecaller  // NEW — for BroadRecallArticles
}
```

Update `NewArticleService` to accept and store it:

```go
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
		articleRepo:   articleRepo,
		taskRepo:      taskRepo,
		tagRepo:       tagRepo,
		categoryRepo:  categoryRepo,
		quotaService:  quotaService,
		asynqClient:   asynqClient,
		aiClient:      aiClient,      // NEW
		broadRecaller: articleRepo,    // NEW — ArticleRepo implements broadRecaller
	}
}
```

- [ ] **Step 3: Add SemanticSearch method**

Add to `server/internal/service/article.go`:

```go
// SemanticSearch does LLM-powered search: expand query → broad recall → LLM rerank.
func (s *ArticleService) SemanticSearch(ctx context.Context, userID, question string, page, perPage int) (*repository.ListArticlesResult, error) {
	// 1. Expand query
	keywords, err := s.aiClient.ExpandQuery(ctx, question)
	if err != nil {
		slog.Warn("semantic search: query expansion failed, falling back to keyword", "error", err)
		return s.Search(ctx, userID, question, page, perPage)
	}

	// 2. Broad recall
	candidates, err := s.broadRecaller.BroadRecallArticles(ctx, userID, keywords, 50)
	if err != nil || len(candidates) == 0 {
		slog.Warn("semantic search: broad recall failed, falling back to keyword", "error", err)
		return s.Search(ctx, userID, question, page, perPage)
	}

	// 3. LLM rerank
	rerankCandidates := make([]client.RerankCandidate, len(candidates))
	for i, a := range candidates {
		summary := ""
		if a.Summary != nil {
			summary = *a.Summary
		}
		rerankCandidates[i] = client.RerankCandidate{
			Index:     i + 1,
			Title:     derefStringPtr(a.Title),
			Summary:   summary,
			KeyPoints: a.KeyPoints,
		}
	}

	ranked, err := s.aiClient.RerankArticles(ctx, question, rerankCandidates)
	if err != nil {
		slog.Warn("semantic search: rerank failed, returning recall order", "error", err)
		// Degrade to recall order
		total := len(candidates)
		start := (page - 1) * perPage
		end := start + perPage
		if start > total { start = total }
		if end > total { end = total }
		return &repository.ListArticlesResult{Articles: candidates[start:end], Total: total}, nil
	}

	// 4. Map ranked indices back
	reranked := make([]domain.Article, 0, len(ranked))
	for _, r := range ranked {
		idx := r.Index - 1
		if idx >= 0 && idx < len(candidates) {
			reranked = append(reranked, candidates[idx])
		}
	}

	total := len(reranked)
	start := (page - 1) * perPage
	end := start + perPage
	if start > total { start = total }
	if end > total { end = total }
	return &repository.ListArticlesResult{Articles: reranked[start:end], Total: total}, nil
}

func derefStringPtr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
```

- [ ] **Step 4: Update HandleSearch for mode parameter**

In `server/internal/api/handler/search.go`, update `HandleSearch`:

```go
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
		// Pro-only gate: semantic search requires subscription
		// (SemanticSearch internally degrades to keyword search if not Pro,
		//  or check subscription here and return 403 for Free users)
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

- [ ] **Step 5: Update main.go ArticleService construction**

In `server/cmd/server/main.go`, update the `articleService` initialization (line 94-97):

```go
	articleService := service.NewArticleService(
		articleRepo, taskRepo, tagRepo, categoryRepo,
		quotaService, asynqClient, aiAnalyzer,
	)
```

- [ ] **Step 6: Fix any import issues and ListArticlesResult type references**

The `SemanticSearch` returns `*repository.ListArticlesResult`. The existing `Search` method also returns this. Make sure the handler uses the correct type. If `service` package re-exports it, use that.

- [ ] **Step 7: Verify build**

Run: `cd server && go build ./...`
Expected: clean build

- [ ] **Step 8: Commit**

```bash
git add server/internal/service/article.go server/internal/api/handler/search.go \
  server/internal/repository/article.go server/cmd/server/main.go
git commit -m "feat: add semantic search API (mode=semantic on /articles/search)"
```

---

## Task 10: AI Handler Test Update

**Files:**
- Modify: `server/internal/worker/ai_handler_test.go`

- [ ] **Step 1: Update mock analyzer to include SemanticKeywords**

In `server/internal/worker/ai_handler_test.go`, the `mockAnalyzer` struct only has `Analyze`. Add `SemanticKeywords` to the mock response in the test setup, and ensure `AIResult` includes `SemanticKeywords` in assertions.

Update the mock response in test fixtures to include:

```go
SemanticKeywords: []string{"mock", "keyword"},
```

And verify that after `ProcessTask` runs, the updated AI result includes `SemanticKeywords`.

- [ ] **Step 2: Test that relate task is enqueued**

Add a test that verifies after successful AI processing, both echo and relate tasks are enqueued:

```go
func TestAIHandler_EnqueuesRelateTask(t *testing.T) {
	// ... setup mocks (similar to existing happy path test) ...
	// After ProcessTask, verify mockEnqueuer received a task of type "article:relate"
}
```

- [ ] **Step 3: Run tests**

Run: `cd server && go test ./internal/worker/ -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add server/internal/worker/ai_handler_test.go
git commit -m "test: update AI handler test for semantic_keywords and relate task enqueue"
```

---

## Task 11: E2E Test

**Files:**
- Create: `server/tests/e2e/test_14_smart_retrieval.py`

- [ ] **Step 1: Write E2E test**

Create `server/tests/e2e/test_14_smart_retrieval.py`:

```python
"""Smart retrieval: semantic search and related articles."""
import time
import pytest


class TestSemanticSearch:
    """Test semantic search API (mode=semantic)."""

    def test_semantic_search_returns_results(self, auth_headers, api_url):
        """Submit articles, wait for AI analysis, then semantic search."""
        # Submit 2 articles with different topics
        urls = [
            "https://example.com/article-ai-education",
            "https://example.com/article-cooking-recipe",
        ]
        for url in urls:
            resp = pytest.helpers.submit_article(api_url, auth_headers, url)
            assert resp.status_code == 201

        # Wait for AI processing
        time.sleep(5)

        # Semantic search
        resp = pytest.helpers.get(
            f"{api_url}/api/v1/articles/search",
            params={"q": "artificial intelligence", "mode": "semantic"},
            headers=auth_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "data" in data

    def test_semantic_search_degrades_to_keyword(self, auth_headers, api_url):
        """Semantic search should work even if query expansion fails (degradation)."""
        resp = pytest.helpers.get(
            f"{api_url}/api/v1/articles/search",
            params={"q": "test", "mode": "semantic"},
            headers=auth_headers,
        )
        assert resp.status_code == 200

    def test_keyword_search_unchanged(self, auth_headers, api_url):
        """Default mode should still work as before."""
        resp = pytest.helpers.get(
            f"{api_url}/api/v1/articles/search",
            params={"q": "test"},
            headers=auth_headers,
        )
        assert resp.status_code == 200


class TestRelatedArticles:
    """Test GET /articles/{id}/related endpoint."""

    def test_related_articles_endpoint(self, auth_headers, api_url):
        """Related articles endpoint should return (possibly empty) array."""
        # Get any existing article
        resp = pytest.helpers.get(
            f"{api_url}/api/v1/articles",
            headers=auth_headers,
        )
        assert resp.status_code == 200
        articles = resp.json().get("data", [])
        if not articles:
            pytest.skip("No articles to test related")

        article_id = articles[0]["id"]
        resp = pytest.helpers.get(
            f"{api_url}/api/v1/articles/{article_id}/related",
            headers=auth_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "articles" in data
        assert isinstance(data["articles"], list)

    def test_related_articles_nonexistent(self, auth_headers, api_url):
        """Related articles for non-existent ID should return empty array."""
        resp = pytest.helpers.get(
            f"{api_url}/api/v1/articles/00000000-0000-0000-0000-000000000000/related",
            headers=auth_headers,
        )
        assert resp.status_code == 200
        assert resp.json()["articles"] == []
```

> **Note:** Adapt the helper calls (`pytest.helpers.submit_article`, `pytest.helpers.get`) to match the project's actual E2E test helper patterns in `server/tests/e2e/conftest.py` and `server/tests/e2e/helpers/`.

- [ ] **Step 2: Run E2E test**

Run: `cd server && ./scripts/run_e2e.sh`
Expected: All tests pass including the new test_14

- [ ] **Step 3: Commit**

```bash
git add server/tests/e2e/test_14_smart_retrieval.py
git commit -m "test: add E2E tests for semantic search and related articles"
```

---

## Task 12: Integration Test & Final Verification

- [ ] **Step 1: Run all Go unit tests**

Run: `cd server && go test ./... -v`
Expected: ALL PASS

- [ ] **Step 2: Rebuild and restart dev server**

Run: `cd server && docker compose -f docker-compose.local.yml up --build -d`

- [ ] **Step 3: Apply migration**

Run:
```bash
cd server && docker compose -f docker-compose.local.yml exec postgres \
  psql -U folio -d folio -f /dev/stdin < migrations/012_smart_retrieval.up.sql
```

- [ ] **Step 4: Manual smoke test**

1. Submit a new article → verify logs show `semantic_keywords` in AI result
2. Wait for processing → check `article_relations` table has entries
3. Call `GET /api/v1/articles/{id}/related` → verify JSON response
4. Call `GET /api/v1/articles/search?q=test&mode=semantic` → verify response

```bash
# Check semantic_keywords populated
cd server && docker compose -f docker-compose.local.yml exec postgres \
  psql -U folio -d folio -c "SELECT id, semantic_keywords FROM articles WHERE semantic_keywords != '{}' LIMIT 3"

# Check relations populated
cd server && docker compose -f docker-compose.local.yml exec postgres \
  psql -U folio -d folio -c "SELECT * FROM article_relations LIMIT 5"
```

- [ ] **Step 5: Run E2E tests**

Run: `cd server && ./scripts/run_e2e.sh`
Expected: ALL PASS

- [ ] **Step 6: Final commit (if any remaining changes)**

```bash
git add -A && git commit -m "chore: final adjustments for smart retrieval"
```
