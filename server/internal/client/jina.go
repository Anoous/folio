package client

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

type JinaClient struct {
	httpClient *http.Client
	apiKey     string
}

type jinaResponse struct {
	Code   int      `json:"code"`
	Status int      `json:"status"`
	Data   jinaData `json:"data"`
}

type jinaData struct {
	Title   string `json:"title"`
	URL     string `json:"url"`
	Content string `json:"content"`
}

func NewJinaClient(apiKey string) *JinaClient {
	return &JinaClient{
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		apiKey: apiKey,
	}
}

// needsBrowserRendering returns true for JS-heavy sites that require
// cf-browser-rendering engine (needs API key).
func needsBrowserRendering(url string) bool {
	return strings.Contains(url, "x.com/") || strings.Contains(url, "twitter.com/")
}

// Common noise selectors to remove from extracted content.
const removeSelectors = "nav, footer, header, .cookie-banner, .ad, .ads, .advertisement, " +
	".sidebar, .social-share, .related-posts, .comments, #comments, .newsletter-signup"

func (c *JinaClient) Scrape(ctx context.Context, url string) (*ScrapeResponse, error) {
	start := time.Now()

	req, err := http.NewRequestWithContext(ctx, "GET", "https://r.jina.ai/"+url, nil)
	if err != nil {
		return nil, fmt.Errorf("create jina request: %w", err)
	}

	// --- Common headers ---
	req.Header.Set("Accept", "application/json")

	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}

	// --- Site-specific headers ---
	if needsBrowserRendering(url) && c.apiKey != "" {
		// X/Twitter: minimal headers to avoid anti-bot detection
		req.Header.Set("X-Engine", "cf-browser-rendering")
		req.Header.Set("X-Wait-For-Selector", "article[data-testid='tweet']")
		req.Header.Set("X-Timeout", "20")
		slog.Debug("jina scrape started", "url", url, "engine", "cf-browser-rendering")
	} else {
		// General sites: full optimization headers
		req.Header.Set("X-Return-Format", "markdown")
		req.Header.Set("X-No-Cache", "true")
		req.Header.Set("X-Timeout", "20")
		req.Header.Set("X-Remove-Selector", removeSelectors)
		if c.apiKey != "" {
			req.Header.Set("X-With-Generated-Alt", "true")
		}
		slog.Debug("jina scrape started", "url", url, "engine", "default")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		slog.Warn("jina scrape request failed", "url", url, "error", err, "duration_ms", time.Since(start).Milliseconds())
		return nil, fmt.Errorf("jina request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		slog.Warn("jina scrape non-200", "url", url, "status", resp.StatusCode, "duration_ms", time.Since(start).Milliseconds())
		return nil, fmt.Errorf("jina error (status %d)", resp.StatusCode)
	}

	var jr jinaResponse
	if err := json.NewDecoder(resp.Body).Decode(&jr); err != nil {
		return nil, fmt.Errorf("decode jina response: %w", err)
	}

	if jr.Data.Content == "" {
		slog.Warn("jina scrape returned empty content", "url", url, "duration_ms", time.Since(start).Milliseconds())
		return nil, fmt.Errorf("jina returned empty content")
	}

	contentLen := len(jr.Data.Content)
	slog.Info("jina scrape succeeded", "url", url, "title", jr.Data.Title, "content_len", contentLen, "duration_ms", time.Since(start).Milliseconds())

	return &ScrapeResponse{
		Markdown: jr.Data.Content,
		Metadata: ReaderMetadata{
			Title: jr.Data.Title,
		},
	}, nil
}
