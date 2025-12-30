# Phase 4: Feed Processing

**Duration:** Week 2-3 (3-4 days)
**Previous Phase:** [Phase 3: Phoenix Contexts](PHASE_3_PHOENIX_CONTEXTS.md)
**Next Phase:** [Phase 5: LiveView UI](PHASE_5_LIVEVIEW_UI.md)

## Overview

Implement feed fetching, parsing, and background job processing. This includes services for HTTP requests, RSS/Atom parsing, feed discovery, and article extraction.

## 4.1: Feed Services

### HTTP Fetcher Service

Create `lib/fuzzy_rss/feeds/fetcher.ex`:

```elixir
defmodule FuzzyRss.Feeds.Fetcher do
  @moduledoc "HTTP fetching with conditional requests and error handling"

  def fetch_feed(feed) do
    headers = conditional_headers(feed)

    case Req.get(feed.url, headers: headers, max_redirects: 5, timeout: 30_000) do
      {:ok, response} ->
        {:ok, response.body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp conditional_headers(feed) do
    headers = []

    headers =
      if feed.etag do
        [{"if-none-match", feed.etag} | headers]
      else
        headers
      end

    if feed.last_modified do
      [{"if-modified-since", feed.last_modified} | headers]
    else
      headers
    end
  end
end
```

### RSS/Atom Parser Service

Create `lib/fuzzy_rss/feeds/parser.ex`:

```elixir
defmodule FuzzyRss.Feeds.Parser do
  @moduledoc "Parse RSS/Atom feeds into normalized entries"

  def parse(xml_string) do
    case FeederEx.parse(xml_string) do
      {:ok, feed_data} ->
        {:ok, normalize_feed(feed_data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_feed(feed_data) do
    %{
      feed: %{
        title: feed_data.feed.title || "Untitled",
        description: feed_data.feed.description,
        site_url: feed_data.feed.link,
        feed_type: feed_data.feed.type || "rss"
      },
      entries: Enum.map(feed_data.entries, &normalize_entry/1)
    }
  end

  defp normalize_entry(entry) do
    %{
      guid: entry.id,
      url: entry.link,
      title: entry.title || "Untitled",
      author: entry.author,
      summary: entry.summary,
      content: entry.content,
      published_at: parse_date(entry.updated),
      image_url: extract_image(entry),
      categories: entry.categories || []
    }
  end

  defp parse_date(nil), do: DateTime.utc_now()
  defp parse_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_date(_), do: DateTime.utc_now()

  defp extract_image(entry) do
    # Try to find image in media content or HTML
    nil
  end
end
```

### Feed Discovery Service

Create `lib/fuzzy_rss/feeds/discoverer.ex`:

```elixir
defmodule FuzzyRss.Feeds.Discoverer do
  @moduledoc "Discover feeds from website URLs"

  def find_feeds(url) do
    case Req.get(url, max_redirects: 5) do
      {:ok, response} ->
        feeds = extract_feed_urls(response.body)

        if Enum.empty?(feeds) do
          try_common_paths(url)
        else
          {:ok, feeds}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_feed_urls(html) do
    html
    |> Floki.find("link[rel~='alternate'][type~='feed']")
    |> Enum.map(&Floki.attribute(&1, "href"))
    |> Enum.filter(& &1)
  end

  defp try_common_paths(base_url) do
    paths = ["/feed", "/rss", "/atom.xml", "/feed.xml", "/rss.xml"]

    feeds =
      Enum.filter_map(paths, fn path ->
        url = base_url <> path
        case Req.head(url) do
          {:ok, %{status: 200}} -> true
          _ -> false
        end
      end, fn path -> base_url <> path end)

    if Enum.empty?(feeds) do
      {:error, :no_feeds_found}
    else
      {:ok, feeds}
    end
  end
end
```

### Article Extraction Service

Create `lib/fuzzy_rss/feeds/extractor.ex`:

```elixir
defmodule FuzzyRss.Feeds.Extractor do
  @moduledoc "Extract full article content from URLs"

  def extract_article(url) do
    with {:ok, response} <- Req.get(url, max_redirects: 5, timeout: 30_000),
         {:ok, content} <- Readability.article(response.body) do
      {:ok, %{
        content: content,
        title: Readability.title(response.body),
        excerpt: Readability.excerpt(response.body)
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### OPML Import/Export Service

Create `lib/fuzzy_rss/feeds/opml.ex`:

```elixir
defmodule FuzzyRss.Feeds.OPML do
  @moduledoc "OPML import/export for subscription lists"

  alias FuzzyRss.{Content, Repo}

  def export(user) do
    subscriptions = Content.list_user_subscriptions(user)
    folders = Content.list_user_folders(user)

    xml = build_opml_xml(user, subscriptions, folders)
    {:ok, xml}
  end

  def import(xml_string, user) do
    with {:ok, document} <- parse_opml(xml_string),
         outlines <- extract_outlines(document) do
      results = process_outlines(outlines, user, nil)
      {:ok, results}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_opml_xml(user, subscriptions, folders) do
    folder_map = Enum.into(folders, %{}, fn f -> {f.id, f} end)
    subs_by_folder = Enum.group_by(subscriptions, & &1.folder_id)

    body = build_body(subs_by_folder, folders, folder_map)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>FuzzyRSS</title>
        <dateCreated>#{DateTime.utc_now()}</dateCreated>
        <ownerName>#{user.email}</ownerName>
      </head>
      <body>
        #{body}
      </body>
    </opml>
    """ |> String.trim()
  end

  defp build_body(subs_by_folder, folders, folder_map) do
    # Root feeds (no folder)
    root_subs = subs_by_folder[nil] || []
    root_xml = Enum.map_join(root_subs, "\n", &feed_outline/1)

    # Folders with nested feeds
    folder_xml = Enum.map_join(folders, "\n", fn folder ->
      folder_subs = subs_by_folder[folder.id] || []
      feeds_xml = Enum.map_join(folder_subs, "\n", &feed_outline/1)
      ~s[<outline type="folder" text="#{folder.name}">
        #{feeds_xml}
      </outline>]
    end)

    "#{root_xml}\n#{folder_xml}"
  end

  defp feed_outline(subscription) do
    feed = subscription.feed
    ~s[<outline type="rss" text="#{feed.title}" xmlUrl="#{feed.url}" />]
  end

  defp parse_opml(xml_string) do
    case Floki.parse_document(xml_string) do
      {:ok, document} -> {:ok, document}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_outlines(document) do
    document
    |> Floki.find("body > outline")
  end

  defp process_outlines(outlines, user, parent_folder_id) do
    results = %{created_feeds: 0, created_folders: 0, errors: []}

    Enum.reduce(outlines, results, fn outline, acc ->
      type = Floki.attribute(outline, "type") |> List.first()

      case type do
        "folder" ->
          process_folder(outline, user, parent_folder_id, acc)

        "rss" ->
          process_feed(outline, user, parent_folder_id, acc)

        _ ->
          acc
      end
    end)
  end

  defp process_folder(outline, user, _parent_id, acc) do
    name = Floki.attribute(outline, "text") |> List.first()
    children = Floki.find(outline, "outline")

    case create_folder(user, name) do
      {:ok, folder} ->
        child_results = process_outlines(children, user, folder.id)

        %{
          acc
          | created_feeds: acc.created_feeds + child_results.created_feeds,
            created_folders: acc.created_folders + child_results.created_folders
        }

      {:error, reason} ->
        Map.update(acc, :errors, [reason], &[reason | &1])
    end
  end

  defp process_feed(outline, user, folder_id, acc) do
    feed_url = Floki.attribute(outline, "xmlUrl") |> List.first()
    title_override = Floki.attribute(outline, "text") |> List.first()

    case Content.subscribe_to_feed(user, feed_url) do
      {:ok, _subscription} ->
        %{acc | created_feeds: acc.created_feeds + 1}

      {:error, reason} ->
        Map.update(acc, :errors, [reason], &[reason | &1])
    end
  end

  defp create_folder(user, name) do
    Content.create_folder(user, %{
      name: name,
      slug: slugify(name)
    })
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/[-\s]+/, "-")
    |> String.trim("-")
  end
end
```

### FreshRSS JSON Import/Export Service

Create `lib/fuzzy_rss/feeds/freshrss_json.ex`:

```elixir
defmodule FuzzyRss.Feeds.FreshRSSJSON do
  @moduledoc "FreshRSS JSON format import/export for starred articles"

  alias FuzzyRss.Content

  def export_starred(user) do
    entries =
      from(e in Content.Entry,
        join: s in Content.Subscription,
          on: s.feed_id == e.feed_id,
        left_join: ues in Content.UserEntryState,
          on: ues.entry_id == e.id and ues.user_id == ^user.id,
        where: s.user_id == ^user.id and ues.starred == true,
        order_by: [desc: e.published_at],
        select: e,
        preload: :feed
      )
      |> Repo.all()

    json_data = %{
      articles: Enum.map(entries, &entry_to_json/1)
    }

    {:ok, Jason.encode!(json_data)}
  end

  def import_starred(json_string, user) do
    with {:ok, data} <- Jason.decode(json_string) do
      articles = Map.get(data, "articles", [])

      results =
        Enum.reduce(articles, %{imported: 0, errors: 0}, fn article, acc ->
          case find_and_star_entry(user, article) do
            :ok -> %{acc | imported: acc.imported + 1}
            :error -> %{acc | errors: acc.errors + 1}
          end
        end)

      {:ok, results}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp entry_to_json(entry) do
    %{
      id: entry.id,
      title: entry.title,
      url: entry.url,
      author: entry.author,
      content: entry.content,
      summary: entry.summary,
      published_at: entry.published_at,
      feed_url: entry.feed.url,
      feed_title: entry.feed.title
    }
  end

  defp find_and_star_entry(user, article) do
    feed_url = Map.get(article, "feed_url")
    entry_url = Map.get(article, "url")

    case Repo.get_by(Content.Feed, url: feed_url) do
      nil ->
        :error

      feed ->
        case Repo.get_by(Content.Entry, feed_id: feed.id, url: entry_url) do
          nil -> :error
          entry -> Content.toggle_starred(user, entry.id)
        end
    end
  end
end
```

## 4.2: Oban Background Workers

### Configure Oban

Update `config/config.exs` or `config/runtime.exs` (if not already done):

```elixir
config :fuzzy_rss, Oban,
  repo: FuzzyRss.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
      crontab: [
        {"*/5 * * * *", FuzzyRss.Workers.FeedSchedulerWorker},
        {"0 2 * * *", FuzzyRss.Workers.CleanupWorker}
      ]
    }
  ],
  queues: [feed_fetcher: 10, extractor: 3, default: 5]
```

Add to `lib/fuzzy_rss/application.ex` supervision tree:

```elixir
{Oban, Application.fetch_env!(:fuzzy_rss, Oban)}
```

### Feed Fetcher Worker

Create `lib/fuzzy_rss/workers/feed_fetcher_worker.ex`:

```elixir
defmodule FuzzyRss.Workers.FeedFetcherWorker do
  use Oban.Worker, queue: :feed_fetcher, max_attempts: 3

  alias FuzzyRss.Content
  alias FuzzyRss.Feeds.{Fetcher, Parser}

  @impl Oban.Worker
  def perform(%Job{args: %{"feed_id" => feed_id}}) do
    feed = Content.get_feed!(feed_id)

    with {:ok, xml} <- Fetcher.fetch_feed(feed),
         {:ok, parsed} <- Parser.parse(xml) do
      save_entries(feed, parsed.entries)
      update_feed_success(feed)
      broadcast_update(feed)
      :ok
    else
      {:error, reason} ->
        update_feed_error(feed, reason)
        {:error, reason}
    end
  end

  defp save_entries(feed, entries) do
    Enum.each(entries, fn entry_data ->
      %FuzzyRss.Content.Entry{}
      |> FuzzyRss.Content.Entry.changeset(
        Map.merge(entry_data, %{feed_id: feed.id})
      )
      |> FuzzyRss.Repo.insert(on_conflict: :replace_all, conflict_target: [:feed_id, :guid])
    end)
  end

  defp update_feed_success(feed) do
    feed
    |> FuzzyRss.Content.Feed.changeset(%{
      last_fetched_at: DateTime.utc_now(),
      last_successful_fetch_at: DateTime.utc_now(),
      last_error: nil
    })
    |> FuzzyRss.Repo.update()
  end

  defp update_feed_error(feed, reason) do
    feed
    |> FuzzyRss.Content.Feed.changeset(%{
      last_fetched_at: DateTime.utc_now(),
      last_error: inspect(reason)
    })
    |> FuzzyRss.Repo.update()
  end

  defp broadcast_update(feed) do
    Phoenix.PubSub.broadcast(
      FuzzyRss.PubSub,
      "feed_update:#{feed.id}",
      {:feed_updated, feed}
    )
  end
end
```

### Feed Scheduler Worker

Create `lib/fuzzy_rss/workers/feed_scheduler_worker.ex`:

```elixir
defmodule FuzzyRss.Workers.FeedSchedulerWorker do
  use Oban.Worker, queue: :default

  alias FuzzyRss.Content
  alias FuzzyRss.Workers.FeedFetcherWorker

  @impl Oban.Worker
  def perform(_job) do
    # Query feeds that need updating
    feeds = Content.feeds_due_for_fetch()

    Enum.each(feeds, fn feed ->
      %{"feed_id" => feed.id}
      |> FeedFetcherWorker.new()
      |> Oban.insert()
    end)

    :ok
  end
end
```

Add to Content context:

```elixir
def feeds_due_for_fetch do
  now = DateTime.utc_now()

  from f in Feed,
    where: f.active == true and (is_nil(f.last_fetched_at) or f.last_fetched_at < datetime_add(^now, -f.fetch_interval, "minute")),
    limit: 100

  |> Repo.all()
end
```

### Entry Extractor Worker

Create `lib/fuzzy_rss/workers/entry_extractor_worker.ex`:

```elixir
defmodule FuzzyRss.Workers.EntryExtractorWorker do
  use Oban.Worker, queue: :extractor

  alias FuzzyRss.Content
  alias FuzzyRss.Feeds.Extractor

  @impl Oban.Worker
  def perform(%Job{args: %{"entry_id" => entry_id}}) do
    entry = Content.get_entry!(entry_id)

    with {:ok, extracted} <- Extractor.extract_article(entry.url) do
      entry
      |> Content.Entry.changeset(%{
        extracted_content: extracted.content,
        extracted_at: DateTime.utc_now()
      })
      |> Content.Repo.update()

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Completion Checklist

- [ ] Created `lib/fuzzy_rss/feeds/fetcher.ex`
- [ ] Created `lib/fuzzy_rss/feeds/parser.ex`
- [ ] Created `lib/fuzzy_rss/feeds/discoverer.ex`
- [ ] Created `lib/fuzzy_rss/feeds/extractor.ex`
- [ ] Created `lib/fuzzy_rss/feeds/opml.ex` with import/export
- [ ] Created `lib/fuzzy_rss/feeds/freshrss_json.ex` for starred articles
- [ ] Configured Oban in config files
- [ ] Added Oban to Application supervision tree
- [ ] Created `lib/fuzzy_rss/workers/feed_fetcher_worker.ex`
- [ ] Created `lib/fuzzy_rss/workers/feed_scheduler_worker.ex`
- [ ] Created `lib/fuzzy_rss/workers/entry_extractor_worker.ex`
- [ ] Verified compilation: `mix compile`

## Testing

```bash
# Start worker in development
iex -S mix

# Manually trigger a fetch
FuzzyRss.Workers.FeedFetcherWorker.new(%{"feed_id" => 1})
|> Oban.insert()

# Watch Oban dashboard: http://localhost:4000/dev/dashboard/oban/jobs
```

## Next Steps

Proceed to [Phase 5: LiveView UI](PHASE_5_LIVEVIEW_UI.md) to build the user interface.
