package worker

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/domain"
)

// pushDeviceRepo abstracts the device repository methods used by PushHandler.
type pushDeviceRepo interface {
	GetPushableDevices(ctx context.Context) ([]domain.PushTarget, error)
	UpdateLastPushAt(ctx context.Context, userID string) error
	DeleteByToken(ctx context.Context, token string) error
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
			// Clean up tokens that APNs reports as permanently invalid.
			if isInvalidTokenError(err) {
				if delErr := h.deviceRepo.DeleteByToken(ctx, t.Token); delErr != nil {
					slog.Error("push:echo — delete invalid token failed",
						"error", delErr,
					)
				} else {
					slog.Info("push:echo — removed invalid device token",
						"token_prefix", t.Token[:min(8, len(t.Token))],
					)
				}
			}
			continue // Do NOT update last_push_at on failure
		}

		// Only update last_push_at after a successful send.
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

// isInvalidTokenError returns true when the APNs error indicates the device
// token is permanently invalid and should be removed. APNs returns HTTP 410
// (Gone) for unregistered tokens and HTTP 400 for malformed tokens.
func isInvalidTokenError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "status 410") ||
		strings.Contains(msg, "BadDeviceToken") ||
		strings.Contains(msg, "Unregistered") ||
		strings.Contains(msg, "DeviceTokenNotForTopic")
}
