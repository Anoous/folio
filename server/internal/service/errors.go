package service

import "errors"

var (
	ErrQuotaExceeded = errors.New("monthly quota exceeded")
	ErrNotFound      = errors.New("not found")
	ErrForbidden     = errors.New("forbidden")
)
