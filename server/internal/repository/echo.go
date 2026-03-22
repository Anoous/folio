package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type EchoRepo struct {
	db *pgxpool.Pool
}

func NewEchoRepo(db *pgxpool.Pool) *EchoRepo {
	return &EchoRepo{db: db}
}

// CreateCard inserts a new echo card.
func (r *EchoRepo) CreateCard(ctx context.Context, card *domain.EchoCard) error {
	err := r.db.QueryRow(ctx, `
		INSERT INTO echo_cards (
			id, user_id, article_id, card_type, question, answer, source_context,
			next_review_at, interval_days, ease_factor, review_count, correct_count,
			related_article_id, highlight_id, created_at, updated_at
		) VALUES (
			COALESCE(NULLIF($1, '')::uuid, uuid_generate_v4()),
			$2::uuid, $3::uuid, $4, $5, $6, $7,
			$8, $9, $10, $11, $12,
			$13, $14, NOW(), NOW()
		)
		RETURNING id, created_at, updated_at`,
		card.ID, card.UserID, card.ArticleID, card.CardType, card.Question, card.Answer, card.SourceContext,
		card.NextReviewAt, card.IntervalDays, card.EaseFactor, card.ReviewCount, card.CorrectCount,
		card.RelatedArticleID, card.HighlightID,
	).Scan(&card.ID, &card.CreatedAt, &card.UpdatedAt)
	if err != nil {
		return fmt.Errorf("create echo card: %w", err)
	}
	return nil
}

// GetDueCards returns cards where next_review_at <= now for a user,
// joined with articles to get article title. Ordered by next_review_at ASC.
func (r *EchoRepo) GetDueCards(ctx context.Context, userID string, limit int) ([]domain.EchoCard, error) {
	rows, err := r.db.Query(ctx, `
		SELECT
			ec.id, ec.user_id, ec.article_id, ec.card_type, ec.question, ec.answer, ec.source_context,
			ec.next_review_at, ec.interval_days, ec.ease_factor, ec.review_count, ec.correct_count,
			ec.related_article_id, ec.highlight_id, ec.created_at, ec.updated_at,
			COALESCE(a.title, '') AS article_title
		FROM echo_cards ec
		LEFT JOIN articles a ON ec.article_id = a.id
		WHERE ec.user_id = $1
		  AND ec.next_review_at <= NOW()
		ORDER BY ec.next_review_at ASC
		LIMIT $2`,
		userID, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("query due cards: %w", err)
	}
	defer rows.Close()

	cards := make([]domain.EchoCard, 0)
	for rows.Next() {
		var c domain.EchoCard
		if err := rows.Scan(
			&c.ID, &c.UserID, &c.ArticleID, &c.CardType, &c.Question, &c.Answer, &c.SourceContext,
			&c.NextReviewAt, &c.IntervalDays, &c.EaseFactor, &c.ReviewCount, &c.CorrectCount,
			&c.RelatedArticleID, &c.HighlightID, &c.CreatedAt, &c.UpdatedAt,
			&c.ArticleTitle,
		); err != nil {
			return nil, fmt.Errorf("scan due card: %w", err)
		}
		cards = append(cards, c)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate due cards: %w", err)
	}
	return cards, nil
}

// GetCardByID returns a single card, verifying user ownership.
func (r *EchoRepo) GetCardByID(ctx context.Context, cardID, userID string) (*domain.EchoCard, error) {
	var c domain.EchoCard
	err := r.db.QueryRow(ctx, `
		SELECT
			ec.id, ec.user_id, ec.article_id, ec.card_type, ec.question, ec.answer, ec.source_context,
			ec.next_review_at, ec.interval_days, ec.ease_factor, ec.review_count, ec.correct_count,
			ec.related_article_id, ec.highlight_id, ec.created_at, ec.updated_at,
			COALESCE(a.title, '') AS article_title
		FROM echo_cards ec
		LEFT JOIN articles a ON ec.article_id = a.id
		WHERE ec.id = $1 AND ec.user_id = $2`,
		cardID, userID,
	).Scan(
		&c.ID, &c.UserID, &c.ArticleID, &c.CardType, &c.Question, &c.Answer, &c.SourceContext,
		&c.NextReviewAt, &c.IntervalDays, &c.EaseFactor, &c.ReviewCount, &c.CorrectCount,
		&c.RelatedArticleID, &c.HighlightID, &c.CreatedAt, &c.UpdatedAt,
		&c.ArticleTitle,
	)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get echo card: %w", err)
	}
	return &c, nil
}

// UpdateCard updates SM-2 fields: interval_days, ease_factor, next_review_at,
// review_count, correct_count, updated_at.
func (r *EchoRepo) UpdateCard(ctx context.Context, card *domain.EchoCard) error {
	_, err := r.db.Exec(ctx, `
		UPDATE echo_cards SET
			interval_days    = $1,
			ease_factor      = $2,
			next_review_at   = $3,
			review_count     = $4,
			correct_count    = $5,
			updated_at       = NOW()
		WHERE id = $6 AND user_id = $7`,
		card.IntervalDays, card.EaseFactor, card.NextReviewAt,
		card.ReviewCount, card.CorrectCount,
		card.ID, card.UserID,
	)
	if err != nil {
		return fmt.Errorf("update echo card: %w", err)
	}
	return nil
}

// CreateReview inserts an echo_reviews record.
func (r *EchoRepo) CreateReview(ctx context.Context, review *domain.EchoReview) error {
	err := r.db.QueryRow(ctx, `
		INSERT INTO echo_reviews (id, card_id, user_id, result, response_time_ms, reviewed_at)
		VALUES (
			COALESCE(NULLIF($1, ''), uuid_generate_v4()::text),
			$2, $3, $4, $5, COALESCE($6, NOW())
		)
		RETURNING id, reviewed_at`,
		review.ID, review.CardID, review.UserID, review.Result, review.ResponseTimeMs, review.ReviewedAt,
	).Scan(&review.ID, &review.ReviewedAt)
	if err != nil {
		return fmt.Errorf("create echo review: %w", err)
	}
	return nil
}

// GetWeeklyStats returns (remembered_count, total_count) for echo_reviews
// this week (since Monday 00:00 UTC).
func (r *EchoRepo) GetWeeklyStats(ctx context.Context, userID string) (remembered, total int, err error) {
	// Calculate Monday 00:00 UTC of the current week
	now := time.Now().UTC()
	weekday := int(now.Weekday())
	if weekday == 0 {
		weekday = 7 // treat Sunday as day 7
	}
	daysBack := weekday - 1 // days since Monday
	monday := time.Date(now.Year(), now.Month(), now.Day()-daysBack, 0, 0, 0, 0, time.UTC)

	err = r.db.QueryRow(ctx, `
		SELECT
			COUNT(*) FILTER (WHERE result = $1) AS remembered_count,
			COUNT(*) AS total_count
		FROM echo_reviews
		WHERE user_id = $2
		  AND reviewed_at >= $3`,
		string(domain.EchoRemembered), userID, monday,
	).Scan(&remembered, &total)
	if err != nil {
		return 0, 0, fmt.Errorf("get weekly stats: %w", err)
	}
	return remembered, total, nil
}

// GetConsecutiveDays returns number of consecutive days with at least one review,
// counting back from today.
func (r *EchoRepo) GetConsecutiveDays(ctx context.Context, userID string) (int, error) {
	// Get distinct review dates in descending order, then count consecutive days
	// starting from today (or yesterday if none today).
	rows, err := r.db.Query(ctx, `
		SELECT DISTINCT DATE(reviewed_at AT TIME ZONE 'UTC') AS review_date
		FROM echo_reviews
		WHERE user_id = $1
		ORDER BY review_date DESC
		LIMIT 365`,
		userID,
	)
	if err != nil {
		return 0, fmt.Errorf("query consecutive days: %w", err)
	}
	defer rows.Close()

	var dates []time.Time
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return 0, fmt.Errorf("scan review date: %w", err)
		}
		dates = append(dates, d)
	}
	if err := rows.Err(); err != nil {
		return 0, fmt.Errorf("iterate review dates: %w", err)
	}

	if len(dates) == 0 {
		return 0, nil
	}

	today := time.Now().UTC().Truncate(24 * time.Hour)
	consecutive := 0

	for i, d := range dates {
		day := d.Truncate(24 * time.Hour)
		expected := today.AddDate(0, 0, -i)
		if day.Equal(expected) {
			consecutive++
		} else {
			break
		}
	}

	// If no review today, check if there was one yesterday and count from there
	if consecutive == 0 {
		yesterday := today.AddDate(0, 0, -1)
		for i, d := range dates {
			day := d.Truncate(24 * time.Hour)
			expected := yesterday.AddDate(0, 0, -i)
			if day.Equal(expected) {
				consecutive++
			} else {
				break
			}
		}
	}

	return consecutive, nil
}

// CountCardsByArticle returns count of echo_cards for a given article.
func (r *EchoRepo) CountCardsByArticle(ctx context.Context, articleID string) (int, error) {
	var count int
	err := r.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM echo_cards WHERE article_id = $1`,
		articleID,
	).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("count cards by article: %w", err)
	}
	return count, nil
}

// GetUserEchoQuota returns echo_count_this_week and echo_week_reset_at for a user.
func (r *EchoRepo) GetUserEchoQuota(ctx context.Context, userID string) (count int, resetAt *time.Time, err error) {
	err = r.db.QueryRow(ctx,
		`SELECT echo_count_this_week, echo_week_reset_at FROM users WHERE id = $1`,
		userID,
	).Scan(&count, &resetAt)
	if err != nil {
		return 0, nil, fmt.Errorf("get user echo quota: %w", err)
	}
	return count, resetAt, nil
}

// ResetEchoWeekCount resets echo_count_this_week to 0 and sets echo_week_reset_at to nextReset.
func (r *EchoRepo) ResetEchoWeekCount(ctx context.Context, userID string, nextReset time.Time) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET echo_count_this_week = 0, echo_week_reset_at = $1 WHERE id = $2`,
		nextReset, userID,
	)
	if err != nil {
		return fmt.Errorf("reset echo week count: %w", err)
	}
	return nil
}

// IncrementEchoWeekCount increments echo_count_this_week by 1.
func (r *EchoRepo) IncrementEchoWeekCount(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx,
		`UPDATE users SET echo_count_this_week = echo_count_this_week + 1 WHERE id = $1`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("increment echo week count: %w", err)
	}
	return nil
}
