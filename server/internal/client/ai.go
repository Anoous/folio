package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type AIClient struct {
	baseURL    string
	httpClient *http.Client
}

type AnalyzeRequest struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Source  string `json:"source"`
	Author  string `json:"author"`
}

type AnalyzeResponse struct {
	Category     string   `json:"category"`
	CategoryName string   `json:"category_name"`
	Confidence   float64  `json:"confidence"`
	Tags         []string `json:"tags"`
	Summary      string   `json:"summary"`
	KeyPoints    []string `json:"key_points"`
	Language     string   `json:"language"`
}

func NewAIClient(baseURL string) *AIClient {
	return &AIClient{
		baseURL:    baseURL,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

func (c *AIClient) Analyze(ctx context.Context, req AnalyzeRequest) (*AnalyzeResponse, error) {
	body, _ := json.Marshal(req)

	httpReq, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/analyze", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("ai request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("ai service error: status %d", resp.StatusCode)
	}

	var result AnalyzeResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}
