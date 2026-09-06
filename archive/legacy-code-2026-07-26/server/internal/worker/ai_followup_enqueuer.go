package worker

import (
	"context"
	"log/slog"
)

type aiFollowupEnqueuer struct {
	asynqClient Enqueuer
}

func (h *AIHandler) followupEnqueuer() aiFollowupEnqueuer {
	return aiFollowupEnqueuer{asynqClient: h.asynqClient}
}

func (e aiFollowupEnqueuer) enqueue(ctx context.Context, p AIProcessPayload) {
	echoTask, err := NewEchoTask(p.ArticleID, p.UserID, "")
	if err == nil {
		if _, err := e.asynqClient.EnqueueContext(ctx, echoTask); err != nil {
			slog.Error("[ECHO] failed to enqueue for article",
				"article_id", p.ArticleID,
				"error", err,
			)
		}
	}

	relateTask := NewRelateTask(p.ArticleID, p.UserID)
	if _, err := e.asynqClient.EnqueueContext(ctx, relateTask); err != nil {
		slog.Error("[RELATE] failed to enqueue for article",
			"article_id", p.ArticleID,
			"error", err,
		)
	}
}
