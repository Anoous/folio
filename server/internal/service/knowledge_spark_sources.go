package service

import (
	"context"
	"fmt"
	"strings"
)

type knowledgeRetrieveFunc func(ctx context.Context, userID, query string, opts KnowledgeRetrieveOptions) (*KnowledgeContext, error)

type knowledgeSparkSourceCollector struct {
	repo     knowledgeDocumentLister
	retrieve knowledgeRetrieveFunc
}

func (s *KnowledgeService) sparkSourceCollector() knowledgeSparkSourceCollector {
	return knowledgeSparkSourceCollector{
		repo:     s.repo,
		retrieve: s.Retrieve,
	}
}

func (c knowledgeSparkSourceCollector) collect(ctx context.Context, userID, prompt string) ([]KnowledgeSource, error) {
	var sources []KnowledgeSource
	if strings.TrimSpace(prompt) == "" {
		allDocs, err := c.repo.ListKnowledgeDocuments(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("list knowledge documents: %w", err)
		}
		sources = knowledgeDocumentsToSources(allDocs, 1)
	} else {
		contextResult, err := c.retrieve(ctx, userID, prompt, KnowledgeRetrieveOptions{
			Mode:       KnowledgeModeSpark,
			MaxSources: 8,
		})
		if err != nil {
			return nil, err
		}
		sources = contextResult.Sources
	}

	if len(sources) < 6 {
		allDocs, err := c.repo.ListKnowledgeDocuments(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("list knowledge documents: %w", err)
		}
		existing := map[string]bool{}
		for _, source := range sources {
			existing[source.ArticleID] = true
		}
		for _, doc := range allDocs {
			if len(sources) >= 6 {
				break
			}
			if existing[doc.ArticleID] {
				continue
			}
			sources = append(sources, knowledgeDocumentToSource(doc, 0.5))
		}
	}

	return sources, nil
}

func knowledgeDocumentsToSources(docs []KnowledgeDocument, relevance float64) []KnowledgeSource {
	sources := make([]KnowledgeSource, 0, len(docs))
	for _, doc := range docs {
		sources = append(sources, knowledgeDocumentToSource(doc, relevance))
	}
	return sources
}

func knowledgeDocumentToSource(doc KnowledgeDocument, relevance float64) KnowledgeSource {
	summary := doc.Summary
	return KnowledgeSource{
		ArticleID: doc.ArticleID,
		Title:     doc.Title,
		SiteName:  doc.SiteName,
		Summary:   &summary,
		CreatedAt: doc.CreatedAt,
		Relevance: relevance,
	}
}
