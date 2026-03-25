package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// SanitizeField removes injection markers from a single field.
// Shared across packages that build LLM prompts.
func SanitizeField(s string) string {
	s = strings.ReplaceAll(s, "```", "")
	s = strings.ReplaceAll(s, "system:", "")
	s = strings.ReplaceAll(s, "assistant:", "")
	s = strings.ReplaceAll(s, "user:", "")
	return s
}

// RAGResult is the parsed output from the RAG LLM call.
type RAGResult struct {
	Answer              string   `json:"answer"`
	CitedIndices        []int    `json:"cited_indices"`
	FollowupSuggestions []string `json:"followup_suggestions"`
}

// Analyzer abstracts AI analysis so callers can swap implementations (real vs mock).
type Analyzer interface {
	Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error)
	GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error)
	GenerateRAGAnswer(ctx context.Context, systemPrompt, userPrompt string) (*RAGResult, error)
	ExpandQuery(ctx context.Context, question string) ([]string, error)
	RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error)
	SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error)
	// IsRealAI reports whether this analyzer calls a real LLM (vs a mock).
	IsRealAI() bool
}

// AnalyzeRequest is the input for AI article analysis.
type AnalyzeRequest struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Source  string `json:"source"`
	Author  string `json:"author"`
}

// AnalyzeResponse is the output from AI article analysis.
type AnalyzeResponse struct {
	Category         string   `json:"category"`
	CategoryName     string   `json:"category_name"`
	Confidence       float64  `json:"confidence"`
	Tags             []string `json:"tags"`
	Summary          string   `json:"summary"`
	KeyPoints        []string `json:"key_points"`
	Language         string   `json:"language"`
	SemanticKeywords []string `json:"semantic_keywords"`
}

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

// categoryEntry holds a slug→name pair for the 9 predefined categories.
type categoryEntry struct {
	Slug string
	Name string
}

var categoryList = []categoryEntry{
	{"tech", "Technology"}, {"business", "Business"}, {"science", "Science"},
	{"culture", "Culture"}, {"lifestyle", "Lifestyle"}, {"news", "News"},
	{"education", "Education"}, {"design", "Design"}, {"other", "Other"},
}

var validCategories = func() map[string]string {
	m := make(map[string]string, len(categoryList))
	for _, c := range categoryList {
		m[c.Slug] = c.Name
	}
	return m
}()

// DeepSeekAnalyzer calls the DeepSeek (OpenAI-compatible) API directly.
type DeepSeekAnalyzer struct {
	apiKey     string
	baseURL    string
	httpClient *http.Client
}

// NewDeepSeekAnalyzer creates a DeepSeekAnalyzer.
// baseURL should be e.g. "https://api.deepseek.com" (no trailing slash).
func NewDeepSeekAnalyzer(apiKey, baseURL string) *DeepSeekAnalyzer {
	return &DeepSeekAnalyzer{
		apiKey:     apiKey,
		baseURL:    strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{Timeout: 60 * time.Second},
	}
}

func (d *DeepSeekAnalyzer) IsRealAI() bool { return true }

// --- OpenAI-compatible request/response types ---

type chatRequest struct {
	Model          string        `json:"model"`
	Messages       []chatMessage `json:"messages"`
	Temperature    float64       `json:"temperature"`
	MaxTokens      int           `json:"max_tokens"`
	ResponseFormat *respFormat   `json:"response_format,omitempty"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type respFormat struct {
	Type string `json:"type"`
}

type chatResponse struct {
	Choices []chatChoice `json:"choices"`
	Error   *chatError   `json:"error,omitempty"`
}

type chatChoice struct {
	Message chatMessage `json:"message"`
}

type chatError struct {
	Message string `json:"message"`
	Type    string `json:"type"`
}

// Analyze sends the article to DeepSeek and returns the structured analysis.
func (d *DeepSeekAnalyzer) Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error) {
	systemPrompt := buildSystemPrompt()
	userPrompt := buildUserPrompt(req.Title, req.Content, req.Source, req.Author)

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0.3,
		MaxTokens:      1024,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("analyze: %w", err)
	}

	var result AnalyzeResponse
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("decode analysis json: %w (raw: %s)", err, string(respBody))
	}

	validateResponse(&result)
	return &result, nil
}

// buildSystemPrompt constructs the system prompt with the category list.
func buildSystemPrompt() string {
	var catLines strings.Builder
	for _, c := range categoryList {
		fmt.Fprintf(&catLines, "   - %s (%s)\n", c.Slug, c.Name)
	}

	return fmt.Sprintf(`你是一个文章分析助手。给定一篇文章的标题、正文、来源和作者，你需要完成以下任务：

1. **分类**：从以下 9 个类别中选择最合适的一个：
%s
2. **标签**：提取 3-5 个关键标签（关键词），用于描述文章主题。

3. **语言检测**：判断文章主要语言，输出 "zh"（中文）或 "en"（英文）。

4. **置信度**：给出你对分类结果的置信度（0.0-1.0）。

5. **summary**：一句核心洞察（不是概括全文，而是文章中最令人惊讶、最反直觉、或最有价值的单一发现），用陈述句，像 pull quote 一样有冲击力。不超过 40 字。

6. **key_points**：3-5 个支撑核心洞察的要点，每条不超过 15 字，是具体论据而非泛泛概括。

7. **semantic_keywords**：生成 10-15 个语义关键词（全部小写），用于后续检索匹配。包含核心概念的中英文双语表达、同义词、上下位概念。

**重要规则**：
- 摘要和标签的语言应跟随文章本身的语言（中文文章用中文，英文文章用英文）。
- category 必须是上述 9 个 slug 之一，不得自创。
- 直接输出 JSON，不要用 markdown code fence 包裹。

输出格式（严格 JSON）：
{
  "category": "<slug>",
  "category_name": "<人类可读分类名>",
  "confidence": <0.0-1.0>,
  "tags": ["tag1", "tag2", "tag3"],
  "summary": "<摘要>",
  "key_points": ["要点1", "要点2", "要点3"],
  "language": "zh 或 en",
  "semantic_keywords": ["keyword1", "关键词2", ...]
}`, catLines.String())
}

// buildUserPrompt constructs the user prompt, sanitizing inputs and truncating
// content to 12000 runes.
func buildUserPrompt(title, content, source, author string) string {
	title = SanitizeField(title)
	content = SanitizeField(content)
	source = SanitizeField(source)
	author = SanitizeField(author)

	const maxContentRunes = 12000
	runes := []rune(content)
	if len(runes) > maxContentRunes {
		content = string(runes[:maxContentRunes]) + "\n...(内容已截断)"
	}

	return fmt.Sprintf("标题：%s\n来源：%s\n作者：%s\n\n正文：\n%s", title, source, author, content)
}

// validateResponse fixes invalid LLM outputs in place.
func validateResponse(resp *AnalyzeResponse) {
	// Validate category
	if name, ok := validCategories[resp.Category]; ok {
		resp.CategoryName = name
	} else {
		resp.Category = "other"
		resp.CategoryName = "Other"
		if resp.Confidence > 0.5 {
			resp.Confidence = 0.5
		}
	}

	// Clamp confidence to [0, 1]
	if resp.Confidence < 0 {
		resp.Confidence = 0
	}
	if resp.Confidence > 1.0 {
		resp.Confidence = 1.0
	}

	// Validate tags
	if len(resp.Tags) == 0 {
		resp.Tags = []string{"untagged"}
	}
	if len(resp.Tags) > 5 {
		resp.Tags = resp.Tags[:5]
	}

	// Validate key_points
	if len(resp.KeyPoints) == 0 {
		resp.KeyPoints = []string{"N/A"}
	}
	if len(resp.KeyPoints) > 5 {
		resp.KeyPoints = resp.KeyPoints[:5]
	}

	// Validate language
	if resp.Language != "zh" && resp.Language != "en" {
		resp.Language = "en"
	}

	// Lowercase all semantic keywords
	for i, kw := range resp.SemanticKeywords {
		resp.SemanticKeywords[i] = strings.ToLower(kw)
	}
	if resp.SemanticKeywords == nil {
		resp.SemanticKeywords = []string{}
	}
}

// EchoQAPair represents a question/answer pair for echo card generation.
type EchoQAPair struct {
	Question      string `json:"question"`
	Answer        string `json:"answer"`
	SourceContext string `json:"source_context"`
}

// GenerateEchoCards calls DeepSeek to generate 1-2 echo Q&A pairs from article key points.
// If the analyzer has no API key, it returns a deterministic fallback using key_points directly.
func (d *DeepSeekAnalyzer) GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error) {
	if d.apiKey == "" {
		return generateMockEchoCards(title, source, keyPoints), nil
	}

	systemPrompt := `你是一个回忆测试生成器。基于文章要点，生成 1-2 个回忆测试问答对。

要求：
1. question：用"还记得……吗？"的口吻，引导用户主动回忆，不超过 30 字
2. answer：简洁的答案，可以是原文引用或精炼表述，不超过 50 字
3. source_context：格式为 "来自《文章标题》· 来源名"

输出 JSON 数组，不要 markdown 代码块：[{"question":"...", "answer":"...", "source_context":"..."}]`

	var pointsBuilder strings.Builder
	for _, kp := range keyPoints {
		fmt.Fprintf(&pointsBuilder, "- %s\n", kp)
	}

	userPrompt := fmt.Sprintf("文章标题：%s\n来源：%s\n要点：\n%s", SanitizeField(title), SanitizeField(source), pointsBuilder.String())

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0.3,
		MaxTokens:      512,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("generate echo cards: %w", err)
	}

	content := string(respBody)

	// Try parsing as array directly
	var pairs []EchoQAPair
	if err := json.Unmarshal([]byte(content), &pairs); err == nil && len(pairs) > 0 {
		return pairs, nil
	}

	// Try parsing as object with array field (json_object mode may wrap)
	var wrapper map[string]json.RawMessage
	if err := json.Unmarshal([]byte(content), &wrapper); err == nil {
		for _, v := range wrapper {
			if err := json.Unmarshal(v, &pairs); err == nil && len(pairs) > 0 {
				return pairs, nil
			}
		}
	}

	// Fallback: return a template card using the first key point
	return echoFallbackCards(title, source, keyPoints), nil
}

// generateMockEchoCards returns deterministic echo cards without calling any API.
func generateMockEchoCards(title, source string, keyPoints []string) []EchoQAPair {
	return echoFallbackCards(title, source, keyPoints)
}

// GenerateRAGAnswer calls DeepSeek to produce a RAG answer from a system + user prompt.
// Uses a 30-second timeout. If no API key is configured, returns a mock fallback.
func (d *DeepSeekAnalyzer) GenerateRAGAnswer(ctx context.Context, systemPrompt, userPrompt string) (*RAGResult, error) {
	if d.apiKey == "" {
		return &RAGResult{
			Answer:              "这是一个模拟回答。基于你的收藏¹，...",
			CitedIndices:        []int{1},
			FollowupSuggestions: []string{"还有什么相关的？"},
		}, nil
	}

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0.3,
		MaxTokens:      2048,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	// Use a 30-second timeout for RAG calls.
	ragCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	respBody, err := d.doRequest(ragCtx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("rag: %w", err)
	}

	var result RAGResult
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("decode rag json: %w (raw: %s)", err, string(respBody))
	}

	// Ensure slices are non-nil.
	if result.CitedIndices == nil {
		result.CitedIndices = []int{}
	}
	if result.FollowupSuggestions == nil {
		result.FollowupSuggestions = []string{}
	}

	return &result, nil
}

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

// ExpandQuery generates 10-15 search keywords for a user question via LLM.
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

	userPrompt := fmt.Sprintf("用户问题：%s", SanitizeField(question))

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

// RerankArticles asks the LLM to judge relevance of candidates to a question.
func (d *DeepSeekAnalyzer) RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "用户问题：%s\n\n以下是候选文章列表。判断每篇与用户问题的相关程度，返回最相关的 Top 10。\n\n候选文章：\n", SanitizeField(question))
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

// SelectRelatedArticles asks the LLM to pick the most related articles to a source article.
func (d *DeepSeekAnalyzer) SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "本文：《%s》\n摘要：%s\n\n候选文章：\n", SanitizeField(sourceTitle), SanitizeField(sourceSummary))
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

// echoFallbackCards builds 1-2 template-based echo cards from key points.
func echoFallbackCards(title, source string, keyPoints []string) []EchoQAPair {
	if len(keyPoints) == 0 {
		return nil
	}
	sourceCtx := fmt.Sprintf("来自《%s》· %s", title, source)

	pairs := []EchoQAPair{
		{
			Question:      "还记得这篇文章的核心观点吗？",
			Answer:        keyPoints[0],
			SourceContext: sourceCtx,
		},
	}
	if len(keyPoints) >= 2 {
		pairs = append(pairs, EchoQAPair{
			Question:      "还记得这篇文章的关键论据吗？",
			Answer:        keyPoints[1],
			SourceContext: sourceCtx,
		})
	}
	return pairs
}
