package client

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"time"

	"folio-server/internal/pipeline"
)

type ReaderClient struct {
	baseURL    string
	httpClient *http.Client
}

type readerErrorResponse struct {
	Error     string `json:"error"`
	Code      string `json:"code"`
	Provider  string `json:"provider"`
	Retryable *bool  `json:"retryable"`
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
	body, _ := json.Marshal(ScrapeRequest{URL: url, TimeoutMs: 55000})

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/scrape", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		if isTimeoutError(err) {
			return nil, pipeline.Wrap(
				pipeline.StageCrawlReader,
				pipeline.ProviderReader,
				pipeline.CodeTimeout,
				true,
				http.StatusGatewayTimeout,
				"reader request timed out",
				err,
			)
		}
		return nil, pipeline.Wrap(
			pipeline.StageCrawlReader,
			pipeline.ProviderReader,
			pipeline.CodeNetwork,
			true,
			http.StatusBadGateway,
			"reader request failed",
			err,
		)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errResp readerErrorResponse
		if err := json.NewDecoder(resp.Body).Decode(&errResp); err != nil {
			return nil, pipeline.Wrap(
				pipeline.StageCrawlReader,
				pipeline.ProviderReader,
				classifyReaderStatus(resp.StatusCode),
				resp.StatusCode >= 500,
				resp.StatusCode,
				"decode reader error response",
				err,
			)
		}
		return nil, pipeline.Wrap(
			pipeline.StageCrawlReader,
			classifyReaderProvider(errResp.Provider),
			classifyReaderCode(errResp.Code, resp.StatusCode),
			retryableOrDefault(errResp.Retryable, resp.StatusCode >= 500),
			resp.StatusCode,
			readerMessageOrDefault(errResp.Error, resp.StatusCode),
			nil,
		)
	}

	var result ScrapeResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, pipeline.Wrap(
			pipeline.StageCrawlReader,
			pipeline.ProviderReader,
			pipeline.CodeInvalidResponse,
			false,
			http.StatusOK,
			"decode reader response",
			err,
		)
	}
	return &result, nil
}

func classifyReaderStatus(status int) pipeline.Code {
	switch {
	case status == http.StatusBadRequest:
		return pipeline.CodeBlockedTarget
	case status == http.StatusUnprocessableEntity:
		return pipeline.CodeEmptyContent
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

func classifyReaderCode(code string, status int) pipeline.Code {
	switch code {
	case string(pipeline.CodeInvalidRequest):
		return pipeline.CodeInvalidRequest
	case string(pipeline.CodeBlockedTarget):
		return pipeline.CodeBlockedTarget
	case string(pipeline.CodeTimeout):
		return pipeline.CodeTimeout
	case string(pipeline.CodeNetwork):
		return pipeline.CodeNetwork
	case string(pipeline.CodeRateLimited):
		return pipeline.CodeRateLimited
	case string(pipeline.CodeUpstream4xx):
		return pipeline.CodeUpstream4xx
	case string(pipeline.CodeUpstream5xx):
		return pipeline.CodeUpstream5xx
	case string(pipeline.CodeEmptyContent):
		return pipeline.CodeEmptyContent
	case string(pipeline.CodeInvalidResponse):
		return pipeline.CodeInvalidResponse
	case string(pipeline.CodeInternal):
		return pipeline.CodeInternal
	default:
		return classifyReaderStatus(status)
	}
}

func classifyReaderProvider(provider string) pipeline.Provider {
	switch provider {
	case string(pipeline.ProviderReader):
		return pipeline.ProviderReader
	case string(pipeline.ProviderJina):
		return pipeline.ProviderJina
	case string(pipeline.ProviderDeepSeek):
		return pipeline.ProviderDeepSeek
	default:
		return pipeline.ProviderReader
	}
}

func retryableOrDefault(value *bool, fallback bool) bool {
	if value != nil {
		return *value
	}
	return fallback
}

func readerMessageOrDefault(message string, status int) string {
	if message != "" {
		return message
	}

	switch classifyReaderStatus(status) {
	case pipeline.CodeBlockedTarget:
		return "reader blocked target URL"
	case pipeline.CodeEmptyContent:
		return "reader returned empty content"
	case pipeline.CodeTimeout:
		return "reader request timed out"
	default:
		return fmt.Sprintf("reader returned status %d", status)
	}
}

func isTimeoutError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	return os.IsTimeout(err)
}
