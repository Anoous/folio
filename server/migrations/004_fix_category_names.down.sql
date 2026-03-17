-- 004_fix_category_names.down.sql — Revert category names to original values

UPDATE categories SET name_zh = '时事' WHERE slug = 'news' AND name_zh = '新闻';
UPDATE categories SET name_zh = '学习' WHERE slug = 'education' AND name_zh = '教育';
