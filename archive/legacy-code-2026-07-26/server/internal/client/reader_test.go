package client

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"folio-server/internal/pipeline"
)

func TestReaderClientScrape_Success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"markdown":"# Example","metadata":{"title":"Example"},"duration_ms":12}`)
	}))
	defer srv.Close()

	c := NewReaderClient(srv.URL)
	c.httpClient = srv.Client()

	resp, err := c.Scrape(context.Background(), "https://example.com")
	if err != nil {
		t.Fatalf("Scrape() error = %v", err)
	}
	if resp.Markdown != "# Example" {
		t.Fatalf("Markdown = %q, want %q", resp.Markdown, "# Example")
	}
	if resp.Metadata.Title != "Example" {
		t.Fatalf("Metadata.Title = %q, want %q", resp.Metadata.Title, "Example")
	}
}

func TestReaderClientScrape_ClassifiesBlockedTarget(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = io.WriteString(w, `{"error":"url is not allowed","code":"blocked_target","provider":"reader","retryable":false}`)
	}))
	defer srv.Close()

	c := NewReaderClient(srv.URL)
	c.httpClient = srv.Client()

	_, err := c.Scrape(context.Background(), "http://127.0.0.1")
	if err == nil {
		t.Fatal("Scrape() error = nil, want classified pipeline error")
	}

	var pErr *pipeline.Error
	if !errors.As(err, &pErr) {
		t.Fatalf("error = %T, want *pipeline.Error", err)
	}
	if pErr.Stage != pipeline.StageCrawlReader {
		t.Fatalf("Stage = %q, want %q", pErr.Stage, pipeline.StageCrawlReader)
	}
	if pErr.Provider != pipeline.ProviderReader {
		t.Fatalf("Provider = %q, want %q", pErr.Provider, pipeline.ProviderReader)
	}
	if pErr.Code != pipeline.CodeBlockedTarget {
		t.Fatalf("Code = %q, want %q", pErr.Code, pipeline.CodeBlockedTarget)
	}
	if pErr.Retryable {
		t.Fatal("Retryable = true, want false")
	}
	if pErr.StatusCode != http.StatusBadRequest {
		t.Fatalf("StatusCode = %d, want %d", pErr.StatusCode, http.StatusBadRequest)
	}
}

func TestReaderClientScrape_ClassifiesTimeoutStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusGatewayTimeout)
		_, _ = io.WriteString(w, `{"error":"reader request timed out","code":"timeout","provider":"reader","retryable":true}`)
	}))
	defer srv.Close()

	c := NewReaderClient(srv.URL)
	c.httpClient = srv.Client()

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
	if pErr.StatusCode != http.StatusGatewayTimeout {
		t.Fatalf("StatusCode = %d, want %d", pErr.StatusCode, http.StatusGatewayTimeout)
	}
}

func TestReaderClientScrape_ClassifiesTransportTimeout(t *testing.T) {
	c := NewReaderClient("http://reader.test")
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

func TestReaderClientScrape_ClassifiesInvalidSuccessBody(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"markdown":`)
	}))
	defer srv.Close()

	c := NewReaderClient(srv.URL)
	c.httpClient = srv.Client()

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
	if pErr.Provider != pipeline.ProviderReader {
		t.Fatalf("Provider = %q, want %q", pErr.Provider, pipeline.ProviderReader)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}
