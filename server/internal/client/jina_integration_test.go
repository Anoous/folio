package client

import (
	"context"
	"os"
	"testing"
	"time"
)

// Run: go test ./internal/client/ -run TestJinaScrapeXPost$ -v -timeout 60s
func TestJinaScrapeXPost(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	apiKey := os.Getenv("JINA_API_KEY")
	if apiKey == "" {
		t.Skip("JINA_API_KEY not set, skipping")
	}

	c := NewJinaClient(apiKey)
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	url := "https://x.com/sunlc_crypto/status/2029881612243194116?s=20"
	resp, err := c.Scrape(ctx, url)
	if err != nil {
		t.Fatalf("Scrape failed: %v", err)
	}

	t.Logf("Title:       %s", resp.Metadata.Title)
	t.Logf("Content len: %d", len(resp.Markdown))
	t.Logf("Content preview:\n%.800s", resp.Markdown)

	if resp.Markdown == "" {
		t.Error("expected non-empty markdown content")
	}
	if resp.Metadata.Title == "" {
		t.Error("expected non-empty title")
	}
}

// Run: go test ./internal/client/ -run TestJinaScrapeWechat -v -timeout 60s
func TestJinaScrapeWechat(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	apiKey := os.Getenv("JINA_API_KEY")
	c := NewJinaClient(apiKey)
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	url := "https://mp.weixin.qq.com/s/dLNfvdobYRPLziWqwYXI8Q"
	resp, err := c.Scrape(ctx, url)
	if err != nil {
		t.Fatalf("Scrape failed: %v", err)
	}

	t.Logf("Title:       %s", resp.Metadata.Title)
	t.Logf("Content len: %d", len(resp.Markdown))
	t.Logf("Content preview:\n%.800s", resp.Markdown)
}

// Run: go test ./internal/client/ -run TestJinaScrapeZhihu -v -timeout 60s
func TestJinaScrapeZhihu(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	apiKey := os.Getenv("JINA_API_KEY")
	c := NewJinaClient(apiKey)
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	url := "https://zhuanlan.zhihu.com/p/666881945"
	resp, err := c.Scrape(ctx, url)
	if err != nil {
		t.Fatalf("Scrape failed: %v", err)
	}

	t.Logf("Title:       %s", resp.Metadata.Title)
	t.Logf("Content len: %d", len(resp.Markdown))
	t.Logf("Content preview:\n%.800s", resp.Markdown)
}

// Run: go test ./internal/client/ -run TestJinaScrapeXiaohongshu -v -timeout 60s
func TestJinaScrapeXiaohongshu(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	apiKey := os.Getenv("JINA_API_KEY")
	c := NewJinaClient(apiKey)
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	url := "https://www.xiaohongshu.com/explore/683541b5000000000b00db42"
	resp, err := c.Scrape(ctx, url)
	if err != nil {
		t.Fatalf("Scrape failed: %v", err)
	}

	t.Logf("Title:       %s", resp.Metadata.Title)
	t.Logf("Content len: %d", len(resp.Markdown))
	t.Logf("Content preview:\n%.800s", resp.Markdown)
}

// Run: go test ./internal/client/ -run TestJinaScrapeBlog -v -timeout 60s
func TestJinaScrapeBlog(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	c := NewJinaClient("") // no key needed for regular sites
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	url := "https://go.dev/blog/go1.24"
	resp, err := c.Scrape(ctx, url)
	if err != nil {
		t.Fatalf("Scrape failed: %v", err)
	}

	t.Logf("Title:       %s", resp.Metadata.Title)
	t.Logf("Content len: %d", len(resp.Markdown))
	t.Logf("Content preview:\n%.500s", resp.Markdown)

	if resp.Markdown == "" {
		t.Error("expected non-empty markdown content")
	}
}
