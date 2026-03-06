package logger

import (
	"log/slog"
	"os"
	"strings"
)

// Init initializes the global slog logger.
// LOG_FORMAT=json outputs JSON (production); otherwise outputs text (development).
// LOG_LEVEL sets the minimum level: debug, info (default), warn, error.
func Init() {
	format := os.Getenv("LOG_FORMAT")
	level := parseLevel(os.Getenv("LOG_LEVEL"))
	opts := &slog.HandlerOptions{Level: level}

	var handler slog.Handler
	if format == "json" {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	} else {
		handler = slog.NewTextHandler(os.Stdout, opts)
	}
	slog.SetDefault(slog.New(handler))
}

func parseLevel(s string) slog.Level {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
