package worker

import (
	"encoding/json"
	"time"

	"github.com/hibiken/asynq"
)

const (
	TypeCrawlArticle = "article:crawl"
	TypeAIProcess    = "article:ai"
	TypeImageUpload  = "article:images"

	QueueCritical = "critical"
	QueueDefault  = "default"
	QueueLow      = "low"
)

type CrawlPayload struct {
	ArticleID string `json:"article_id"`
	TaskID    string `json:"task_id"`
	URL       string `json:"url"`
	UserID    string `json:"user_id"`
}

type AIProcessPayload struct {
	ArticleID string `json:"article_id"`
	TaskID    string `json:"task_id"`
	UserID    string `json:"user_id"`
	Title     string `json:"title"`
	Markdown  string `json:"markdown"`
	Source    string `json:"source"`
	Author    string `json:"author"`
}

type ImageUploadPayload struct {
	ArticleID string   `json:"article_id"`
	ImageURLs []string `json:"image_urls"`
}

func NewCrawlTask(articleID, taskID, url, userID string) *asynq.Task {
	payload, _ := json.Marshal(CrawlPayload{
		ArticleID: articleID,
		TaskID:    taskID,
		URL:       url,
		UserID:    userID,
	})
	return asynq.NewTask(TypeCrawlArticle, payload,
		asynq.Queue(QueueCritical),
		asynq.MaxRetry(3),
		asynq.Timeout(90*time.Second),
	)
}

func NewAIProcessTask(articleID, taskID, userID, title, markdown, source, author string) *asynq.Task {
	payload, _ := json.Marshal(AIProcessPayload{
		ArticleID: articleID,
		TaskID:    taskID,
		UserID:    userID,
		Title:     title,
		Markdown:  markdown,
		Source:    source,
		Author:    author,
	})
	return asynq.NewTask(TypeAIProcess, payload,
		asynq.Queue(QueueDefault),
		asynq.MaxRetry(3),
		asynq.Timeout(60*time.Second),
	)
}

func NewImageUploadTask(articleID string, imageURLs []string) *asynq.Task {
	payload, _ := json.Marshal(ImageUploadPayload{
		ArticleID: articleID,
		ImageURLs: imageURLs,
	})
	return asynq.NewTask(TypeImageUpload, payload,
		asynq.Queue(QueueLow),
		asynq.MaxRetry(2),
		asynq.Timeout(5*time.Minute),
	)
}
