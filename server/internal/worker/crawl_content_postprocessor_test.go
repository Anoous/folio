package worker

import (
	"testing"

	"folio-server/internal/client"
)

func TestCrawlContentPostprocessor_LeavesNonWeiboContentUnchanged(t *testing.T) {
	result := &client.ScrapeResponse{
		Markdown: "# Normal Article\n\nBody",
		Metadata: client.ReaderMetadata{Title: "Normal Title"},
	}

	processed := crawlContentPostprocessor{}.apply("https://example.com/article", result)

	if processed.title != "Normal Title" {
		t.Fatalf("title = %q, want Normal Title", processed.title)
	}
	if processed.markdown != "# Normal Article\n\nBody" {
		t.Fatalf("markdown = %q, want original markdown", processed.markdown)
	}
}

func TestCrawlContentPostprocessor_CleansWeiboContentAndReplacesGenericTitle(t *testing.T) {
	result := &client.ScrapeResponse{
		Markdown: "[#Go语言#](//s.weibo.com/weibo?q=Go) 今天分享一个技巧 //s.weibo.com/weibo?q=other",
		Metadata: client.ReaderMetadata{Title: "微博正文 - 微博"},
	}

	processed := crawlContentPostprocessor{}.apply("https://weibo.com/123/post", result)

	if processed.markdown != "#Go语言# 今天分享一个技巧" {
		t.Fatalf("markdown = %q, want cleaned Weibo markdown", processed.markdown)
	}
	if processed.title != "Go语言# 今天分享一个技巧" {
		t.Fatalf("title = %q, want title extracted from cleaned markdown", processed.title)
	}
}
