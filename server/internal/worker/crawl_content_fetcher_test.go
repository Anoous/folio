package worker

import (
	"context"
	"errors"
	"testing"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/pipeline"
)

func TestCrawlContentFetcher_ReaderSuccessSkipsJina(t *testing.T) {
	readerResponse := &client.ScrapeResponse{
		Markdown: "# Reader",
		Metadata: client.ReaderMetadata{Title: "Reader Title"},
	}
	jinaCalled := false
	fetcher := crawlContentFetcher{
		readerClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				return readerResponse, nil
			},
		},
		jinaClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				jinaCalled = true
				return nil, nil
			},
		},
	}

	result, err := fetcher.fetch(context.Background(), crawlFetchTestPayload(), time.Now())
	if err != nil {
		t.Fatalf("fetch() error = %v", err)
	}
	if result.response != readerResponse {
		t.Fatalf("response = %+v, want reader response", result.response)
	}
	if result.stage != pipeline.StageCrawlReader || result.provider != pipeline.ProviderReader {
		t.Fatalf("stage/provider = %s/%s, want reader", result.stage, result.provider)
	}
	if jinaCalled {
		t.Fatal("jina should not be called after reader success")
	}
}

func TestCrawlContentFetcher_ReaderFailureUsesJinaResult(t *testing.T) {
	jinaResponse := &client.ScrapeResponse{
		Markdown: "# Jina",
		Metadata: client.ReaderMetadata{Title: "Jina Title"},
	}
	fetcher := crawlContentFetcher{
		readerClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				return nil, errors.New("reader timeout")
			},
		},
		jinaClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				return jinaResponse, nil
			},
		},
	}

	result, err := fetcher.fetch(context.Background(), crawlFetchTestPayload(), time.Now())
	if err != nil {
		t.Fatalf("fetch() error = %v", err)
	}
	if result.response != jinaResponse {
		t.Fatalf("response = %+v, want jina response", result.response)
	}
	if result.stage != pipeline.StageCrawlJina || result.provider != pipeline.ProviderJina {
		t.Fatalf("stage/provider = %s/%s, want jina", result.stage, result.provider)
	}
}

func TestCrawlContentFetcher_PreservesReaderPipelineFailureWhenJinaFailsInternally(t *testing.T) {
	readerErr := pipeline.Wrap(
		pipeline.StageCrawlReader,
		pipeline.ProviderReader,
		pipeline.CodeBlockedTarget,
		false,
		403,
		"reader blocked target URL",
		errors.New("blocked"),
	)
	fetcher := crawlContentFetcher{
		readerClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				return nil, readerErr
			},
		},
		jinaClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				return nil, errors.New("jina adapter crashed")
			},
		},
	}

	result, err := fetcher.fetch(context.Background(), crawlFetchTestPayload(), time.Now())
	if err != readerErr {
		t.Fatalf("fetch() error = %v, want original reader pipeline error", err)
	}
	if result.stage != pipeline.StageCrawlReader || result.provider != pipeline.ProviderReader {
		t.Fatalf("stage/provider = %s/%s, want preserved reader failure", result.stage, result.provider)
	}
}

func TestCrawlContentFetcher_UsesJinaPipelineFailureWhenAvailable(t *testing.T) {
	readerErr := pipeline.Wrap(
		pipeline.StageCrawlReader,
		pipeline.ProviderReader,
		pipeline.CodeNetwork,
		true,
		502,
		"reader request failed",
		errors.New("network"),
	)
	jinaErr := pipeline.Wrap(
		pipeline.StageCrawlJina,
		pipeline.ProviderJina,
		pipeline.CodeEmptyContent,
		false,
		200,
		"jina returned empty content",
		errors.New("empty"),
	)
	fetcher := crawlContentFetcher{
		readerClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				return nil, readerErr
			},
		},
		jinaClient: &mockScraper{
			scrapeFn: func(ctx context.Context, url string) (*client.ScrapeResponse, error) {
				return nil, jinaErr
			},
		},
	}

	result, err := fetcher.fetch(context.Background(), crawlFetchTestPayload(), time.Now())
	if err != jinaErr {
		t.Fatalf("fetch() error = %v, want jina pipeline error", err)
	}
	if result.stage != pipeline.StageCrawlJina || result.provider != pipeline.ProviderJina {
		t.Fatalf("stage/provider = %s/%s, want jina failure", result.stage, result.provider)
	}
}

func crawlFetchTestPayload() CrawlPayload {
	return CrawlPayload{
		ArticleID: "art-1",
		TaskID:    "task-1",
		URL:       "https://example.com/article",
		UserID:    "user-1",
	}
}
