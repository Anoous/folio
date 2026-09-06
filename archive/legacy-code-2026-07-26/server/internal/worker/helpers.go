package worker

// derefFloat returns the dereferenced float64 or 0 if the pointer is nil.
func derefFloat(f *float64) float64 {
	if f != nil {
		return *f
	}
	return 0
}

// derefOrEmpty returns the dereferenced string or "" if the pointer is nil.
func derefOrEmpty(s *string) string {
	if s != nil {
		return *s
	}
	return ""
}

// derefOrDefault returns the dereferenced string, or fallback if nil or empty.
func derefOrDefault(s *string, fallback string) string {
	if s != nil && *s != "" {
		return *s
	}
	return fallback
}
