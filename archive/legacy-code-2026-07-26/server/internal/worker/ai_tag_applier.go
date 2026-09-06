package worker

import "context"

type aiTagApplier struct {
	tagRepo TagCreator
}

func (h *AIHandler) tagApplier() aiTagApplier {
	return aiTagApplier{tagRepo: h.tagRepo}
}

func (a aiTagApplier) apply(ctx context.Context, p AIProcessPayload, tagNames []string) {
	for _, tagName := range tagNames {
		tag, err := a.tagRepo.Create(ctx, p.UserID, tagName, true)
		if err != nil {
			continue
		}
		a.tagRepo.AttachToArticle(ctx, p.ArticleID, tag.ID)
	}
}
