package worker

import (
	"context"
	"fmt"
)

type crawlAIHandoff struct {
	taskRepo    TaskCrawlTracker
	asynqClient Enqueuer
}

type crawlAIHandoffRequest struct {
	payload             CrawlPayload
	title               string
	markdown            string
	source              string
	author              string
	finishBeforeEnqueue bool
	setFinishedLabel    string
	enqueueLabel        string
}

func (h *CrawlHandler) aiHandoff() crawlAIHandoff {
	return crawlAIHandoff{
		taskRepo:    h.taskRepo,
		asynqClient: h.asynqClient,
	}
}

func (h crawlAIHandoff) enqueue(ctx context.Context, req crawlAIHandoffRequest) error {
	task := NewAIProcessTask(
		req.payload.ArticleID,
		req.payload.TaskID,
		req.payload.UserID,
		req.title,
		req.markdown,
		req.source,
		req.author,
	)

	if req.finishBeforeEnqueue {
		if err := h.taskRepo.SetCrawlFinished(ctx, req.payload.TaskID); err != nil {
			return fmt.Errorf("%s: %w", req.setFinishedLabel, err)
		}
		if _, err := h.asynqClient.EnqueueContext(ctx, task); err != nil {
			return fmt.Errorf("%s: %w", req.enqueueLabel, err)
		}
		return nil
	}

	if _, err := h.asynqClient.EnqueueContext(ctx, task); err != nil {
		return fmt.Errorf("%s: %w", req.enqueueLabel, err)
	}
	if err := h.taskRepo.SetCrawlFinished(ctx, req.payload.TaskID); err != nil {
		return fmt.Errorf("%s: %w", req.setFinishedLabel, err)
	}
	return nil
}
