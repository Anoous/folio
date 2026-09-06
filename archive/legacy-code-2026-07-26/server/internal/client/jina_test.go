package client

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"

	"folio-server/internal/pipeline"
)

func TestJinaClientScrape_ClassifiesRateLimited(t *testing.T) {
	c := NewJinaClient("")
	c.httpClient = &http.Client{
		Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusTooManyRequests,
				Body:       io.NopCloser(strings.NewReader("")),
				Header:     make(http.Header),
				Request:    r,
			}, nil
		}),
	}

	_, err := c.Scrape(context.Background(), "https://example.com")
	if err == nil {
		t.Fatal("Scrape() error = nil, want classified pipeline error")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Stage != pipeline.StageCrawlJina {
		t.Fatalf("Stage = %q, want %q", pErr.Stage, pipeline.StageCrawlJina)
	}
	if pErr.Provider != pipeline.ProviderJina {
		t.Fatalf("Provider = %q, want %q", pErr.Provider, pipeline.ProviderJina)
	}
	if pErr.Code != pipeline.CodeRateLimited {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeRateLimited)
	}
	if !pErr.Retryable {
		t.Fatal("Retryable = false, want true")
	}
	if pErr.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("StatusCode = %d, want %d", pErr.StatusCode, http.StatusTooManyRequests)
	}
}

func TestJinaClientScrape_ClassifiesTransportTimeout(t *testing.T) {
	c := NewJinaClient("")
	c.httpClient = &http.Client{
		Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			return nil, context.DeadlineExceeded
		}),
	}

	_, err := c.Scrape(context.Background(), "https://example.com")
	if err == nil {
		t.Fatal("Scrape() error = nil, want timeout classification")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Code != pipeline.CodeTimeout {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeTimeout)
	}
	if !pErr.Retryable {
		t.Fatal("Retryable = false, want true")
	}
}

func TestJinaClientScrape_ClassifiesInvalidResponse(t *testing.T) {
	c := NewJinaClient("")
	c.httpClient = &http.Client{
		Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(strings.NewReader(`{"data":`)),
				Header:     make(http.Header),
				Request:    r,
			}, nil
		}),
	}

	_, err := c.Scrape(context.Background(), "https://example.com")
	if err == nil {
		t.Fatal("Scrape() error = nil, want invalid response classification")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Code != pipeline.CodeInvalidResponse {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeInvalidResponse)
	}
}

func TestJinaClientScrape_ClassifiesEmptyContent(t *testing.T) {
	c := NewJinaClient("")
	c.httpClient = &http.Client{
		Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       io.NopCloser(strings.NewReader(`{"data":{"title":"Example","content":""}}`)),
				Header:     make(http.Header),
				Request:    r,
			}, nil
		}),
	}

	_, err := c.Scrape(context.Background(), "https://example.com")
	if err == nil {
		t.Fatal("Scrape() error = nil, want empty content classification")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Code != pipeline.CodeEmptyContent {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeEmptyContent)
	}
	if pErr.Retryable {
		t.Fatal("Retryable = true, want false")
	}
}
