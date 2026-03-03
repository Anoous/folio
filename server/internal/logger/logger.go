package logger

import (
	"log/slog"
	"os"
)

// Init initializes the global slog logger.
// LOG_FORMAT=json outputs JSON (production); otherwise outputs text (development).
func Init() {
	format := os.Getenv("LOG_FORMAT")
	opts := &slog.HandlerOptions{Level: slog.LevelInfo}

	var handler slog.Handler
	if format == "json" {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	} else {
		handler = slog.NewTextHandler(os.Stdout, opts)
	}
	slog.SetDefault(slog.New(handler))
}
