package service

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"folio-server/internal/client"
	"folio-server/internal/domain"
	"folio-server/internal/repository"
)

// Valid product IDs for Folio Pro subscriptions.
var validProductIDs = map[string]bool{
	"com.folio.app.pro.yearly":  true,
	"com.folio.app.pro.monthly": true,
}

// SubscriptionService handles App Store subscription verification and webhook
// processing.
type SubscriptionService struct {
	appleClient client.AppleStoreClient
	userRepo    *repository.UserRepo
	bundleID    string
}

// NewSubscriptionService creates a SubscriptionService.
func NewSubscriptionService(appleClient client.AppleStoreClient, userRepo *repository.UserRepo, bundleID string) *SubscriptionService {
	return &SubscriptionService{
		appleClient: appleClient,
		userRepo:    userRepo,
		bundleID:    bundleID,
	}
}

// VerifyAndActivateResult is returned on successful subscription activation.
type VerifyAndActivateResult struct {
	Subscription string     `json:"subscription"`
	ExpiresAt    *time.Time `json:"expires_at,omitempty"`
}

// VerifyAndActivate verifies a transaction with Apple and activates the user's
// subscription.
//
//  1. Call Apple API to verify the transactionID
//  2. Validate bundleID (skip for mock)
//  3. Validate productID is a known Folio Pro product
//  4. Check expiresDate is in the future
//  5. Update user: subscription = "pro", expiry, original_transaction_id
func (s *SubscriptionService) VerifyAndActivate(ctx context.Context, userID, transactionID, productID string) (*VerifyAndActivateResult, error) {
	txnInfo, err := s.appleClient.VerifyTransaction(ctx, transactionID)
	if err != nil {
		return nil, fmt.Errorf("verify transaction: %w", err)
	}

	// Validate bundle ID (real client returns actual bundleID; mock returns
	// the configured one, so this check passes for both).
	if s.bundleID != "" && txnInfo.BundleID != "" && txnInfo.BundleID != s.bundleID {
		slog.Warn("subscription: bundle ID mismatch",
			"expected", s.bundleID, "got", txnInfo.BundleID)
		return nil, ErrInvalidBundleID
	}

	// Validate product ID.
	if !validProductIDs[txnInfo.ProductID] {
		slog.Warn("subscription: invalid product ID",
			"product_id", txnInfo.ProductID, "user_id", userID)
		return nil, ErrInvalidProduct
	}

	// Check expiry.
	if txnInfo.ExpiresDate == nil || txnInfo.ExpiresDate.Before(time.Now()) {
		slog.Warn("subscription: transaction already expired",
			"expires", txnInfo.ExpiresDate, "user_id", userID)
		return nil, ErrSubscriptionExpired
	}

	// Activate.
	origTxnID := txnInfo.OriginalTransactionID
	if err := s.userRepo.UpdateSubscription(ctx, userID,
		domain.SubscriptionPro, txnInfo.ExpiresDate, &origTxnID); err != nil {
		return nil, fmt.Errorf("activate subscription: %w", err)
	}

	slog.Info("subscription activated",
		"user_id", userID,
		"product_id", txnInfo.ProductID,
		"expires_at", txnInfo.ExpiresDate,
		"original_txn_id", origTxnID)

	return &VerifyAndActivateResult{
		Subscription: string(domain.SubscriptionPro),
		ExpiresAt:    txnInfo.ExpiresDate,
	}, nil
}

// HandleWebhookEvent processes an App Store Server notification.
//
// For MVP, the webhook logs all events and only acts on REFUND (downgrades the
// user). Renewals and expirations are handled client-side via StoreKit 2
// Transaction.currentEntitlements.
func (s *SubscriptionService) HandleWebhookEvent(ctx context.Context, signedPayload string) error {
	event, err := s.appleClient.ParseWebhookPayload(signedPayload)
	if err != nil {
		return fmt.Errorf("parse webhook payload: %w", err)
	}

	slog.Info("apple webhook received",
		"notification_type", event.NotificationType,
		"subtype", event.Subtype)

	// Parse the signed transaction inside the event to get user-linking info.
	var txnInfo *client.TransactionInfo
	if event.Data.SignedTransactionInfo != "" {
		txnInfo, err = s.appleClient.ParseSignedTransaction(event.Data.SignedTransactionInfo)
		if err != nil {
			slog.Warn("webhook: failed to parse signed transaction",
				"error", err,
				"notification_type", event.NotificationType)
			// Non-fatal — we still return 200 to Apple.
			return nil
		}
		slog.Info("webhook transaction parsed",
			"original_txn_id", txnInfo.OriginalTransactionID,
			"product_id", txnInfo.ProductID,
			"expires", txnInfo.ExpiresDate)
	}

	switch event.NotificationType {
	case "DID_RENEW":
		slog.Info("webhook: subscription renewed",
			"original_txn_id", safeOrigTxnID(txnInfo))
		// Update expiry if we can find the user.
		if txnInfo != nil {
			s.tryUpdateExpiry(ctx, txnInfo)
		}

	case "EXPIRED":
		slog.Info("webhook: subscription expired",
			"original_txn_id", safeOrigTxnID(txnInfo))
		// Downgrade if we can find the user.
		if txnInfo != nil {
			s.tryDowngrade(ctx, txnInfo)
		}

	case "REFUND":
		slog.Info("webhook: refund issued",
			"original_txn_id", safeOrigTxnID(txnInfo))
		if txnInfo != nil {
			s.tryDowngrade(ctx, txnInfo)
		}

	case "DID_CHANGE_RENEWAL_STATUS":
		slog.Info("webhook: renewal status changed",
			"subtype", event.Subtype,
			"original_txn_id", safeOrigTxnID(txnInfo))

	default:
		slog.Info("webhook: unhandled notification type",
			"notification_type", event.NotificationType,
			"subtype", event.Subtype)
	}

	return nil
}

// tryUpdateExpiry attempts to find the user by original_transaction_id and
// update their subscription expiry. Errors are logged but not returned (webhook
// must always return 200).
func (s *SubscriptionService) tryUpdateExpiry(ctx context.Context, txnInfo *client.TransactionInfo) {
	if txnInfo.OriginalTransactionID == "" || txnInfo.ExpiresDate == nil {
		return
	}

	user, err := s.userRepo.GetByOriginalTransactionID(ctx, txnInfo.OriginalTransactionID)
	if err != nil {
		slog.Error("webhook: failed to find user by txn ID",
			"original_txn_id", txnInfo.OriginalTransactionID, "error", err)
		return
	}
	if user == nil {
		slog.Warn("webhook: no user found for original_txn_id",
			"original_txn_id", txnInfo.OriginalTransactionID)
		return
	}

	if err := s.userRepo.UpdateSubscription(ctx, user.ID,
		domain.SubscriptionPro, txnInfo.ExpiresDate, nil); err != nil {
		slog.Error("webhook: failed to update subscription expiry",
			"user_id", user.ID, "error", err)
	} else {
		slog.Info("webhook: subscription expiry updated",
			"user_id", user.ID, "expires_at", txnInfo.ExpiresDate)
	}
}

// tryDowngrade attempts to find the user and revert them to the free tier.
func (s *SubscriptionService) tryDowngrade(ctx context.Context, txnInfo *client.TransactionInfo) {
	if txnInfo.OriginalTransactionID == "" {
		return
	}

	user, err := s.userRepo.GetByOriginalTransactionID(ctx, txnInfo.OriginalTransactionID)
	if err != nil {
		slog.Error("webhook: failed to find user for downgrade",
			"original_txn_id", txnInfo.OriginalTransactionID, "error", err)
		return
	}
	if user == nil {
		slog.Warn("webhook: no user found for downgrade",
			"original_txn_id", txnInfo.OriginalTransactionID)
		return
	}

	if err := s.userRepo.UpdateSubscription(ctx, user.ID,
		domain.SubscriptionFree, nil, nil); err != nil {
		slog.Error("webhook: failed to downgrade user",
			"user_id", user.ID, "error", err)
	} else {
		slog.Info("webhook: user downgraded to free",
			"user_id", user.ID)
	}
}

func safeOrigTxnID(txnInfo *client.TransactionInfo) string {
	if txnInfo == nil {
		return "<unknown>"
	}
	return txnInfo.OriginalTransactionID
}
