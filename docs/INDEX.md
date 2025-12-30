# FuzzyRSS Implementation Plan - Documentation Index

## Overview
Build a modern RSS aggregator similar to FreshRSS with multi-user support, feed management, article filtering/search, PWA capabilities, and REST API.

**Target Features:**
- Feed subscription & management (OPML import/export)
- Multi-user authentication
- Article filtering & search (read/unread/starred)
- Background feed updates (Oban)
- Mobile-friendly PWA
- REST/JSON API
- Full-text article extraction
- Custom UI/UX with daisyUI

---

## Implementation Phases

Each phase builds on the previous one. Follow them in order.

### [Phase 1: Dependencies & Authentication](PHASE_1_DEPENDENCIES_AND_AUTH.md) - Week 1
- Update `mix.exs` for multi-database support
- Configure database selection via environment variables
- Generate and customize authentication scaffold
- **Estimated time:** 2-3 days

### [Phase 2: Database Schema](PHASE_2_DATABASE_SCHEMA.md) - Week 1-2
- Create core migrations (Oban, folders, feeds, entries, subscriptions, user states)
- Create Ecto schemas for all entities
- Set up database-specific indexes
- **Estimated time:** 2-3 days

### [Phase 3: Phoenix Contexts](PHASE_3_PHOENIX_CONTEXTS.md) - Week 2
- Build Content context with all CRUD functions
- Implement feed, folder, and entry management
- Add entry filtering and search logic
- **Estimated time:** 3-4 days

### [Phase 4: Feed Processing](PHASE_4_FEED_PROCESSING.md) - Week 2-3
- Create feed services (fetcher, parser, discoverer, extractor)
- Implement OPML import/export for subscriptions
- Implement FreshRSS JSON import/export for starred articles
- Set up Oban background jobs
- Implement feed scheduling and worker jobs
- **Estimated time:** 3-4 days

### [Phase 5: LiveView UI](PHASE_5_LIVEVIEW_UI.md) - Week 3-4
- Update router with authenticated routes
- Build main reader interface LiveView
- Create feed management and settings LiveViews
- Add import/export settings UI (OPML & FreshRSS JSON)
- Add enhanced CoreComponents
- **Estimated time:** 4-5 days

### [Phase 6: PWA Features](PHASE_6_PWA_FEATURES.md) - Week 5
- Create web app manifest
- Build service worker for offline support
- Implement mobile-responsive UI
- **Estimated time:** 2 days

### [Phase 7: REST API](PHASE_7_REST_API.md) - Week 6
- Set up API pipeline with JWT authentication
- Create API controllers for feeds and entries
- Implement OPML import/export API endpoints
- Implement FreshRSS JSON import/export API endpoints
- **Estimated time:** 2-3 days

### [Phase 8: Search & Polish](PHASE_8_SEARCH_AND_POLISH.md) - Week 7-8
- Implement database-agnostic full-text search
- Add keyboard shortcuts
- Implement UX enhancements (loading states, animations)
- **Estimated time:** 2-3 days

### [Phase 9: Testing & Deployment](PHASE_9_TESTING_AND_DEPLOYMENT.md) - Week 9
- Write comprehensive tests (unit, integration, E2E)
- Configure production environment
- Set up Docker and deployment
- **Estimated time:** 3-4 days

---

## Infrastructure & DevOps

### [Multi-Database & Docker Deployment](MULTI_DATABASE_DOCKER.md)
- Dockerfile supporting PostgreSQL, MySQL, and SQLite
- Docker Compose configurations for each database
- Running locally with different database backends
- Database-specific considerations

### Import/Export Features
- **Phase 4**: OPML and FreshRSS JSON services for parsing and exporting
- **Phase 5**: LiveView UI for file upload/download in settings
- **Phase 7**: REST API endpoints for import/export operations

---

## Quick Reference

### Critical Files to Create/Modify

1. **`lib/fuzzy_rss/content.ex`** - Core business logic context
2. **`lib/fuzzy_rss_web/live/reader_live/index.ex`** - Main reader interface
3. **`lib/fuzzy_rss/workers/feed_fetcher_worker.ex`** - Background feed fetching
4. **`lib/fuzzy_rss/feeds/parser.ex`** - RSS/Atom parsing service
5. **`priv/repo/migrations/*`** - Database schema migrations
6. **`lib/fuzzy_rss_web/router.ex`** - Authenticated routes + API routes
7. **`lib/fuzzy_rss/feeds/fetcher.ex`** - HTTP fetching
8. **`lib/fuzzy_rss_web/components/core_components.ex`** - UI components

### Configuration Files

- `mix.exs` - Dependencies for all three databases
- `config/config.exs` - Default configuration
- `config/runtime.exs` - Runtime adapter selection
- `lib/fuzzy_rss/application.ex` - Oban supervision

---

## Implementation Order Checklist

- [ ] Phase 1: Add dependencies + phx.gen.auth
- [ ] Phase 2: Create all migrations + schemas
- [ ] Phase 3: Build Content context with all CRUD functions
- [ ] Phase 4: Implement feed services + Oban workers
- [ ] Phase 5: Build reader LiveView + feed management UI
- [ ] Phase 6: Add PWA manifest + service worker + mobile UI
- [ ] Phase 7: Build REST API with JWT auth
- [ ] Phase 8: Add search + keyboard shortcuts + polish
- [ ] Phase 9: Write tests + deploy to production

---

## Quick Start Commands

### Local Development (PostgreSQL)
```bash
mix deps.get
mix ecto.setup
mix phx.server
```

### With MySQL
```bash
DATABASE_ADAPTER=mysql mix ecto.setup
DATABASE_ADAPTER=mysql mix phx.server
```

### With SQLite
```bash
DATABASE_ADAPTER=sqlite mix ecto.setup
DATABASE_ADAPTER=sqlite mix phx.server
```

### Docker Deployment
```bash
# PostgreSQL (recommended)
docker-compose up

# MySQL
docker-compose -f docker-compose.mysql.yml up

# SQLite
docker-compose -f docker-compose.sqlite.yml up
```

---

## Notes

- All three database adapters (PostgreSQL, MySQL, SQLite) are included in production builds
- The adapter is selected at runtime via `DATABASE_ADAPTER` environment variable
- A single Docker image supports all three backends
- PostgreSQL is recommended for production deployments
- SQLite is ideal for single-user/small deployments
- MySQL offers good compatibility with many hosting providers

For more information, see individual phase documents or the Multi-Database Docker deployment guide.
