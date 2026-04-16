package worker

import (
	"folio-server/internal/pipeline"
)

func clientErr(err error) (*pipeline.Error, bool) {
	return pipeline.As(err)
}

func ensurePipelineErr(stage pipeline.Stage, provider pipeline.Provider, retryable bool, message string, err error) error {
	if err == nil {
		return nil
	}
	if pErr, ok := clientErr(err); ok {
		return pErr
	}
	return pipeline.Wrap(stage, provider, pipeline.CodeInternal, retryable, 0, message, err)
}
