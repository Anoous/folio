package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/hibiken/asynq"

	"folio-server/internal/client"
	"folio-server/internal/repository"
)

type ImageHandler struct {
	r2Client    *client.R2Client
	articleRepo *repository.ArticleRepo
}

func NewImageHandler(r2Client *client.R2Client, articleRepo *repository.ArticleRepo) *ImageHandler {
	return &ImageHandler{
		r2Client:    r2Client,
		articleRepo: articleRepo,
	}
}

func (h *ImageHandler) ProcessTask(ctx context.Context, t *asynq.Task) error {
	var p ImageUploadPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("unmarshal image payload: %w", err)
	}

	// Get current article markdown
	article, err := h.articleRepo.GetByID(ctx, p.ArticleID)
	if err != nil {
		return fmt.Errorf("get article: %w", err)
	}
	if article == nil || article.MarkdownContent == nil {
		return nil
	}

	markdown := *article.MarkdownContent
	keyPrefix := fmt.Sprintf("articles/%s/images", p.ArticleID)

	// Download and re-upload each image
	for _, imageURL := range p.ImageURLs {
		newURL, err := h.r2Client.DownloadAndUpload(ctx, imageURL, keyPrefix)
		if err != nil {
			continue // Skip failed images
		}
		markdown = strings.ReplaceAll(markdown, imageURL, newURL)
	}

	// Update markdown with new image URLs
	return h.articleRepo.UpdateMarkdownContent(ctx, p.ArticleID, markdown)
}
