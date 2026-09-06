package service

import "context"

type knowledgeLearnContextCollector struct {
	retrieve knowledgeRetrieveFunc
}

func (s *KnowledgeService) learnContextCollector() knowledgeLearnContextCollector {
	return knowledgeLearnContextCollector{retrieve: s.Retrieve}
}

func (c knowledgeLearnContextCollector) collect(ctx context.Context, userID, prompt string) (*KnowledgeContext, error) {
	contextResult, err := c.retrieve(ctx, userID, prompt, KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeLearn,
		MaxSources: 6,
	})
	if err != nil {
		return nil, err
	}
	if !contextResult.Insufficient && len(contextResult.Sources) > 0 {
		return contextResult, nil
	}
	return c.retrieve(ctx, userID, "knowledge learning review", KnowledgeRetrieveOptions{
		Mode:       KnowledgeModeLearn,
		MaxSources: 6,
	})
}
