package service

type knowledgeGrounding struct {
	sources    []KnowledgeSource
	sourceByID map[string]KnowledgeSource
}

func newKnowledgeGrounding(sources []KnowledgeSource) knowledgeGrounding {
	sourceByID := make(map[string]KnowledgeSource, len(sources))
	for _, source := range sources {
		if source.ArticleID == "" || !knowledgeSourceHasEvidence(source) {
			continue
		}
		sourceByID[source.ArticleID] = source
	}
	return knowledgeGrounding{
		sources:    sources,
		sourceByID: sourceByID,
	}
}

func (g knowledgeGrounding) groundedSourceIDs(ids []string) []string {
	seen := map[string]bool{}
	result := make([]string, 0, len(ids))
	for _, id := range ids {
		if id == "" || seen[id] {
			continue
		}
		if _, ok := g.sourceByID[id]; !ok {
			continue
		}
		seen[id] = true
		result = append(result, id)
	}
	return result
}

func (g knowledgeGrounding) sourcesByUsedIDs(used map[string]bool) []KnowledgeSource {
	result := make([]KnowledgeSource, 0, len(used))
	for _, source := range g.sources {
		if used[source.ArticleID] {
			result = append(result, source)
		}
	}
	return result
}
