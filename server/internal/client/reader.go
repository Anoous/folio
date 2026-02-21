package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type ReaderClient struct {
	baseURL    string
	httpClient *http.Client
}

type ScrapeRequest struct {
	URL       string `json:"url"`
	TimeoutMs int    `json:"timeout_ms,omitempty"`
}

type ScrapeResponse struct {
	Markdown   string         `json:"markdown"`
	Metadata   ReaderMetadata `json:"metadata"`
	DurationMs int            `json:"duration_ms"`
}

type ReaderMetadata struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Author      string `json:"author"`
	SiteName    string `json:"siteName"`
	Favicon     string `json:"favicon"`
	OGImage     string `json:"ogImage"`
	Language    string `json:"language"`
	Canonical   string `json:"canonical"`
}

func NewReaderClient(baseURL string) *ReaderClient {
	return &ReaderClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 60 * time.Second,
		},
	}
}

func (c *ReaderClient) Scrape(ctx context.Context, url string) (*ScrapeResponse, error) {
	body, _ := json.Marshal(ScrapeRequest{URL: url, TimeoutMs: 30000})

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/scrape", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("reader request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Error string `json:"error"`
		}
		json.NewDecoder(resp.Body).Decode(&errResp)
		return nil, fmt.Errorf("reader error (status %d): %s", resp.StatusCode, errResp.Error)
	}

	var result ScrapeResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &result, nil
}
