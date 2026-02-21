# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Folio (页集) is a local-first personal knowledge curation iOS app. Users share links from any app (WeChat, Twitter, browsers), and Folio extracts content, auto-classifies, tags, summarizes via AI, and stores everything locally on-device with full-text search.

**Core flow**: Collect → Organize → Find (zero configuration)

**Status**: Design specification phase — comprehensive docs exist, no implementation code yet.

## Documentation Structure

- `docs/design/prd.md` — Full PRD: 9 features (F1-F9), content source strategies, AI specs, subscription tiers, acceptance criteria
- `docs/architecture/system-design.md` — System architecture, tech stack, API design, data models, deployment
- `docs/interaction/core-flows.md` — UI/UX flows, navigation, gesture system, screen mockups

## Architecture

Four-tier system:

1. **iOS Client** (Swift 5.9+ / SwiftUI / SwiftData / SQLite FTS5 / CloudKit)
   - MVVM + Clean Architecture (Presentation → Domain → Data layers)
   - Share Extension as primary entry point (120MB memory limit, App Group shared storage)
   - Local-first: all data persisted on-device, server results sync back
2. **Go Backend** (Go 1.22+ / chi router / asynq task queue / pgx)
   - API layer (auth, articles, search, tags) + async Worker layer + Service layer
   - JWT auth, rate limiting via Caddy gateway
3. **Reader Service** (@vakra-dev/reader) — multi-engine cascade scraping (HTTP→TLS→Browser), HTML→Markdown, anti-scraping bypass
4. **AI Service** (Python 3.12+ / FastAPI / Claude API) — classification, tagging, summarization in a single API call

**Data layer**: PostgreSQL (relational data), Redis (task queue + cache), Cloudflare R2 (images)

## Key Design Decisions

- **Local-first**: All user content stored on device; only AI processing content sent to server
- **Offline-first save**: Share Extension writes URL + metadata to local SwiftData immediately, backend processing happens async when network available
- **Single AI call**: Classification + tags + summary extracted in one Claude API request for efficiency
- **AI model**: Claude claude-sonnet-4-5 for classification/summarization; confidence threshold at 70%
- **Content sources prioritized**: P0 = blogs, WeChat public accounts, Twitter/X; P1 = Zhihu, Weibo; P2 = newsletters, YouTube
- **WeChat special handling**: proxy scraping, anti-hotlink image rehosting
- **Subscription tiers**: Free (30 saves/month), Pro ($68/yr), Pro+ ($128/yr)
- **Not-to-do list**: No notes editor, no batch editing, no multi-level folders, no RSS, no social features, no recommendations

## Language & i18n

Documentation is in Chinese. The product targets global users (Chinese + English bilingual). AI output language should match the article's language.
