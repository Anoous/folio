package client

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"folio-server/internal/pipeline"
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
	} else {
		// General sites: full optimization headers
		req.Header.Set("X-Return-Format", "markdown")
		req.Header.Set("X-No-Cache", "true")
		req.Header.Set("X-Timeout", "20")
		req.Header.Set("X-Remove-Selector", removeSelectors)
		if c.apiKey != "" {
			req.Header.Set("X-With-Generated-Alt", "true")
		}
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		if isTimeoutError(err) {
			return nil, pipeline.Wrap(
				pipeline.StageCrawlJina,
				pipeline.ProviderJina,
				pipeline.CodeTimeout,
				true,
				http.StatusGatewayTimeout,
				"jina request timed out",
				err,
			)
		}
		return nil, pipeline.Wrap(
			pipeline.StageCrawlJina,
			pipeline.ProviderJina,
			pipeline.CodeNetwork,
			true,
			http.StatusBadGateway,
			"jina request failed",
			err,
		)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, pipeline.Wrap(
			pipeline.StageCrawlJina,
			pipeline.ProviderJina,
			classifyJinaStatus(resp.StatusCode),
			jinaRetryable(resp.StatusCode),
			resp.StatusCode,
			fmt.Sprintf("jina returned status %d", resp.StatusCode),
			nil,
		)
	}

	var jr jinaResponse
	if err := json.NewDecoder(resp.Body).Decode(&jr); err != nil {
		return nil, pipeline.Wrap(
			pipeline.StageCrawlJina,
			pipeline.ProviderJina,
			pipeline.CodeInvalidResponse,
			false,
			http.StatusOK,
			"decode jina response",
			err,
		)
	}

	if jr.Data.Content == "" {
		return nil, pipeline.Wrap(
			pipeline.StageCrawlJina,
			pipeline.ProviderJina,
			pipeline.CodeEmptyContent,
			false,
			http.StatusOK,
			"jina returned empty content",
			nil,
		)
	}

	return &ScrapeResponse{
		Markdown: jr.Data.Content,
		Metadata: ReaderMetadata{
			Title: jr.Data.Title,
		},
	}, nil
}

func classifyJinaStatus(status int) pipeline.Code {
	switch {
	case status == http.StatusTooManyRequests:
		return pipeline.CodeRateLimited
	case status == http.StatusGatewayTimeout:
		return pipeline.CodeTimeout
	case status >= 500:
		return pipeline.CodeUpstream5xx
	case status >= 400:
		return pipeline.CodeUpstream4xx
	default:
		return pipeline.CodeInternal
	}
}

func jinaRetryable(status int) bool {
	return status == http.StatusTooManyRequests || status >= 500
}
