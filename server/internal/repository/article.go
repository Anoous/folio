package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
	"unicode"

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
	UserID          string
	URL             *string
	SourceType      domain.SourceType
	Title           *string
	Author          *string
	SiteName        *string
	MarkdownContent *string
	WordCount       *int
	ClientID        *string
}

func (r *ArticleRepo) Create(ctx context.Context, p CreateArticleParams) (*domain.Article, error) {
	wordCount := 0
	if p.WordCount != nil {
		wordCount = *p.WordCount
	}

	var a domain.Article
	err := r.pool.QueryRow(ctx, `
		INSERT INTO articles (user_id, url, source_type, title, author, site_name, markdown_content, word_count, client_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, user_id, url, status, source_type, created_at, updated_at`,
		p.UserID, p.URL, p.SourceType, p.Title, p.Author, p.SiteName, p.MarkdownContent, wordCount, p.ClientID,
	).Scan(&a.ID, &a.UserID, &a.URL, &a.Status, &a.SourceType, &a.CreatedAt, &a.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("insert article: %w", err)
	}
	a.KeyPoints = []string{}
	return &a, nil
}

func (r *ArticleRepo) ExistsByUserAndClientID(ctx context.Context, userID, clientID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM articles WHERE user_id = $1 AND client_id = $2 AND deleted_at IS NULL)`,
		userID, clientID,
	).Scan(&exists)
	return exists, err
}

func (r *ArticleRepo) GetByID(ctx context.Context, id string) (*domain.Article, error) {
	var a domain.Article
	var keyPointsJSON []byte
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, url, title, author, site_name, favicon_url, cover_image_url,
		       markdown_content, word_count, language, category_id, summary, key_points,
		       ai_confidence, status, source_type, fetch_error, retry_count,
		       is_favorite, is_archived, read_progress, highlight_count, last_read_at, published_at,
		       created_at, updated_at, deleted_at, semantic_keywords
		FROM articles WHERE id = $1`, id,
	).Scan(
		&a.ID, &a.UserID, &a.URL, &a.Title, &a.Author, &a.SiteName,
		&a.FaviconURL, &a.CoverImageURL, &a.MarkdownContent, &a.WordCount,
		&a.Language, &a.CategoryID, &a.Summary, &keyPointsJSON,
		&a.AIConfidence, &a.Status, &a.SourceType, &a.FetchError, &a.RetryCount,
		&a.IsFavorite, &a.IsArchived, &a.ReadProgress, &a.HighlightCount, &a.LastReadAt, &a.PublishedAt,
		&a.CreatedAt, &a.UpdatedAt, &a.DeletedAt, &a.SemanticKeywords,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get article: %w", err)
	}
	if keyPointsJSON != nil {
		if err := json.Unmarshal(keyPointsJSON, &a.KeyPoints); err != nil {
			return nil, fmt.Errorf("unmarshal key_points: %w", err)
		}
	}
	if a.KeyPoints == nil {
		a.KeyPoints = []string{}
	}
	if a.SemanticKeywords == nil {
		a.SemanticKeywords = []string{}
	}
	return &a, nil
}

type ListArticlesParams struct {
	UserID       string
	Category     *string
	Status       *domain.ArticleStatus
	Favorite     *bool
	UpdatedSince *time.Time
	Page         int
	PerPage      int
}

type ListArticlesResult struct {
	Articles []domain.Article `json:"data"`
	Total    int              `json:"total"`
}

func (r *ArticleRepo) ListByUser(ctx context.Context, p ListArticlesParams) (*ListArticlesResult, error) {
	offset := (p.Page - 1) * p.PerPage

	// When using updated_since (incremental sync), include soft-deleted articles
	// so the client can learn about deletions. Otherwise, filter them out.
	includeDeleted := p.UpdatedSince != nil

	// Count
	countQuery := `SELECT COUNT(*) FROM articles WHERE user_id = $1`
	args := []any{p.UserID}
	argIdx := 2

	if !includeDeleted {
		countQuery += ` AND deleted_at IS NULL`
	}
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
	if p.UpdatedSince != nil {
		countQuery += fmt.Sprintf(` AND updated_at > $%d`, argIdx)
		args = append(args, *p.UpdatedSince)
		argIdx++
	}

	var total int
	if err := r.pool.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, fmt.Errorf("count articles: %w", err)
	}

	// Query
	query := `SELECT id, user_id, url, title, summary, cover_image_url, site_name,
	                 source_type, category_id, word_count, is_favorite, is_archived,
	                 read_progress, status, created_at, updated_at, deleted_at
	          FROM articles WHERE user_id = $1`
	queryArgs := []any{p.UserID}
	qArgIdx := 2

	if !includeDeleted {
		query += ` AND deleted_at IS NULL`
	}
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
	if p.UpdatedSince != nil {
		query += fmt.Sprintf(` AND updated_at > $%d`, qArgIdx)
		queryArgs = append(queryArgs, *p.UpdatedSince)
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
			&a.UpdatedAt, &a.DeletedAt,
		); err != nil {
			return nil, fmt.Errorf("scan article: %w", err)
		}
		a.KeyPoints = []string{}
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
	wordCount := CountWords(cr.Markdown)
	_, err := r.pool.Exec(ctx, `
		UPDATE articles SET
			title = COALESCE(NULLIF($1, ''), title),
			author = COALESCE(NULLIF($2, ''), author),
			site_name = COALESCE(NULLIF($3, ''), site_name),
			markdown_content = COALESCE(NULLIF($4, ''), markdown_content),
			cover_image_url = COALESCE(NULLIF($5, ''), cover_image_url),
			language = COALESCE(NULLIF($6, ''), language),
			favicon_url = COALESCE(NULLIF($7, ''), favicon_url),
			word_count = CASE WHEN NULLIF($4, '') IS NOT NULL THEN $8 ELSE word_count END
		WHERE id = $9`,
		truncateUTF8(cr.Title, 500), truncateUTF8(cr.Author, 200), truncateUTF8(cr.SiteName, 200), cr.Markdown,
		truncateUTF8(cr.CoverImage, 500), truncateUTF8(cr.Language, 10), truncateUTF8(cr.FaviconURL, 500), wordCount, id)
	if err != nil {
		return fmt.Errorf("update crawl result: %w", err)
	}
	return nil
}

// isCJK reports whether r is a CJK ideograph or fullwidth character.
func isCJK(r rune) bool {
	return unicode.Is(unicode.Han, r) ||
		unicode.Is(unicode.Hangul, r) ||
		unicode.Is(unicode.Katakana, r) ||
		unicode.Is(unicode.Hiragana, r)
}

// CountWords counts words in text. CJK characters are counted individually;
// non-CJK runs are counted by whitespace-separated tokens.
func CountWords(text string) int {
	count := 0
	var nonCJK strings.Builder
	for _, r := range text {
		if isCJK(r) {
			// Flush any accumulated non-CJK text as space-separated words
			if nonCJK.Len() > 0 {
				count += len(strings.Fields(nonCJK.String()))
				nonCJK.Reset()
			}
			count++
		} else {
			nonCJK.WriteRune(r)
		}
	}
	// Flush remaining non-CJK text
	if nonCJK.Len() > 0 {
		count += len(strings.Fields(nonCJK.String()))
	}
	return count
}

// truncateUTF8 truncates s to at most maxLen runes.
func truncateUTF8(s string, maxLen int) string {
	runes := []rune(s)
	if len(runes) <= maxLen {
		return s
	}
	return string(runes[:maxLen])
}

func (r *ArticleRepo) UpdateTitle(ctx context.Context, articleID string, title string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE articles SET title = $1, updated_at = NOW() WHERE id = $2`,
		title, articleID)
	return err
}

type AIResult struct {
	CategoryID       string
	Summary          string
	KeyPoints        []string
	Confidence       float64
	Language         string
	SemanticKeywords []string
}

func (r *ArticleRepo) UpdateAIResult(ctx context.Context, id string, ai AIResult) error {
	kp := ai.KeyPoints
	if kp == nil {
		kp = []string{}
	}
	keyPointsJSON, _ := json.Marshal(kp)
	sk := ai.SemanticKeywords
	if sk == nil {
		sk = []string{}
	}
	_, err := r.pool.Exec(ctx, `
		UPDATE articles SET
			category_id = $1,
			summary = $2, key_points = $3, ai_confidence = $4, language = $5,
			semantic_keywords = $6,
			status = 'ready'
		WHERE id = $7`,
		ai.CategoryID, ai.Summary, keyPointsJSON, ai.Confidence, ai.Language, sk, id)
	if err != nil {
		return fmt.Errorf("update ai result: %w", err)
	}
	return nil
}

func (r *ArticleRepo) UpdateMarkdownContent(ctx context.Context, id string, markdown string) error {
	wordCount := CountWords(markdown)
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

func (r *ArticleRepo) Update(ctx context.Context, id string, userID string, p UpdateArticleParams) error {
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
	query := fmt.Sprintf("UPDATE articles SET %s WHERE id = $%d AND user_id = $%d", setClauses, argIdx, argIdx+1)
	args = append(args, id, userID)

	_, err := r.pool.Exec(ctx, query, args...)
	if err != nil {
		return fmt.Errorf("update article: %w", err)
	}
	return nil
}

func (r *ArticleRepo) ExistsByUserAndURL(ctx context.Context, userID, url string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM articles WHERE user_id = $1 AND url = $2 AND deleted_at IS NULL)`,
		userID, url).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check article exists: %w", err)
	}
	return exists, nil
}

func (r *ArticleRepo) Delete(ctx context.Context, id string, userID string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE articles SET deleted_at = NOW() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		id, userID)
	if err != nil {
		return fmt.Errorf("soft delete article: %w", err)
	}
	return nil
}

// BroadRecallArticles does multi-path keyword recall returning full Article objects for semantic search.
func (r *ArticleRepo) BroadRecallArticles(ctx context.Context, userID string, keywords []string, limit int) ([]domain.Article, error) {
	cleaned := make([]string, len(keywords))
	escaped := make([]string, len(keywords))
	for i, kw := range keywords {
		lc := strings.ToLower(strings.TrimSpace(kw))
		cleaned[i] = lc
		escaped[i] = strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(lc)
	}

	// Set low trigram threshold for broad recall
	_, _ = r.pool.Exec(ctx, `SELECT set_config('pg_trgm.similarity_threshold', '0.1', true)`)

	rows, err := r.pool.Query(ctx, `
		WITH keyword_matches AS (
			SELECT DISTINCT ON (a.id)
				a.id, a.user_id, a.url, a.title, a.summary, a.site_name, a.source_type, a.created_at,
				CASE
					WHEN a.semantic_keywords && $2::text[] THEN 1.0
					WHEN EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw) THEN 0.6
					ELSE 0.1
				END AS score
			FROM articles a
			WHERE a.user_id = $1
				AND a.status = 'ready'
				AND a.deleted_at IS NULL
				AND (
					a.semantic_keywords && $2::text[]
					OR EXISTS (SELECT 1 FROM unnest($2::text[]) kw WHERE a.title % kw)
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.summary ILIKE '%' || esc || '%')
					OR EXISTS (SELECT 1 FROM unnest($3::text[]) esc WHERE a.key_points::text ILIKE '%' || esc || '%')
				)
			ORDER BY a.id, score DESC
		)
		SELECT id, user_id, url, title, summary, site_name, source_type, created_at
		FROM keyword_matches
		ORDER BY score DESC
		LIMIT $4`,
		userID, cleaned, escaped, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("broad recall articles: %w", err)
	}
	defer rows.Close()

	articles := make([]domain.Article, 0)
	for rows.Next() {
		var a domain.Article
		if err := rows.Scan(&a.ID, &a.UserID, &a.URL, &a.Title, &a.Summary,
			&a.SiteName, &a.SourceType, &a.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan broad recall article: %w", err)
		}
		a.KeyPoints = []string{}
		articles = append(articles, a)
	}
	return articles, rows.Err()
}

func (r *ArticleRepo) Search(ctx context.Context, userID, query string, page, perPage int) (*ListArticlesResult, error) {
	offset := (page - 1) * perPage
	escaped := strings.NewReplacer("%", "\\%", "_", "\\_").Replace(query)
	pattern := "%" + escaped + "%"

	var total int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM articles WHERE user_id = $1 AND deleted_at IS NULL AND (
			title ILIKE $2 OR summary ILIKE $2 OR author ILIKE $2 OR site_name ILIKE $2
		)`,
		userID, pattern,
	).Scan(&total)
	if err != nil {
		return nil, fmt.Errorf("count search: %w", err)
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, user_id, url, title, summary, site_name, source_type, created_at
		FROM articles WHERE user_id = $1 AND deleted_at IS NULL AND (
			title ILIKE $2 OR summary ILIKE $2 OR author ILIKE $2 OR site_name ILIKE $2
		)
		ORDER BY
			CASE WHEN title ILIKE $2 THEN 0 ELSE 1 END,
			created_at DESC
		LIMIT $3 OFFSET $4`,
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
		a.KeyPoints = []string{}
		articles = append(articles, a)
	}

	return &ListArticlesResult{Articles: articles, Total: total}, nil
}
