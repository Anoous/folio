package worker

import (
	"time"

	"folio-server/internal/domain"
	"folio-server/internal/pipeline"
)

func buildTaskFailure(err error, duration time.Duration) domain.TaskFailure {
	failure := domain.TaskFailure{
		Message: err.Error(),
	}

	durationMs := duration.Milliseconds()
	failure.DurationMs = &durationMs

	if pErr, ok := pipeline.As(err); ok {
		stage := string(pErr.Stage)
		code := string(pErr.Code)
		provider := string(pErr.Provider)
		retryable := pErr.Retryable

		failure.Stage = &stage
		failure.Code = &code
		failure.Provider = &provider
		failure.Retryable = &retryable
	}

	return failure
}
