package domain

import "time"

type Category struct {
	ID        string    `json:"id"`
	Slug      string    `json:"slug"`
	NameZH    string    `json:"name_zh"`
	NameEN    string    `json:"name_en"`
	Icon      *string   `json:"icon,omitempty"`
	SortOrder int       `json:"sort_order"`
	CreatedAt time.Time `json:"created_at"`
}
