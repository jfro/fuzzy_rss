# Phase 7: REST API

**Duration:** Week 6 (2-3 days)
**Previous Phase:** [Phase 6: PWA Features](PHASE_6_PWA_FEATURES.md)
**Next Phase:** [Phase 8: Search & Polish](PHASE_8_SEARCH_AND_POLISH.md)

## Overview

Build REST/JSON API with JWT authentication for external clients and mobile apps.

## 7.1: API Pipeline & Routes

Update `lib/fuzzy_rss_web/router.ex`:

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug FuzzyRssWeb.ApiAuth
end

scope "/api/v1", FuzzyRssWeb.API.V1, as: :api_v1 do
  pipe_through :api

  post "/auth/login", AuthController, :login
  post "/auth/refresh", AuthController, :refresh

  resources "/feeds", FeedController, only: [:index, :show, :create, :delete]
  resources "/entries", EntryController, only: [:index, :show]

  post "/entries/:id/read", EntryController, :mark_read
  post "/entries/:id/star", EntryController, :star

  get "/opml/export", OPMLController, :export
  post "/opml/import", OPMLController, :import
end
```

## 7.2: API Authentication

Create `lib/fuzzy_rss_web/api_auth.ex`:

```elixir
defmodule FuzzyRssWeb.ApiAuth do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- verify_token(token),
         user <- FuzzyRss.Accounts.get_user!(claims["user_id"]) do
      assign(conn, :current_user, user)
    else
      _ -> send_unauthorized(conn)
    end
  end

  defp verify_token(token) do
    Joken.verify(token, FuzzyRss.TokenSigner)
  end

  defp send_unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
    |> halt()
  end
end
```

## 7.3: API Controllers

Create `lib/fuzzy_rss_web/controllers/api/v1/auth_controller.ex`:

```elixir
defmodule FuzzyRssWeb.API.V1.AuthController do
  use FuzzyRssWeb, :controller

  def login(conn, %{"email" => email, "password" => password}) do
    case FuzzyRss.Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        token = generate_token(user)
        json(conn, %{token: token, user: user_json(user)})

      {:error, _} ->
        conn |> put_status(401) |> json(%{error: "Invalid credentials"})
    end
  end

  defp generate_token(user) do
    {:ok, token, _claims} =
      Joken.generate_and_sign(
        %{"user_id" => user.id, "email" => user.email},
        FuzzyRss.TokenSigner
      )

    token
  end

  defp user_json(user) do
    %{id: user.id, email: user.email}
  end
end
```

Create `lib/fuzzy_rss_web/controllers/api/v1/feed_controller.ex`:

```elixir
defmodule FuzzyRssWeb.API.V1.FeedController do
  use FuzzyRssWeb, :controller

  def index(conn, _params) do
    user = conn.assigns.current_user
    feeds = FuzzyRss.Content.list_user_feeds(user)
    json(conn, %{feeds: Enum.map(feeds, &feed_json/1)})
  end

  def show(conn, %{"id" => id}) do
    feed = FuzzyRss.Content.get_feed!(id)
    json(conn, %{feed: feed_json(feed)})
  end

  def create(conn, %{"feed" => feed_params}) do
    user = conn.assigns.current_user

    case FuzzyRss.Content.subscribe_to_feed(user, feed_params["url"]) do
      {:ok, subscription} ->
        json(conn, %{feed: feed_json(subscription.feed)})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    FuzzyRss.Content.unsubscribe_from_feed(user, id)
    json(conn, %{})
  end

  defp feed_json(feed) do
    %{
      id: feed.id,
      title: feed.title,
      url: feed.url,
      site_url: feed.site_url,
      last_fetched_at: feed.last_fetched_at
    }
  end

  defp changeset_errors(changeset) do
    Enum.into(changeset.errors, %{}, fn {key, {msg, _}} ->
      {key, msg}
    end)
  end
end
```

Create `lib/fuzzy_rss_web/controllers/api/v1/entry_controller.ex`:

```elixir
defmodule FuzzyRssWeb.API.V1.EntryController do
  use FuzzyRssWeb, :controller

  def index(conn, params) do
    user = conn.assigns.current_user

    opts = [
      filter: String.to_atom(params["filter"] || "all"),
      limit: String.to_integer(params["limit"] || "50"),
      offset: String.to_integer(params["offset"] || "0")
    ]

    entries = FuzzyRss.Content.list_entries(user, opts)
    json(conn, %{entries: Enum.map(entries, &entry_json/1)})
  end

  def show(conn, %{"id" => id}) do
    entry = FuzzyRss.Content.get_entry!(id)
    json(conn, %{entry: entry_json(entry)})
  end

  def mark_read(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    FuzzyRss.Content.mark_as_read(user, id)
    json(conn, %{})
  end

  def star(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    FuzzyRss.Content.toggle_starred(user, id)
    json(conn, %{})
  end

  defp entry_json(entry) do
    %{
      id: entry.id,
      title: entry.title,
      url: entry.url,
      summary: entry.summary,
      content: entry.content,
      published_at: entry.published_at
    }
  end
end
```

Create `lib/fuzzy_rss_web/controllers/api/v1/opml_controller.ex`:

```elixir
defmodule FuzzyRssWeb.API.V1.OPMLController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.Feeds.OPML

  def export(conn, _params) do
    user = conn.assigns.current_user

    case OPML.export(user) do
      {:ok, xml} ->
        conn
        |> put_resp_content_type("application/xml")
        |> put_resp_header("content-disposition", "attachment; filename=\"fuzzyrss-subscriptions.opml\"")
        |> send_resp(200, xml)

      {:error, _} ->
        json(conn |> put_status(500), %{error: "Failed to export OPML"})
    end
  end

  def import(conn, %{"file" => file}) do
    user = conn.assigns.current_user

    case read_upload(file) do
      {:ok, xml} ->
        case OPML.import(xml, user) do
          {:ok, results} ->
            json(conn, %{
              success: true,
              created_feeds: results.created_feeds,
              created_folders: results.created_folders,
              errors: results.errors
            })

          {:error, reason} ->
            json(conn |> put_status(400), %{error: inspect(reason)})
        end

      {:error, _} ->
        json(conn |> put_status(400), %{error: "Failed to read file"})
    end
  end

  defp read_upload(file) do
    case file do
      %{path: path} ->
        {:ok, File.read!(path)}

      _ ->
        {:error, :invalid_file}
    end
  end
end
```

Create `lib/fuzzy_rss_web/controllers/api/v1/freshrss_json_controller.ex`:

```elixir
defmodule FuzzyRssWeb.API.V1.FreshRSSJSONController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.Feeds.FreshRSSJSON

  def export_starred(conn, _params) do
    user = conn.assigns.current_user

    case FreshRSSJSON.export_starred(user) do
      {:ok, json} ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("content-disposition", "attachment; filename=\"fuzzyrss-starred.json\"")
        |> send_resp(200, json)

      {:error, _} ->
        json(conn |> put_status(500), %{error: "Failed to export starred articles"})
    end
  end

  def import_starred(conn, %{"file" => file}) do
    user = conn.assigns.current_user

    case read_upload(file) do
      {:ok, json_str} ->
        case FreshRSSJSON.import_starred(json_str, user) do
          {:ok, results} ->
            json(conn, %{
              success: true,
              imported: results.imported,
              errors: results.errors
            })

          {:error, reason} ->
            json(conn |> put_status(400), %{error: inspect(reason)})
        end

      {:error, _} ->
        json(conn |> put_status(400), %{error: "Failed to read file"})
    end
  end

  defp read_upload(file) do
    case file do
      %{path: path} ->
        {:ok, File.read!(path)}

      _ ->
        {:error, :invalid_file}
    end
  end
end
```

Update routes in `lib/fuzzy_rss_web/router.ex` to add import/export endpoints:

```elixir
scope "/api/v1", FuzzyRssWeb.API.V1, as: :api_v1 do
  pipe_through :api

  post "/auth/login", AuthController, :login
  post "/auth/refresh", AuthController, :refresh

  resources "/feeds", FeedController, only: [:index, :show, :create, :delete]
  resources "/entries", EntryController, only: [:index, :show]

  post "/entries/:id/read", EntryController, :mark_read
  post "/entries/:id/star", EntryController, :star

  # OPML import/export
  get "/opml/export", OPMLController, :export
  post "/opml/import", OPMLController, :import

  # FreshRSS JSON import/export
  get "/freshrss/starred/export", FreshRSSJSONController, :export_starred
  post "/freshrss/starred/import", FreshRSSJSONController, :import_starred
end
```

## Completion Checklist

- [ ] Created API pipeline and routes
- [ ] Created `lib/fuzzy_rss_web/api_auth.ex`
- [ ] Created `lib/fuzzy_rss_web/controllers/api/v1/auth_controller.ex`
- [ ] Created `lib/fuzzy_rss_web/controllers/api/v1/feed_controller.ex`
- [ ] Created `lib/fuzzy_rss_web/controllers/api/v1/entry_controller.ex`
- [ ] Created `lib/fuzzy_rss_web/controllers/api/v1/opml_controller.ex`
- [ ] Created `lib/fuzzy_rss_web/controllers/api/v1/freshrss_json_controller.ex`
- [ ] Added import/export routes to router
- [ ] Verified compilation: `mix compile`

## Testing API

```bash
# Login
curl -X POST http://localhost:4000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password"}'

# Get feeds
curl http://localhost:4000/api/v1/feeds \
  -H "Authorization: Bearer YOUR_TOKEN"

# Export OPML
curl http://localhost:4000/api/v1/opml/export \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -o subscriptions.opml

# Import OPML
curl -X POST http://localhost:4000/api/v1/opml/import \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@subscriptions.opml"

# Export starred articles
curl http://localhost:4000/api/v1/freshrss/starred/export \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -o starred.json

# Import starred articles
curl -X POST http://localhost:4000/api/v1/freshrss/starred/import \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@starred.json"
```

## Next Steps

Proceed to [Phase 8: Search & Polish](PHASE_8_SEARCH_AND_POLISH.md).
