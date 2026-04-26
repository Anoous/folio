package service

import "testing"

func TestKnowledgeAnswerComposer_ReturnsInsufficientForEmptyContext(t *testing.T) {
	answer := knowledgeAnswerComposer{}.compose("为什么？", &KnowledgeContext{Insufficient: true})

	if answer.Status != KnowledgeStatusInsufficientEvidence {
		t.Fatalf("status = %q, want insufficient evidence", answer.Status)
	}
	if len(answer.FollowupSuggestions) != 2 || answer.FollowupSuggestions[0] != "换个角度再问一次" {
		t.Fatalf("followups = %v, want default insufficient followups", answer.FollowupSuggestions)
	}
}

func TestKnowledgeAnswerComposer_CitesSingleSourceForSimpleQuestion(t *testing.T) {
	summary := "This source explains the default path."
	answer := knowledgeAnswerComposer{}.compose("为什么默认路径重要？", &KnowledgeContext{
		Sources: []KnowledgeSource{
			{ArticleID: "a1", Title: "Default Path", Summary: &summary},
		},
	})

	if answer.Status != KnowledgeStatusAnswered {
		t.Fatalf("status = %q, want answered", answer.Status)
	}
	if len(answer.Sources) != 1 || answer.Sources[0].ArticleID != "a1" {
		t.Fatalf("sources = %+v, want first source", answer.Sources)
	}
	if len(answer.CitedIndices) != 1 || answer.CitedIndices[0] != 1 {
		t.Fatalf("cited indices = %v, want [1]", answer.CitedIndices)
	}
}

func TestKnowledgeAnswerComposer_CrossSourceRequiresTwoSources(t *testing.T) {
	summary := "Only one source."
	answer := knowledgeAnswerComposer{}.compose("结合两个来源怎么看？", &KnowledgeContext{
		Sources: []KnowledgeSource{
			{ArticleID: "a1", Title: "One", Summary: &summary},
		},
	})

	if answer.Status != KnowledgeStatusInsufficientEvidence {
		t.Fatalf("status = %q, want insufficient evidence", answer.Status)
	}
	if len(answer.FollowupSuggestions) != 2 || answer.FollowupSuggestions[0] != "把问题收窄到一个主题" {
		t.Fatalf("followups = %v, want cross-source insufficient followups", answer.FollowupSuggestions)
	}
}

func TestKnowledgeAnswerComposer_CrossSourceCitesTwoSources(t *testing.T) {
	first := "First source evidence."
	second := "Second source evidence."
	answer := knowledgeAnswerComposer{}.compose("结合可靠性和默认设置怎么看？", &KnowledgeContext{
		Sources: []KnowledgeSource{
			{ArticleID: "a1", Title: "One", Summary: &first},
			{ArticleID: "a2", Title: "Two", Summary: &second},
		},
	})

	if answer.Status != KnowledgeStatusAnswered {
		t.Fatalf("status = %q, want answered", answer.Status)
	}
	if len(answer.Sources) != 2 {
		t.Fatalf("source count = %d, want 2", len(answer.Sources))
	}
	if len(answer.CitedIndices) != 2 || answer.CitedIndices[0] != 1 || answer.CitedIndices[1] != 2 {
		t.Fatalf("cited indices = %v, want [1 2]", answer.CitedIndices)
	}
}
