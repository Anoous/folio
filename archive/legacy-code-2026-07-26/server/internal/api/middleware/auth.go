package middleware

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"folio-server/internal/service"
)

type contextKey string

const userIDKey contextKey = "userID"

func JWTAuth(authService *service.AuthService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				slog.Debug("auth: missing authorization header", "path", r.URL.Path)
				writeAuthError(w, "missing authorization header")
				return
			}

			token := strings.TrimPrefix(authHeader, "Bearer ")
			if token == authHeader {
				slog.Debug("auth: invalid authorization format", "path", r.URL.Path)
				writeAuthError(w, "invalid authorization format")
				return
			}

			userID, err := authService.ValidateAccessToken(token)
			if err != nil {
				slog.Debug("auth: token validation failed", "path", r.URL.Path, "error", err)
				writeAuthError(w, "invalid or expired token")
				return
			}

			ctx := context.WithValue(r.Context(), userIDKey, userID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func writeAuthError(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

// UserIDFromContext extracts the user ID from the request context.
// Returns the user ID set by JWTAuth middleware. Returns empty string if not set
// (should not happen for routes behind JWTAuth).
func UserIDFromContext(ctx context.Context) string {
	id, ok := ctx.Value(userIDKey).(string)
	if !ok || id == "" {
		slog.Error("UserIDFromContext: no user ID in context")
		return ""
	}
	return id
}

// ContextWithUserID returns a new context with the given userID set.
// This is useful for testing handlers without going through JWT validation.
func ContextWithUserID(ctx context.Context, userID string) context.Context {
	return context.WithValue(ctx, userIDKey, userID)
}
