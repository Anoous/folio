package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"folio-server/internal/domain"
)

type CategoryRepo struct {
	pool *pgxpool.Pool
}

func NewCategoryRepo(pool *pgxpool.Pool) *CategoryRepo {
	return &CategoryRepo{pool: pool}
}

func (r *CategoryRepo) ListAll(ctx context.Context) ([]domain.Category, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, slug, name_zh, name_en, icon, sort_order, created_at
		 FROM categories ORDER BY sort_order`)
	if err != nil {
		return nil, fmt.Errorf("list categories: %w", err)
	}
	defer rows.Close()

	categories := make([]domain.Category, 0)
	for rows.Next() {
		var c domain.Category
		if err := rows.Scan(&c.ID, &c.Slug, &c.NameZH, &c.NameEN, &c.Icon, &c.SortOrder, &c.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan category: %w", err)
		}
		categories = append(categories, c)
	}
	return categories, nil
}

func (r *CategoryRepo) GetByID(ctx context.Context, id string) (*domain.Category, error) {
	var c domain.Category
	err := r.pool.QueryRow(ctx,
		`SELECT id, slug, name_zh, name_en, icon, sort_order, created_at
		 FROM categories WHERE id = $1`, id,
	).Scan(&c.ID, &c.Slug, &c.NameZH, &c.NameEN, &c.Icon, &c.SortOrder, &c.CreatedAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get category by id: %w", err)
	}
	return &c, nil
}

func (r *CategoryRepo) GetBySlug(ctx context.Context, slug string) (*domain.Category, error) {
	var c domain.Category
	err := r.pool.QueryRow(ctx,
		`SELECT id, slug, name_zh, name_en, icon, sort_order, created_at
		 FROM categories WHERE slug = $1`, slug,
	).Scan(&c.ID, &c.Slug, &c.NameZH, &c.NameEN, &c.Icon, &c.SortOrder, &c.CreatedAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get category: %w", err)
	}
	return &c, nil
}
