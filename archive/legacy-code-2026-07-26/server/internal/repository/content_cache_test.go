package repository

import (
	"testing"

	"folio-server/internal/domain"
)

func TestIsCacheWorthy_ShortContent(t *testing.T) {
	if domain.IsCacheWorthy("short", 0.9) {
		t.Error("content under 200 bytes should not be cache-worthy")
	}
}

func TestIsCacheWorthy_LongContent(t *testing.T) {
	content := make([]byte, 200)
	for i := range content {
		content[i] = 'a'
	}
	if !domain.IsCacheWorthy(string(content), 0.9) {
		t.Error("content at 200 bytes should be cache-worthy")
	}
}
