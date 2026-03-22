package service

import "errors"

var (
	ErrQuotaExceeded    = errors.New("monthly quota exceeded")
	ErrRAGQuotaExceeded = errors.New("rag monthly quota exceeded")
	ErrNotFound         = errors.New("not found")
	ErrForbidden        = errors.New("forbidden")
	ErrDuplicateURL     = errors.New("url already saved")
	ErrInvalidCode      = errors.New("invalid verification code")
	ErrCodeRateLimit    = errors.New("verification code rate limit")

	// Subscription errors
	ErrInvalidProduct       = errors.New("invalid product ID")
	ErrInvalidBundleID      = errors.New("bundle ID mismatch")
	ErrSubscriptionExpired  = errors.New("subscription already expired")
)
