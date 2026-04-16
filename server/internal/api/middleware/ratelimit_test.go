package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRateLimiterMiddleware_IgnoresSpoofedForwardedFor(t *testing.T) {
	rl := NewRateLimiter(1, 1)

	var nextCalls int
	handler := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nextCalls++
		w.WriteHeader(http.StatusOK)
	}))

	req1 := httptest.NewRequest(http.MethodPost, "/auth/email/code", nil)
	req1.RemoteAddr = "198.51.100.10:1234"
	req1.Header.Set("X-Forwarded-For", "203.0.113.1")
	resp1 := httptest.NewRecorder()
	handler.ServeHTTP(resp1, req1)

	if resp1.Code != http.StatusOK {
		t.Fatalf("first request status = %d, want %d", resp1.Code, http.StatusOK)
	}

	req2 := httptest.NewRequest(http.MethodPost, "/auth/email/code", nil)
	req2.RemoteAddr = "198.51.100.10:5678"
	req2.Header.Set("X-Forwarded-For", "203.0.113.2")
	resp2 := httptest.NewRecorder()
	handler.ServeHTTP(resp2, req2)

	if resp2.Code != http.StatusTooManyRequests {
		t.Fatalf("second request status = %d, want %d", resp2.Code, http.StatusTooManyRequests)
	}
	if nextCalls != 1 {
		t.Fatalf("next handler calls = %d, want 1", nextCalls)
	}
}

func TestClientIP_FallsBackToRemoteAddrWhenSplitFails(t *testing.T) {
	if got := clientIP("198.51.100.10"); got != "198.51.100.10" {
		t.Fatalf("clientIP() = %q, want raw remote addr", got)
	}
}

func TestRateLimiterMiddleware_UsesForwardedForFromTrustedProxy(t *testing.T) {
	rl := NewRateLimiter(1, 1)

	var nextCalls int
	handler := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nextCalls++
		w.WriteHeader(http.StatusOK)
	}))

	req1 := httptest.NewRequest(http.MethodPost, "/auth/email/code", nil)
	req1.RemoteAddr = "10.0.0.2:1234"
	req1.Header.Set("X-Forwarded-For", "203.0.113.1")
	resp1 := httptest.NewRecorder()
	handler.ServeHTTP(resp1, req1)

	req2 := httptest.NewRequest(http.MethodPost, "/auth/email/code", nil)
	req2.RemoteAddr = "10.0.0.2:5678"
	req2.Header.Set("X-Forwarded-For", "203.0.113.2")
	resp2 := httptest.NewRecorder()
	handler.ServeHTTP(resp2, req2)

	if resp1.Code != http.StatusOK || resp2.Code != http.StatusOK {
		t.Fatalf("statuses = (%d, %d), want both 200", resp1.Code, resp2.Code)
	}
	if nextCalls != 2 {
		t.Fatalf("next handler calls = %d, want 2", nextCalls)
	}
}

func TestRateLimiterMiddleware_UsesRightMostUntrustedForwardedIP(t *testing.T) {
	rl := NewRateLimiter(1, 1)

	var nextCalls int
	handler := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		nextCalls++
		w.WriteHeader(http.StatusOK)
	}))

	req1 := httptest.NewRequest(http.MethodPost, "/auth/email/code", nil)
	req1.RemoteAddr = "10.0.0.2:1234"
	req1.Header.Set("X-Forwarded-For", "198.51.100.200, 203.0.113.9")
	resp1 := httptest.NewRecorder()
	handler.ServeHTTP(resp1, req1)

	req2 := httptest.NewRequest(http.MethodPost, "/auth/email/code", nil)
	req2.RemoteAddr = "10.0.0.2:5678"
	req2.Header.Set("X-Forwarded-For", "203.0.113.9")
	resp2 := httptest.NewRecorder()
	handler.ServeHTTP(resp2, req2)

	if resp1.Code != http.StatusOK {
		t.Fatalf("first request status = %d, want %d", resp1.Code, http.StatusOK)
	}
	if resp2.Code != http.StatusTooManyRequests {
		t.Fatalf("second request status = %d, want %d", resp2.Code, http.StatusTooManyRequests)
	}
	if nextCalls != 1 {
		t.Fatalf("next handler calls = %d, want 1", nextCalls)
	}
}
