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
	AIServiceURL string
	JWTSecret    string
	R2Endpoint   string
	R2AccessKey  string
	R2SecretKey  string
	R2BucketName string
	R2PublicURL  string
	DevMode      bool
}

func Load() (*Config, error) {
	cfg := &Config{
		Port:         envOrDefault("PORT", "8080"),
		DatabaseURL:  os.Getenv("DATABASE_URL"),
		RedisAddr:    envOrDefault("REDIS_ADDR", "localhost:6379"),
		ReaderURL:    envOrDefault("READER_URL", "http://localhost:3000"),
		AIServiceURL: envOrDefault("AI_SERVICE_URL", "http://localhost:8000"),
		JWTSecret:    os.Getenv("JWT_SECRET"),
		R2Endpoint:   os.Getenv("R2_ENDPOINT"),
		R2AccessKey:  os.Getenv("R2_ACCESS_KEY"),
		R2SecretKey:  os.Getenv("R2_SECRET_KEY"),
		R2BucketName: envOrDefault("R2_BUCKET_NAME", "folio-images"),
		R2PublicURL:  os.Getenv("R2_PUBLIC_URL"),
		DevMode:      os.Getenv("DEV_MODE") == "true",
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}

	return cfg, nil
}

func envOrDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
