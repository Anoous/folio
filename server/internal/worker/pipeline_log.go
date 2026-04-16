package worker

import (
	"log/slog"
	"net/url"
	"time"

	"folio-server/internal/pipeline"
)

func logPipelineStarted(stage pipeline.Stage, provider pipeline.Provider, taskID, articleID, userID, rawURL string) {
	slog.Info("pipeline_started", pipelineLogAttrs(stage, provider, taskID, articleID, userID, rawURL, 0, nil, "", "")...)
}

func logPipelineSucceeded(stage pipeline.Stage, provider pipeline.Provider, taskID, articleID, userID, rawURL string, duration time.Duration) {
	slog.Info("pipeline_succeeded", pipelineLogAttrs(stage, provider, taskID, articleID, userID, rawURL, duration, nil, "", "")...)
}

func logPipelineFailed(stage pipeline.Stage, provider pipeline.Provider, taskID, articleID, userID, rawURL string, duration time.Duration, err error) {
	slog.Error("pipeline_failed", pipelineLogAttrs(stage, provider, taskID, articleID, userID, rawURL, duration, err, "", "")...)
}

func logPipelineFallbackStarted(stage pipeline.Stage, provider pipeline.Provider, taskID, articleID, userID, rawURL string, fallbackTo pipeline.Provider, err error) {
	slog.Warn("pipeline_fallback_started", pipelineLogAttrs(stage, provider, taskID, articleID, userID, rawURL, 0, err, string(provider), string(fallbackTo))...)
}

func logPipelineFallbackSucceeded(stage pipeline.Stage, provider pipeline.Provider, taskID, articleID, userID, rawURL string, fallbackFrom pipeline.Provider, duration time.Duration) {
	slog.Warn("pipeline_fallback_succeeded", pipelineLogAttrs(stage, provider, taskID, articleID, userID, rawURL, duration, nil, string(fallbackFrom), string(provider))...)
}

func pipelineLogAttrs(stage pipeline.Stage, provider pipeline.Provider, taskID, articleID, userID, rawURL string, duration time.Duration, err error, fallbackFrom, fallbackTo string) []any {
	attrs := []any{
		"pipeline_stage", stage,
		"provider", provider,
		"task_id", taskID,
		"article_id", articleID,
		"user_id", userID,
	}

	if host := pipelineURLHost(rawURL); host != "" {
		attrs = append(attrs, "url_host", host)
	}
	if duration > 0 {
		attrs = append(attrs, "duration_ms", duration.Milliseconds())
	}
	if fallbackFrom != "" {
		attrs = append(attrs, "fallback_from", fallbackFrom)
	}
	if fallbackTo != "" {
		attrs = append(attrs, "fallback_to", fallbackTo)
	}

	if err == nil {
		return attrs
	}

	attrs = append(attrs, "error", err.Error())
	if pErr, ok := clientErr(err); ok {
		attrs = append(attrs, "error_code", pErr.Code, "retryable", pErr.Retryable)
		if pErr.StatusCode > 0 {
			attrs = append(attrs, "status_code", pErr.StatusCode)
		}
		return attrs
	}

	return append(attrs, "error_code", pipeline.CodeInternal, "retryable", false)
}

func pipelineURLHost(rawURL string) string {
	if rawURL == "" {
		return ""
	}
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	return parsed.Hostname()
}
