-- 001_init.down.sql — 回滚初始数据库结构

DROP TRIGGER IF EXISTS tr_crawl_tasks_updated_at ON crawl_tasks;
DROP TRIGGER IF EXISTS tr_articles_updated_at ON articles;
DROP TRIGGER IF EXISTS tr_users_updated_at ON users;
DROP FUNCTION IF EXISTS update_updated_at();

DROP TABLE IF EXISTS activity_logs;
DROP TABLE IF EXISTS crawl_tasks;
DROP TABLE IF EXISTS article_tags;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS articles;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS users;

DROP EXTENSION IF EXISTS "pg_trgm";
DROP EXTENSION IF EXISTS "uuid-ossp";
