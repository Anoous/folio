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

// EscapeILIKE escapes ILIKE wildcard characters in a keyword.
func EscapeILIKE(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `%`, `\%`)
	s = strings.ReplaceAll(s, `_`, `\_`)
	return s
}

// Analyzer abstracts AI analysis so callers can swap implementations (real vs mock).
type Analyzer interface {
	Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error)
	GenerateEchoCards(ctx context.Context, title string, source string, keyPoints []string) ([]EchoQAPair, error)
	GenerateRAGAnswer(ctx context.Context, systemPrompt, userPrompt string) (*RAGResult, error)
	ExpandQuery(ctx context.Context, question string) ([]string, error)
	RerankArticles(ctx context.Context, question string, candidates []RerankCandidate) ([]RerankResult, error)
	SelectRelatedArticles(ctx context.Context, sourceTitle, sourceSummary string, candidates []RerankCandidate) ([]RelatedResult, error)
	GenerateRAGAnswerStream(ctx context.Context, systemPrompt, userPrompt string, tokens chan<- string) (fullAnswer string, err error)
	GenerateFollowups(ctx context.Context, question, answer string) ([]string, error)
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

// RAGResult is the parsed output from the RAG LLM call.
type RAGResult struct {
	Answer              string   `json:"answer"`
	CitedIndices        []int    `json:"cited_indices"`
	FollowupSuggestions []string `json:"followup_suggestions"`
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

// EchoQAPair represents a question/answer pair for echo card generation.
type EchoQAPair struct {
	Question      string `json:"question"`
	Answer        string `json:"answer"`
	SourceContext string `json:"source_context"`
}

// DeepSeekAnalyzer calls the DeepSeek (OpenAI-compatible) API directly.
type DeepSeekAnalyzer struct {
	apiKey           string
	baseURL          string
	httpClient       *http.Client
	streamHTTPClient *http.Client
}

// NewDeepSeekAnalyzer creates a DeepSeekAnalyzer.
// baseURL should be e.g. "https://api.deepseek.com" (no trailing slash).
func NewDeepSeekAnalyzer(apiKey, baseURL string) *DeepSeekAnalyzer {
	return &DeepSeekAnalyzer{
		apiKey:           apiKey,
		baseURL:          strings.TrimRight(baseURL, "/"),
		httpClient:       &http.Client{Timeout: 60 * time.Second},
		streamHTTPClient: &http.Client{},
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

// streamChatRequest is like chatRequest but with Stream field.
type streamChatRequest struct {
	Model       string        `json:"model"`
	Messages    []chatMessage `json:"messages"`
	Temperature float64       `json:"temperature"`
	MaxTokens   int           `json:"max_tokens"`
	Stream      bool          `json:"stream"`
}

// streamDelta is the delta content in a streaming response chunk.
type streamDelta struct {
	Content string `json:"content"`
}

// streamChoice is a single choice in a streaming response chunk.
type streamChoice struct {
	Delta        streamDelta `json:"delta"`
	FinishReason *string     `json:"finish_reason"`
}

// streamChunk is one SSE data payload from the DeepSeek streaming API.
type streamChunk struct {
	Choices []streamChoice `json:"choices"`
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
