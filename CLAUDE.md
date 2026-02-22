# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Folio (页集) is a local-first personal knowledge curation iOS app. Users share links from any app (WeChat, Twitter, browsers), and Folio extracts content, auto-classifies, tags, summarizes via AI, and stores everything locally on-device with full-text search.

**Core flow**: Collect → Organize → Find (zero configuration)

**Status**: MVP implementation complete — iOS app (61 source files), Go backend, Reader service, AI service, E2E test suite (17 test files), iOS unit tests (29 test files).

## Repository Structure

```
folio/
├── CLAUDE.md
├── docs/
│   ├── design/prd.md              # PRD: 9 features (F1-F9), subscription tiers
│   ├── architecture/
│   │   ├── system-design.md       # System architecture, data models
│   │   └── api-contract.md        # API contracts
│   ├── interaction/core-flows.md  # UI/UX flows, screen mockups
│   ├── ios-mvp-plan.md            # MVP task breakdown (50 iOS + 22 backend tasks)
│   └── local-deploy.md            # Local deployment guide
├── ios/                           # iOS app
│   ├── project.yml                # XcodeGen project definition
│   ├── Folio.xcodeproj/
│   ├── Folio/                     # Main app target (61 Swift files)
│   ├── ShareExtension/            # Share Extension target
│   ├── FolioTests/                # Unit tests (29 Swift files)
│   └── Shared/                    # Shared code between app & extension
└── server/
    ├── cmd/server/main.go         # Go API + Worker entry point
    ├── internal/                   # Go packages (api, service, repository, worker, client, config, domain)
    ├── migrations/                 # PostgreSQL migrations (001_init.up.sql)
    ├── reader-service/             # Node.js content scraping (TypeScript + Express)
    ├── ai-service/                 # Python AI analysis (FastAPI + DeepSeek)
    ├── tests/e2e/                  # E2E test suite (Python pytest, 17 test files)
    ├── scripts/
    │   ├── dev-start.sh            # One-command local dev startup
    │   ├── run_e2e.sh              # Full E2E test runner
    │   ├── smoke_api_e2e.sh        # Quick API smoke test
    │   └── mock_ai_service.py      # Deterministic mock AI for local testing
    ├── docker-compose.yml          # Production (Caddy + API + Reader + AI + PG + Redis)
    ├── docker-compose.dev.yml      # Dev (PostgreSQL :5432 + Redis :6380 only)
    ├── docker-compose.test.yml     # E2E test (isolated ports 15432/16379)
    ├── Dockerfile                  # Multi-stage Go API build
    ├── Caddyfile                   # Reverse proxy config
    └── .env.example                # Environment variable template
```

## Architecture

Four-tier system:

### 1. iOS Client

- **Stack**: Swift 5.9+ / SwiftUI / SwiftData / SQLite FTS5
- **Pattern**: MVVM + Clean Architecture (Presentation → Domain → Data)
- **Deployment target**: iOS 17.0
- **Xcode**: 16.2, project generated via XcodeGen (`ios/project.yml`)
- **Bundle IDs**: `com.folio.app` (main), `com.folio.app.share-extension`
- **App Group**: `group.com.folio.app` (shared data between app & extension)

**Targets**:
- `Folio` — main app (SwiftUI lifecycle, AppDelegate adapter)
- `ShareExtension` — share sheet entry point (120MB memory limit)
- `FolioTests` — unit tests

**Dependencies** (Swift Package Manager):
- `apple/swift-markdown` ≥ 0.5.0 — Markdown rendering
- `kean/Nuke` ≥ 12.8.0 — Image loading (Nuke + NukeUI)
- `kishikawakatsumi/KeychainAccess` ≥ 4.2.2 — Secure credential storage

**App structure**:
- 3 tabs: Library (HomeView), Search (SearchView), Settings (SettingsView)
- Onboarding flow → Dev Login button available in DEBUG builds
- `APIClient.defaultBaseURL` = `http://localhost:8080` in DEBUG, `https://api.folio.app` in RELEASE
- OfflineQueueManager for pending articles, SyncService for server sync

**Key iOS source paths**:
- `ios/Folio/App/` — FolioApp.swift (entry), MainTabView.swift (tabs), AppDelegate.swift
- `ios/Folio/Presentation/` — Auth/, Home/, Reader/, Search/, Settings/, Onboarding/, Components/
- `ios/Folio/Domain/Models/` — Article, Tag, Category, User value types
- `ios/Folio/Data/SwiftData/` — DataManager.swift, SharedDataManager.swift
- `ios/Folio/Data/Network/` — Network.swift (APIClient + all DTOs), OfflineQueueManager.swift
- `ios/Folio/Data/Search/` — SQLite FTS5 full-text search
- `ios/Folio/Data/Repository/` — Repository pattern abstractions
- `ios/Folio/Data/KeyChain/` — KeyChainManager (token storage)
- `ios/Folio/Data/Sync/` — SyncService (CloudKit + backend sync)

### 2. Go Backend

- **Stack**: Go 1.24+ / chi v5 router / asynq task queue / pgx v5 / JWT
- **Entry point**: `server/cmd/server/main.go` — starts HTTP server + Worker server in single process
- **Pattern**: Handler → Service → Repository → Domain

**API routes** (chi router, `server/internal/api/router.go`):
- `GET /health` — health check
- `POST /api/v1/auth/apple` — Apple Sign In
- `POST /api/v1/auth/refresh` — token refresh
- `POST /api/v1/auth/dev` — dev login (DEV_MODE only)
- `GET /api/v1/articles` — list (paginated, filterable by category/status/favorite)
- `POST /api/v1/articles` — submit URL → creates article + crawl task
- `GET /api/v1/articles/{id}` — detail
- `PUT /api/v1/articles/{id}` — update (favorite, archive, read progress)
- `DELETE /api/v1/articles/{id}` — delete
- `GET /api/v1/articles/search?q=` — full-text search
- `GET /api/v1/tags` — list tags
- `POST /api/v1/tags` — create tag
- `DELETE /api/v1/tags/{id}` — delete tag
- `GET /api/v1/categories` — list categories
- `GET /api/v1/tasks/{id}` — poll task status
- `POST /api/v1/subscription/verify` — verify subscription

**Middleware**: JWT auth (`server/internal/api/middleware/auth.go`) — extracts userID into request context.

**Worker tasks** (asynq, Redis-backed, `server/internal/worker/`):
1. `article:crawl` — calls Reader service, stores markdown, enqueues AI task (Critical queue, 3 retries, 90s timeout)
2. `article:ai` — calls AI service, stores classification/tags/summary (Default queue, 3 retries, 60s timeout)
3. `article:images` — rehosts images to R2 (Low queue, 2 retries, 5min timeout)

**External clients** (`server/internal/client/`):
- `reader.go` — Reader service HTTP client
- `ai.go` — AI service HTTP client
- `r2.go` — Cloudflare R2 S3-compatible client (optional)

**Configuration** (`server/internal/config/config.go`):

| Env var | Required | Default | Description |
|---------|----------|---------|-------------|
| `DATABASE_URL` | yes | — | PostgreSQL connection string |
| `JWT_SECRET` | yes | — | JWT signing key |
| `PORT` | no | 8080 | HTTP port |
| `REDIS_ADDR` | no | localhost:6379 | Redis address (dev uses 6380, see docker-compose.dev.yml) |
| `READER_URL` | no | http://localhost:3000 | Reader service URL |
| `AI_SERVICE_URL` | no | http://localhost:8000 | AI service URL |
| `DEV_MODE` | no | false | Enables /auth/dev endpoint |
| `R2_ENDPOINT` | no | — | Cloudflare R2 endpoint |
| `R2_ACCESS_KEY` | no | — | R2 access key |
| `R2_SECRET_KEY` | no | — | R2 secret key |
| `R2_BUCKET_NAME` | no | folio-images | R2 bucket name |
| `R2_PUBLIC_URL` | no | — | R2 public URL prefix |

### 3. Reader Service

- **Stack**: Node.js / TypeScript / Express / `@vakra-dev/reader`
- **Location**: `server/reader-service/`
- **Endpoints**: `POST /scrape` (url → markdown + metadata), `GET /health`
- **Local dependency**: `@vakra-dev/reader` linked via `file:../../../reader` (requires `/Users/mac/github/reader` to exist with `dist/` built)
- **Updating reader**: When the reader library at `/Users/mac/github/reader` is updated, run `cd /Users/mac/github/reader && npm run build` to rebuild, then `cd server/reader-service && rm -rf node_modules/@vakra-dev && npm install` to pick up the new version, and restart the reader service.
- **Dev command**: `npm run dev` (uses tsx), **Build**: `npm run build` (tsc → dist/)

### 4. AI Service

- **Stack**: Python 3.12+ / FastAPI / DeepSeek API (via openai SDK)
- **Location**: `server/ai-service/`
- **Endpoints**: `POST /api/analyze` (title + content + source + author → analysis), `GET /health`
- **Model**: `deepseek-chat`, temperature=0.3, max_tokens=1024, JSON output format
- **Dependencies**: `server/ai-service/requirements.txt` (fastapi, uvicorn, openai, redis, pydantic, pytest, httpx)
- **Env**: `DEEPSEEK_API_KEY` (required), `REDIS_URL` (optional, for caching)
- **Mock for local dev**: `server/scripts/mock_ai_service.py` — deterministic responses based on URL patterns, no API key needed

**9 categories**: tech, business, science, culture, lifestyle, news, education, design, other

**Single API call returns**: category (slug + name), confidence (0-1), tags (3-5), summary, key_points (3-5), language (zh/en)

## Database

PostgreSQL 16 with migrations at `server/migrations/001_init.up.sql`.

**Tables**: users, categories (9 pre-inserted), articles, tags, article_tags, crawl_tasks, activity_logs

**Extensions**: uuid-ossp, pg_trgm (trigram full-text search)

**Key constraints**:
- articles: unique (user_id, url) — no duplicate URLs per user
- tags: unique (user_id, name)
- articles.status: pending → processing → ready | failed
- crawl_tasks.status: queued → running → done | failed
- users.subscription: free | pro | pro+, monthly_quota default 30

## Local Development

**IMPORTANT — Database access**: `psql` is NOT installed on the host machine. PostgreSQL runs inside Docker. Always use `docker exec` to run database commands:
```bash
# Dev database (docker-compose.dev.yml)
docker exec $(docker ps --filter "publish=5432" -q) psql -U folio -d folio -c "YOUR SQL HERE"

# E2E test database (docker-compose.test.yml)
docker exec $(docker ps --filter "publish=15432" -q) psql -U folio -d folio -c "YOUR SQL HERE"
```
Similarly, `redis-cli` is not available on the host. Use `docker exec` for Redis access as well.

**One-command startup**:

```bash
cd server && ./scripts/dev-start.sh
```

This automatically: checks/installs Go 1.24 via gvm, starts PostgreSQL (:5432) + Redis (:6380) via Docker, builds reader local dependency if needed, starts Reader (:3000) + Mock AI (:8000) + Go API (:8080, DEV_MODE=true), opens Xcode.

**Dev ports**:
- Go API: 8080
- Reader: 3000
- Mock AI: 8000
- PostgreSQL: 5432 (user: folio, password: folio, db: folio)
- Redis: 6380 (note: NOT 6379, mapped in docker-compose.dev.yml)

**iOS in simulator**: Cmd+R in Xcode → tap "Dev Login" button (DEBUG builds only) → test features.

**Stopping**: Ctrl+C in script terminal (stops Reader/AI/Go), then `docker compose -f docker-compose.dev.yml down` for DB/Redis.

See `docs/local-deploy.md` for full details.

## Testing

**iOS unit tests** (29 files in `ios/FolioTests/`):
```bash
xcodebuild test -project ios/Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

**E2E tests** (17 test files in `server/tests/e2e/`, Python pytest):
```bash
cd server && ./scripts/run_e2e.sh
```
Uses isolated docker-compose.test.yml (PostgreSQL :15432, Redis :16379, API :18080, Reader :13000, AI :18000). Reports generated in `server/tests/e2e/reports/`.

**Quick smoke test**:
```bash
cd server && ./scripts/smoke_api_e2e.sh
```

## Key Design Decisions

- **Local-first**: All user content stored on device; only AI processing content sent to server
- **Offline-first save**: Share Extension writes URL + metadata to local SwiftData immediately, backend processing happens async when network available
- **Single AI call**: Classification + tags + summary extracted in one DeepSeek API request for efficiency
- **AI model**: DeepSeek Chat (deepseek-chat) for classification/summarization; confidence threshold at 70%
- **Content sources prioritized**: P0 = blogs, WeChat public accounts, Twitter/X; P1 = Zhihu, Weibo; P2 = newsletters, YouTube
- **WeChat special handling**: proxy scraping, anti-hotlink image rehosting
- **Subscription tiers**: Free (30 saves/month), Pro ($68/yr), Pro+ ($128/yr)
- **Not-to-do list**: No notes editor, no batch editing, no multi-level folders, no RSS, no social features, no recommendations

## Build Commands

| What | Command |
|------|---------|
| Go server (dev) | `cd server && go run ./cmd/server` |
| Go server (build) | `cd server && go build -o folio-server ./cmd/server` |
| Reader service (dev) | `cd server/reader-service && npm run dev` |
| Reader service (build) | `cd server/reader-service && npm run build && npm start` |
| AI service | `cd server/ai-service && uvicorn app.main:app --port 8000` |
| Mock AI service | `python3 server/scripts/mock_ai_service.py` |
| iOS (Xcode) | Open `ios/Folio.xcodeproj`, scheme Folio, Cmd+R |
| iOS (CLI build) | `xcodebuild build -project ios/Folio.xcodeproj -scheme Folio -destination 'generic/platform=iOS Simulator'` |
| XcodeGen regenerate | `cd ios && xcodegen generate` |
| Docker prod stack | `cd server && docker compose up -d` |
| Docker dev infra | `cd server && docker compose -f docker-compose.dev.yml up -d` |

## Language & i18n

Documentation is in Chinese. The product targets global users (Chinese + English bilingual). AI output language matches the article's language. iOS app localized for en + zh-Hans.
