package service

import "slices"

type knowledgeAnswerComposer struct{}

func (c knowledgeAnswerComposer) compose(question string, contextResult *KnowledgeContext) *KnowledgeAnswer {
	if contextResult == nil || contextResult.Insufficient || len(contextResult.Sources) == 0 {
		return insufficientKnowledgeAnswer(
			"证据不足，暂时无法根据你的收藏确认这个问题。",
			[]string{"换个角度再问一次", "先继续收藏相关内容"},
		)
	}

	multiSource := isCrossSourceQuestion(question)
	cited := 1
	if multiSource {
		cited = min(2, len(contextResult.Sources))
		if cited < 2 {
			return insufficientKnowledgeAnswer(
				"证据不足，暂时无法根据你的收藏确认这个跨来源问题。",
				[]string{"把问题收窄到一个主题", "先继续收藏相关内容"},
			)
		}
	}

	sources := slices.Clone(contextResult.Sources[:cited])
	citedIndices := make([]int, 0, cited)
	for i := range sources {
		citedIndices = append(citedIndices, i+1)
	}

	answer := buildKnowledgeAnswer(question, sources, citedIndices, multiSource)
	result := &KnowledgeAnswer{
		Status:              KnowledgeStatusAnswered,
		Answer:              answer,
		Sources:             sources,
		CitedIndices:        citedIndices,
		FollowupSuggestions: buildKnowledgeFollowups(question, sources),
	}
	if !isKnowledgeAnswerGrounded(result) {
		return insufficientKnowledgeAnswer(
			"证据不足，暂时无法根据你的收藏确认这个问题。",
			[]string{"换个角度再问一次", "先继续收藏相关内容"},
		)
	}
	return result
}

func insufficientKnowledgeAnswer(answer string, followups []string) *KnowledgeAnswer {
	return &KnowledgeAnswer{
		Status:              KnowledgeStatusInsufficientEvidence,
		Answer:              answer,
		FollowupSuggestions: followups,
	}
}
