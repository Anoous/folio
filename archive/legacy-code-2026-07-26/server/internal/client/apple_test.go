package client

import (
	"errors"
	"net/http"
	"testing"
)

func TestClassifyAppleAPIError_MapsInvalidTransactionStatuses(t *testing.T) {
	statuses := []int{http.StatusBadRequest, http.StatusNotFound}

	for _, status := range statuses {
		t.Run(http.StatusText(status), func(t *testing.T) {
			err := classifyAppleAPIError(status, []byte(`{"errorCode":"INVALID_TRANSACTION_ID"}`))
			if !errors.Is(err, ErrAppleTransactionNotFound) {
				t.Fatalf("classifyAppleAPIError() error = %v, want %v", err, ErrAppleTransactionNotFound)
			}
		})
	}
}

func TestClassifyAppleAPIError_PreservesUpstreamFailures(t *testing.T) {
	err := classifyAppleAPIError(http.StatusInternalServerError, []byte("unavailable"))

	var apiErr *AppleAPIError
	if !errors.As(err, &apiErr) {
		t.Fatalf("classifyAppleAPIError() error = %T, want *AppleAPIError", err)
	}
	if apiErr.StatusCode != http.StatusInternalServerError {
		t.Fatalf("StatusCode = %d, want %d", apiErr.StatusCode, http.StatusInternalServerError)
	}
	if errors.Is(err, ErrAppleTransactionNotFound) {
		t.Fatal("classifyAppleAPIError() marked upstream failure as invalid transaction")
	}
}
