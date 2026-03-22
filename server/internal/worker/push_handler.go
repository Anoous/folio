package worker

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

// pushDeviceRepo abstracts the device repository methods used by PushHandler.
type pushDeviceRepo interface {
	GetPushableDevices(ctx context.Context) ([]domain.PushTarget, error)
	UpdateLastPushAt(ctx context.Context, userID string) error
}

// PushHandler processes push:echo tasks. Each invocation queries for all
// users eligible for a push notification and sends one per user.
type PushHandler struct {
	deviceRepo pushDeviceRepo
	apnsClient *client.APNSClient
	bundleID   string
}

// NewPushHandler creates a PushHandler.
func NewPushHandler(deviceRepo pushDeviceRepo, apnsClient *client.APNSClient, bundleID string) *PushHandler {
	return &PushHandler{
		deviceRepo: deviceRepo,
		apnsClient: apnsClient,
		bundleID:   bundleID,
	}
}

// ProcessTask handles the push:echo periodic task.
func (h *PushHandler) ProcessTask(ctx context.Context, _ *asynq.Task) error {
	start := time.Now()

	targets, err := h.deviceRepo.GetPushableDevices(ctx)
	if err != nil {
		return fmt.Errorf("get pushable devices: %w", err)
	}

	if len(targets) == 0 {
		slog.Debug("push:echo — no eligible users")
		return nil
	}

	sent := 0
	for _, t := range targets {
		title := "Echo"
		body := fmt.Sprintf("\u2726 %s", t.Question)

		if err := h.apnsClient.SendPush(ctx, t.Token, title, body, h.bundleID); err != nil {
			slog.Error("push:echo — send failed",
				"user_id", t.UserID,
				"error", err,
			)
			continue
		}

		if err := h.deviceRepo.UpdateLastPushAt(ctx, t.UserID); err != nil {
			slog.Error("push:echo — update last_push_at failed",
				"user_id", t.UserID,
				"error", err,
			)
		}
		sent++
	}

	slog.Info("push:echo completed",
		"eligible", len(targets),
		"sent", sent,
		"duration_ms", time.Since(start).Milliseconds(),
	)

	return nil
}
