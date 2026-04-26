package worker

import (
	"context"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/pipeline"
)

type crawlContentFetcher struct {
	readerClient scraper
	jinaClient   scraper
}

type crawlFetchResult struct {
	response *client.ScrapeResponse
	stage    pipeline.Stage
	provider pipeline.Provider
}

func (h *CrawlHandler) contentFetcher() crawlContentFetcher {
	return crawlContentFetcher{
		readerClient: h.readerClient,
		jinaClient:   h.jinaClient,
	}
}

func (f crawlContentFetcher) fetch(ctx context.Context, p CrawlPayload, start time.Time) (crawlFetchResult, error) {
	stage := pipeline.StageCrawlReader
	provider := pipeline.ProviderReader
	logPipelineStarted(stage, provider, p.TaskID, p.ArticleID, p.UserID, p.URL)

	response, err := f.readerClient.Scrape(ctx, p.URL)
	if err == nil {
		return crawlFetchResult{
			response: response,
			stage:    stage,
			provider: provider,
		}, nil
	}

	readerErr := ensurePipelineErr(stage, provider, true, "reader scrape failed", err)
	logPipelineFallbackStarted(stage, provider, p.TaskID, p.ArticleID, p.UserID, p.URL, pipeline.ProviderJina, readerErr)

	stage = pipeline.StageCrawlJina
	provider = pipeline.ProviderJina
	response, err = f.jinaClient.Scrape(ctx, p.URL)
	if err == nil {
		logPipelineFallbackSucceeded(stage, provider, p.TaskID, p.ArticleID, p.UserID, p.URL, pipeline.ProviderReader, time.Since(start))
		return crawlFetchResult{
			response: response,
			stage:    stage,
			provider: provider,
		}, nil
	}

	failureErr := ensurePipelineErr(stage, provider, true, "jina scrape failed", err)
	if shouldPreserveReaderFailure(readerErr, err) {
		failureErr = readerErr
		stage = pipeline.StageCrawlReader
		provider = pipeline.ProviderReader
	}

	return crawlFetchResult{
		stage:    stage,
		provider: provider,
	}, failureErr
}

func shouldPreserveReaderFailure(readerErr error, fallbackErr error) bool {
	if _, ok := clientErr(readerErr); !ok {
		return false
	}
	if _, fallbackOK := clientErr(fallbackErr); fallbackOK {
		return false
	}
	return true
}
