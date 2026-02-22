package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type ArticleRepo struct {
	pool *pgxpool.Pool
}

func NewArticleRepo(pool *pgxpool.Pool) *ArticleRepo {
	return &ArticleRepo{pool: pool}
}

type CreateArticleParams struct {
	UserID     string
	URL        string
	SourceType domain.SourceType
}

func (r *ArticleRepo) Create(ctx context.Context, p CreateArticleParams) (*domain.Article, error) {
	var a domain.Article
	err := r.pool.QueryRow(ctx, `
		INSERT INTO articles (user_id, url, source_type)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, url, status, source_type, created_at, updated_at`,
		p.UserID, p.URL, p.SourceType,
	).Scan(&a.ID, &a.UserID, &a.URL, &a.Status, &a.SourceType, &a.CreatedAt, &a.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("insert article: %w", err)
	}
	return &a, nil
}

func (r *ArticleRepo) GetByID(ctx context.Context, id string) (*domain.Article, error) {
	var a domain.Article
	var keyPointsJSON []byte
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, url, title, author, site_name, favicon_url, cover_image_url,
		       markdown_content, word_count, language, category_id, summary, key_points,
		       ai_confidence, status, source_type, fetch_error, retry_count,
		       is_favorite, is_archived, read_progress, last_read_at, published_at,
		       created_at, updated_at
		FROM articles WHERE id = $1`, id,
	).Scan(
		&a.ID, &a.UserID, &a.URL, &a.Title, &a.Author, &a.SiteName,
		&a.FaviconURL, &a.CoverImageURL, &a.MarkdownContent, &a.WordCount,
		&a.Language, &a.CategoryID, &a.Summary, &keyPointsJSON,
		&a.AIConfidence, &a.Status, &a.SourceType, &a.FetchError, &a.RetryCount,
		&a.IsFavorite, &a.IsArchived, &a.ReadProgress, &a.LastReadAt, &a.PublishedAt,
		&a.CreatedAt, &a.UpdatedAt,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get article: %w", err)
	}
	if keyPointsJSON != nil {
		json.Unmarshal(keyPointsJSON, &a.KeyPoints)
	}
	return &a, nil
}

type ListArticlesParams struct {
	UserID   string
	Category *string
	Status   *domain.ArticleStatus
	Favorite *bool
	Page     int
	PerPage  int
}

type ListArticlesResult struct {
	Articles []domain.Article `json:"data"`
	Total    int              `json:"total"`
}

func (r *ArticleRepo) ListByUser(ctx context.Context, p ListArticlesParams) (*ListArticlesResult, error) {
	if p.Page < 1 {
		p.Page = 1
	}
	if p.PerPage < 1 || p.PerPage > 100 {
		p.PerPage = 20
	}
	offset := (p.Page - 1) * p.PerPage

	// Count
	countQuery := `SELECT COUNT(*) FROM articles WHERE user_id = $1`
	args := []any{p.UserID}
	argIdx := 2

	if p.Category != nil {
		countQuery += fmt.Sprintf(` AND category_id = (SELECT id FROM categories WHERE slug = $%d)`, argIdx)
		args = append(args, *p.Category)
		argIdx++
	}
	if p.Status != nil {
		countQuery += fmt.Sprintf(` AND status = $%d`, argIdx)
		args = append(args, *p.Status)
		argIdx++
	}
	if p.Favorite != nil {
		countQuery += fmt.Sprintf(` AND is_favorite = $%d`, argIdx)
		args = append(args, *p.Favorite)
		argIdx++
	}

	var total int
	if err := r.pool.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, fmt.Errorf("count articles: %w", err)
	}

	// Query
	query := `SELECT id, user_id, url, title, summary, cover_image_url, site_name,
	                 source_type, category_id, word_count, is_favorite, is_archived,
	                 read_progress, status, created_at, updated_at
	          FROM articles WHERE user_id = $1`
	queryArgs := []any{p.UserID}
	qArgIdx := 2

	if p.Category != nil {
		query += fmt.Sprintf(` AND category_id = (SELECT id FROM categories WHERE slug = $%d)`, qArgIdx)
		queryArgs = append(queryArgs, *p.Category)
		qArgIdx++
	}
	if p.Status != nil {
		query += fmt.Sprintf(` AND status = $%d`, qArgIdx)
		queryArgs = append(queryArgs, *p.Status)
		qArgIdx++
	}
	if p.Favorite != nil {
		query += fmt.Sprintf(` AND is_favorite = $%d`, qArgIdx)
		queryArgs = append(queryArgs, *p.Favorite)
		qArgIdx++
	}

	query += fmt.Sprintf(` ORDER BY created_at DESC LIMIT $%d OFFSET $%d`, qArgIdx, qArgIdx+1)
	queryArgs = append(queryArgs, p.PerPage, offset)

	rows, err := r.pool.Query(ctx, query, queryArgs...)
	if err != nil {
		return nil, fmt.Errorf("list articles: %w", err)
	}
	defer rows.Close()

	articles := make([]domain.Article, 0)
	for rows.Next() {
		var a domain.Article
		if err := rows.Scan(
			&a.ID, &a.UserID, &a.URL, &a.Title, &a.Summary, &a.CoverImageURL,
			&a.SiteName, &a.SourceType, &a.CategoryID, &a.WordCount,
			&a.IsFavorite, &a.IsArchived, &a.ReadProgress, &a.Status, &a.CreatedAt,
			&a.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan article: %w", err)
		}
		articles = append(articles, a)
	}

	return &ListArticlesResult{Articles: articles, Total: total}, nil
}

func (r *ArticleRepo) UpdateStatus(ctx context.Context, id string, status domain.ArticleStatus) error {
	_, err := r.pool.Exec(ctx, `UPDATE articles SET status = $1 WHERE id = $2`, status, id)
	if err != nil {
		return fmt.Errorf("update status: %w", err)
	}
	return nil
}

func (r *ArticleRepo) SetError(ctx context.Context, id string, errMsg string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE articles SET fetch_error = $1, retry_count = retry_count + 1 WHERE id = $2`,
		errMsg, id)
	if err != nil {
		return fmt.Errorf("set error: %w", err)
	}
	return nil
}

type CrawlResult struct {
	Title      string
	Author     string
	SiteName   string
	Markdown   string
	CoverImage string
	Language   string
	FaviconURL string
}

func (r *ArticleRepo) UpdateCrawlResult(ctx context.Context, id string, cr CrawlResult) error {
	wordCount := len([]rune(cr.Markdown))
	_, err := r.pool.Exec(ctx, `
		UPDATE articles SET
			title = $1, author = $2, site_name = $3, markdown_content = $4,
			cover_image_url = $5, language = $6, favicon_url = $7, word_count = $8
		WHERE id = $9`,
		truncateUTF8(cr.Title, 500), truncateUTF8(cr.Author, 200), truncateUTF8(cr.SiteName, 200), cr.Markdown,
		truncateUTF8(cr.CoverImage, 500), truncateUTF8(cr.Language, 10), truncateUTF8(cr.FaviconURL, 500), wordCount, id)
	if err != nil {
		return fmt.Errorf("update crawl result: %w", err)
	}
	return nil
}

// truncateUTF8 truncates s to at most maxLen runes.
func truncateUTF8(s string, maxLen int) string {
	runes := []rune(s)
	if len(runes) <= maxLen {
		return s
	}
	return string(runes[:maxLen])
}

type AIResult struct {
	CategorySlug string
	Summary      string
	KeyPoints    []string
	Confidence   float64
	Language     string
}

func (r *ArticleRepo) UpdateAIResult(ctx context.Context, id string, ai AIResult) error {
	keyPointsJSON, _ := json.Marshal(ai.KeyPoints)
	_, err := r.pool.Exec(ctx, `
		UPDATE articles SET
			category_id = (SELECT id FROM categories WHERE slug = $1),
			summary = $2, key_points = $3, ai_confidence = $4, language = $5,
			status = 'ready'
		WHERE id = $6`,
		ai.CategorySlug, ai.Summary, keyPointsJSON, ai.Confidence, ai.Language, id)
	if err != nil {
		return fmt.Errorf("update ai result: %w", err)
	}
	return nil
}

func (r *ArticleRepo) UpdateMarkdownContent(ctx context.Context, id string, markdown string) error {
	wordCount := len([]rune(markdown))
	_, err := r.pool.Exec(ctx,
		`UPDATE articles SET markdown_content = $1, word_count = $2 WHERE id = $3`,
		markdown, wordCount, id)
	if err != nil {
		return fmt.Errorf("update markdown content: %w", err)
	}
	return nil
}

type UpdateArticleParams struct {
	IsFavorite   *bool    `json:"is_favorite,omitempty"`
	IsArchived   *bool    `json:"is_archived,omitempty"`
	ReadProgress *float64 `json:"read_progress,omitempty"`
}

func (r *ArticleRepo) Update(ctx context.Context, id string, p UpdateArticleParams) error {
	setClauses := ""
	args := []any{}
	argIdx := 1

	if p.IsFavorite != nil {
		setClauses += fmt.Sprintf("is_favorite = $%d, ", argIdx)
		args = append(args, *p.IsFavorite)
		argIdx++
	}
	if p.IsArchived != nil {
		setClauses += fmt.Sprintf("is_archived = $%d, ", argIdx)
		args = append(args, *p.IsArchived)
		argIdx++
	}
	if p.ReadProgress != nil {
		setClauses += fmt.Sprintf("read_progress = $%d, last_read_at = NOW(), ", argIdx)
		args = append(args, *p.ReadProgress)
		argIdx++
	}

	if len(args) == 0 {
		return nil
	}

	// Remove trailing comma+space
	setClauses = setClauses[:len(setClauses)-2]
	query := fmt.Sprintf("UPDATE articles SET %s WHERE id = $%d", setClauses, argIdx)
	args = append(args, id)

	_, err := r.pool.Exec(ctx, query, args...)
	if err != nil {
		return fmt.Errorf("update article: %w", err)
	}
	return nil
}

func (r *ArticleRepo) Delete(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM articles WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("delete article: %w", err)
	}
	return nil
}

func (r *ArticleRepo) SearchByTitle(ctx context.Context, userID, query string, page, perPage int) (*ListArticlesResult, error) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	offset := (page - 1) * perPage
	pattern := "%" + query + "%"

	var total int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM articles WHERE user_id = $1 AND title ILIKE $2`,
		userID, pattern,
	).Scan(&total)
	if err != nil {
		return nil, fmt.Errorf("count search: %w", err)
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, url, title, summary, site_name, source_type, created_at
		FROM articles WHERE user_id = $1 AND title ILIKE $2
		ORDER BY created_at DESC LIMIT $3 OFFSET $4`,
		userID, pattern, perPage, offset)
	if err != nil {
		return nil, fmt.Errorf("search articles: %w", err)
	}
	defer rows.Close()

	articles := make([]domain.Article, 0)
	for rows.Next() {
		var a domain.Article
		if err := rows.Scan(&a.ID, &a.UserID, &a.URL, &a.Title, &a.Summary,
			&a.SiteName, &a.SourceType, &a.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan search result: %w", err)
		}
		articles = append(articles, a)
	}

	return &ListArticlesResult{Articles: articles, Total: total}, nil
}
