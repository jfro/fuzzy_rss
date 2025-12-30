# Phase 9: Testing & Deployment

**Duration:** Week 9 (3-4 days)
**Previous Phase:** [Phase 8: Search & Polish](PHASE_8_SEARCH_AND_POLISH.md)
**Next Phase:** Production deployment

## Overview

Write comprehensive tests and configure production deployment.

## 9.1: Testing

### Context Tests

Create `test/fuzzy_rss/content_test.exs`:

```elixir
defmodule FuzzyRss.ContentTest do
  use FuzzyRss.DataCase

  alias FuzzyRss.Content

  describe "feeds" do
    test "list_user_feeds/1 returns only user's subscribed feeds" do
      user = user_fixture()
      feed1 = feed_fixture()
      feed2 = feed_fixture()

      Content.subscribe_to_feed(user, feed1.url)

      feeds = Content.list_user_feeds(user)
      assert length(feeds) == 1
      assert List.first(feeds).id == feed1.id
    end

    test "subscribe_to_feed/2 creates subscription" do
      user = user_fixture()
      feed = feed_fixture()

      {:ok, subscription} = Content.subscribe_to_feed(user, feed.url)

      assert subscription.user_id == user.id
      assert subscription.feed_id == feed.id
    end
  end

  describe "entries" do
    test "mark_as_read/2 updates user entry state" do
      user = user_fixture()
      entry = entry_fixture()

      Content.mark_as_read(user, entry.id)

      state = Repo.get_by!(Content.UserEntryState, user_id: user.id, entry_id: entry.id)
      assert state.read == true
    end

    test "search_entries/2 finds entries by title" do
      user = user_fixture()
      feed = feed_fixture()
      Content.subscribe_to_feed(user, feed.url)

      _entry1 = entry_fixture(%{feed_id: feed.id, title: "Elixir Tips"})
      _entry2 = entry_fixture(%{feed_id: feed.id, title: "Phoenix Guide"})

      results = Content.search_entries(user, "Elixir")
      assert length(results) == 1
    end
  end
end
```

### Worker Tests

Create `test/fuzzy_rss/workers/feed_fetcher_worker_test.exs`:

```elixir
defmodule FuzzyRss.Workers.FeedFetcherWorkerTest do
  use FuzzyRss.DataCase

  import Oban.Testing

  alias FuzzyRss.Workers.FeedFetcherWorker

  describe "perform/1" do
    test "fetches and saves feed entries" do
      feed = feed_fixture()

      assert :ok = perform_job(FeedFetcherWorker, %{"feed_id" => feed.id})

      # Verify feed was updated
      feed = Repo.reload(feed)
      assert not is_nil(feed.last_fetched_at)

      # Verify entries were created
      entries = Repo.all(from e in Entry, where: e.feed_id == ^feed.id)
      assert length(entries) > 0
    end
  end
end
```

### LiveView Tests

Create `test/fuzzy_rss_web/live/reader_live_test.exs`:

```elixir
defmodule FuzzyRssWeb.ReaderLiveTest do
  use FuzzyRssWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "ReaderLive.Index" do
    test "renders feed list", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/app")

      assert html =~ "FuzzyRSS"
    end

    test "marks entry as read", %{conn: conn} do
      user = user_fixture()
      feed = feed_fixture()
      entry = entry_fixture(%{feed_id: feed.id})
      Content.subscribe_to_feed(user, feed.url)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/app")

      view |> element("#entry-#{entry.id}") |> render_click("mark_read")

      state = Repo.get_by(Content.UserEntryState, user_id: user.id, entry_id: entry.id)
      assert state.read == true
    end
  end
end
```

Run tests:

```bash
mix test
```

## 9.2: Production Configuration

Update `config/runtime.exs`:

```elixir
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL not set"

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE not set"

  host = System.get_env("HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :fuzzy_rss, FuzzyRssWeb.Endpoint,
    url: [scheme: "https", host: host, port: 443],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  config :fuzzy_rss, FuzzyRss.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true,
    ssl_opts: [verify: :verify_peer]

  config :fuzzy_rss, Oban,
    queues: [feed_fetcher: 20, extractor: 5, default: 10]
end
```

## 9.3: Docker & Docker Compose

See [Multi-Database Docker Deployment](MULTI_DATABASE_DOCKER.md) for detailed Docker setup.

Quick commands:

```bash
# Build image
docker build -t fuzzyrss:latest .

# Run with PostgreSQL
docker-compose up

# Run with MySQL
docker-compose -f docker-compose.mysql.yml up

# Run with SQLite
docker-compose -f docker-compose.sqlite.yml up
```

## 9.4: Health Check Endpoint

Create `lib/fuzzy_rss_web/controllers/health_controller.ex`:

```elixir
defmodule FuzzyRssWeb.HealthController do
  use FuzzyRssWeb, :controller

  def check(conn, _params) do
    case FuzzyRss.Repo.query("SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok", timestamp: DateTime.utc_now()})

      {:error, _} ->
        conn |> put_status(503) |> json(%{status: "error"})
    end
  end
end
```

Add to router:

```elixir
scope "/", FuzzyRssWeb do
  get "/health", HealthController, :check
end
```

## 9.5: Monitoring & Error Tracking

### Sentry (Error Tracking)

Add to `mix.exs`:

```elixir
{:sentry, "~> 10.0"}
```

Configure in `config/runtime.exs`:

```elixir
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: config_env(),
  included_environments: [:prod]
```

### AppSignal (Performance Monitoring)

Add to `mix.exs`:

```elixir
{:appsignal, "~> 2.0"}
```

## 9.6: Database Backups

For production databases:
- **PostgreSQL**: Use pg_dump or managed service backups
- **MySQL**: Use mysqldump or managed service backups
- **SQLite**: Copy database file regularly or use managed backup service

## Deployment Checklist

- [ ] All tests passing: `mix test`
- [ ] Code formatted: `mix format --check-formatted`
- [ ] No compiler warnings: `mix compile --warnings-as-errors`
- [ ] Dialyzer passes: `mix dialyzer`
- [ ] Environment variables configured
- [ ] Database backups configured
- [ ] Health check endpoint working
- [ ] Error tracking (Sentry) configured
- [ ] Performance monitoring configured
- [ ] SSL/TLS certificates configured
- [ ] Docker image builds successfully
- [ ] Tested with all three database backends

## Deployment Platforms

### Fly.io (Recommended for Elixir)

```bash
# Install fly CLI
# Create app
flyctl launch

# Deploy
flyctl deploy
```

### Render

```bash
# Connect to Render
# Create web service
# Configure environment variables
# Deploy
```

### AWS ECS

```bash
# Build and push image to ECR
# Create ECS task definition
# Create service
# Configure load balancer
```

## Completion Checklist

- [ ] Unit tests written and passing
- [ ] Integration tests written and passing
- [ ] E2E tests written and passing
- [ ] Production config finalized
- [ ] Health check endpoint implemented
- [ ] Error tracking configured
- [ ] Performance monitoring configured
- [ ] Docker image built and tested
- [ ] Docker Compose files tested
- [ ] Database backups configured
- [ ] Application deployed to production
- [ ] Monitoring dashboards set up
- [ ] Documentation updated

## Next Steps

Monitor application in production and iterate based on user feedback and performance metrics.
