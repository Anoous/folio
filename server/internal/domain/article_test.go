package domain

import "testing"

func TestSourceManualConstant(t *testing.T) {
	if SourceManual != "manual" {
		t.Errorf("SourceManual = %q, want %q", SourceManual, "manual")
	}
}
