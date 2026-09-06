package worker

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/hibiken/asynq"
)

type recordingFollowupEnqueuer struct {
	tasks      []*asynq.Task
	failByType map[string]error
}

func (r *recordingFollowupEnqueuer) EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error) {
	r.tasks = append(r.tasks, task)
	if err := r.failByType[task.Type()]; err != nil {
		return nil, err
	}
	return &asynq.TaskInfo{}, nil
}

func TestAIFollowupEnqueuer_EnqueuesEchoAndRelate(t *testing.T) {
	enqueuer := &recordingFollowupEnqueuer{failByType: map[string]error{}}
	followups := aiFollowupEnqueuer{asynqClient: enqueuer}

	followups.enqueue(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
		UserID:    "user-1",
	})

	if len(enqueuer.tasks) != 2 {
		t.Fatalf("enqueued tasks = %d, want 2", len(enqueuer.tasks))
	}
	if enqueuer.tasks[0].Type() != TypeEchoGenerate || enqueuer.tasks[1].Type() != TypeRelateArticle {
		t.Fatalf("task types = %s, %s; want echo then relate", enqueuer.tasks[0].Type(), enqueuer.tasks[1].Type())
	}

	var echoPayload EchoPayload
	if err := json.Unmarshal(enqueuer.tasks[0].Payload(), &echoPayload); err != nil {
		t.Fatalf("unmarshal echo payload: %v", err)
	}
	if echoPayload.ArticleID != "art-1" || echoPayload.UserID != "user-1" || echoPayload.HighlightID != "" {
		t.Fatalf("echo payload = %+v, want article-level echo", echoPayload)
	}

	var relatePayload RelatePayload
	if err := json.Unmarshal(enqueuer.tasks[1].Payload(), &relatePayload); err != nil {
		t.Fatalf("unmarshal relate payload: %v", err)
	}
	if relatePayload.ArticleID != "art-1" || relatePayload.UserID != "user-1" {
		t.Fatalf("relate payload = %+v, want article/user", relatePayload)
	}
}

func TestAIFollowupEnqueuer_RelateStillEnqueuedWhenEchoEnqueueFails(t *testing.T) {
	enqueuer := &recordingFollowupEnqueuer{
		failByType: map[string]error{
			TypeEchoGenerate: errors.New("queue unavailable"),
		},
	}
	followups := aiFollowupEnqueuer{asynqClient: enqueuer}

	followups.enqueue(context.Background(), AIProcessPayload{
		ArticleID: "art-1",
		UserID:    "user-1",
	})

	if len(enqueuer.tasks) != 2 {
		t.Fatalf("enqueued attempts = %d, want echo attempt and relate attempt", len(enqueuer.tasks))
	}
	if enqueuer.tasks[1].Type() != TypeRelateArticle {
		t.Fatalf("second task type = %s, want relate", enqueuer.tasks[1].Type())
	}
}
