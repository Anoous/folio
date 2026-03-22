package config

import (
	"fmt"
	"os"
)

type Config struct {
	Port         string
	DatabaseURL  string
	RedisAddr    string
	ReaderURL    string
	DeepSeekAPIKey  string
	DeepSeekBaseURL string
	JWTSecret    string
	R2Endpoint   string
	R2AccessKey  string
	R2SecretKey  string
	R2BucketName string
	R2PublicURL  string
	JinaAPIKey     string
	AppleBundleID  string
	ResendAPIKey   string
	AppMode        string // "api" | "worker" | "all" (default "all")
}

func Load() (*Config, error) {
	cfg := &Config{
		Port:         envOrDefault("PORT", "8080"),
		DatabaseURL:  os.Getenv("DATABASE_URL"),
		RedisAddr:    envOrDefault("REDIS_ADDR", "localhost:6379"),
		ReaderURL:    envOrDefault("READER_URL", "http://localhost:3000"),
		DeepSeekAPIKey:  os.Getenv("DEEPSEEK_API_KEY"),
		DeepSeekBaseURL: envOrDefault("DEEPSEEK_BASE_URL", "https://api.deepseek.com"),
		JWTSecret:    os.Getenv("JWT_SECRET"),
		R2Endpoint:   os.Getenv("R2_ENDPOINT"),
		R2AccessKey:  os.Getenv("R2_ACCESS_KEY"),
		R2SecretKey:  os.Getenv("R2_SECRET_KEY"),
		R2BucketName: envOrDefault("R2_BUCKET_NAME", "folio-images"),
		R2PublicURL:  os.Getenv("R2_PUBLIC_URL"),
		JinaAPIKey:    os.Getenv("JINA_API_KEY"),
		ResendAPIKey:  os.Getenv("RESEND_API_KEY"),
		AppleBundleID: envOrDefault("APPLE_BUNDLE_ID", "com.7WSH9CR7KS.folio.app"),
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}
	if len(cfg.JWTSecret) < 32 {
		return nil, fmt.Errorf("JWT_SECRET must be at least 32 characters")
	}

	cfg.AppMode = os.Getenv("APP_MODE")
	if cfg.AppMode == "" {
		cfg.AppMode = "all"
	}
	if cfg.AppMode != "api" && cfg.AppMode != "worker" && cfg.AppMode != "all" {
		return nil, fmt.Errorf("invalid APP_MODE %q: must be api, worker, or all", cfg.AppMode)
	}

	return cfg, nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
