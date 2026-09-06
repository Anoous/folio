package domain

import (
	"encoding/json"
	"testing"
)

func TestSourceManual_JSONRoundTrip(t *testing.T) {
	// Verify SourceManual survives JSON serialization (the actual cross-module contract).
	article := Article{SourceType: SourceManual}
	data, err := json.Marshal(article)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var decoded Article
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if decoded.SourceType != SourceManual {
		t.Errorf("round-trip: got %q, want %q", decoded.SourceType, SourceManual)
	}
}

func TestSourceManual_IsDistinctFromOtherTypes(t *testing.T) {
	others := []SourceType{SourceWeb, SourceWechat, SourceTwitter, SourceWeibo, SourceZhihu, SourceNewsletter, SourceYoutube}
	for _, other := range others {
		if SourceManual == other {
			t.Errorf("SourceManual should be distinct from %q", other)
		}
	}
}
