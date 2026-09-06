package repository

import "strings"

func prepareKnowledgeRecallTerms(keywords []string) ([]string, []string, string) {
	cleaned := make([]string, 0, len(keywords))
	escaped := make([]string, 0, len(keywords))
	queryParts := make([]string, 0, len(keywords))
	seen := map[string]bool{}

	for _, kw := range keywords {
		term := strings.ToLower(strings.TrimSpace(kw))
		if term == "" || seen[term] {
			continue
		}
		seen[term] = true
		cleaned = append(cleaned, term)
		escaped = append(escaped, escapeILIKE(term))
		queryParts = append(queryParts, formatFullTextQueryTerm(term))
	}

	return cleaned, escaped, strings.Join(queryParts, " ")
}

func formatFullTextQueryTerm(term string) string {
	if !strings.Contains(term, " ") {
		return term
	}
	term = strings.ReplaceAll(term, `"`, " ")
	term = strings.Join(strings.Fields(term), " ")
	return `"` + term + `"`
}
