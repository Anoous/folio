package client

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

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

// GenerateRAGAnswerStream calls DeepSeek with stream=true and sends each token
// through the tokens channel. Closes tokens when done. Returns the full answer.
func (d *DeepSeekAnalyzer) GenerateRAGAnswerStream(ctx context.Context, systemPrompt, userPrompt string, tokens chan<- string) (string, error) {
	defer close(tokens)

	if d.apiKey == "" {
		mockAnswer := "这是一个模拟回答。基于你的收藏¹，..."
		for _, r := range mockAnswer {
			tokens <- string(r)
		}
		return mockAnswer, nil
	}

	streamCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()

	reqBody := streamChatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature: 0.3,
		MaxTokens:   2048,
		Stream:      true,
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal stream request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(streamCtx, "POST", d.baseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("create stream request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+d.apiKey)

	resp, err := d.streamHTTPClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("stream request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("deepseek stream error: status %d, body: %s", resp.StatusCode, string(respBody))
	}

	var fullAnswer strings.Builder
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		data := strings.TrimPrefix(line, "data: ")
		if data == "[DONE]" {
			break
		}

		var chunk streamChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}
		if len(chunk.Choices) == 0 {
			continue
		}

		content := chunk.Choices[0].Delta.Content
		if content != "" {
			fullAnswer.WriteString(content)
			select {
			case tokens <- content:
			case <-streamCtx.Done():
				return fullAnswer.String(), streamCtx.Err()
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return fullAnswer.String(), fmt.Errorf("read stream: %w", err)
	}

	return fullAnswer.String(), nil
}

// GenerateFollowups calls DeepSeek to generate 2 follow-up question suggestions.
func (d *DeepSeekAnalyzer) GenerateFollowups(ctx context.Context, question, answer string) ([]string, error) {
	if d.apiKey == "" {
		return []string{"还有什么相关的？", "能展开说说吗？"}, nil
	}

	systemPrompt := `基于用户的问题和回答，生成 2 个有深度的跟进问题。
输出 JSON 对象：{"suggestions": ["问题1", "问题2"]}`

	userPrompt := fmt.Sprintf("用户问题：%s\n\n回答：%s", SanitizeField(question), SanitizeField(answer))

	chatReq := chatRequest{
		Model: "deepseek-chat",
		Messages: []chatMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		Temperature:    0.3,
		MaxTokens:      128,
		ResponseFormat: &respFormat{Type: "json_object"},
	}

	respBody, err := d.doRequest(ctx, chatReq)
	if err != nil {
		return nil, fmt.Errorf("generate followups: %w", err)
	}

	var suggestions []string
	if err := json.Unmarshal(respBody, &suggestions); err != nil {
		var wrapper map[string]json.RawMessage
		if err2 := json.Unmarshal(respBody, &wrapper); err2 == nil {
			for _, v := range wrapper {
				if err3 := json.Unmarshal(v, &suggestions); err3 == nil && len(suggestions) > 0 {
					break
				}
			}
		}
	}

	if len(suggestions) == 0 {
		return []string{}, nil
	}
	if len(suggestions) > 2 {
		suggestions = suggestions[:2]
	}
	return suggestions, nil
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
