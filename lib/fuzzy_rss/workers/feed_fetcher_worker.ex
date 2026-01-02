defmodule FuzzyRss.Workers.FeedFetcherWorker do
  use Oban.Worker, queue: :feed_fetcher, max_attempts: 3

  import Ecto.Query
  alias FuzzyRss.Content
  alias FuzzyRss.Content.Entry
  alias FuzzyRss.Feeds.{Fetcher, Parser, Discoverer}

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"feed_id" => feed_id}}) do
    feed = Content.get_feed!(feed_id)
    require Logger
    Logger.info("FeedFetcherWorker: Starting fetch for feed #{feed_id} (#{feed.url})")

    with {:ok, xml} <- Fetcher.fetch_feed(feed),
         {:ok, parsed} <- Parser.parse(xml) do
      Logger.info(
        "FeedFetcherWorker: Successfully fetched and parsed feed #{feed_id}, saving #{length(parsed.entries)} entries"
      )

      save_entries(feed, parsed.entries)
      update_feed_metadata(feed, parsed.feed)
      update_feed_success(feed)
      broadcast_update(feed)
      Logger.info("FeedFetcherWorker: Completed feed #{feed_id}")
      :ok
    else
      {:error, reason} ->
        Logger.error("FeedFetcherWorker: Failed to fetch feed #{feed_id}: #{inspect(reason)}")
        update_feed_error(feed, reason)
        {:error, reason}
    end
  end

  defp save_entries(feed, entries) do
    require Logger

    Enum.each(entries, fn entry_data ->
      try do
        case %Entry{}
             |> Entry.changeset(Map.put(entry_data, :feed_id, feed.id))
             |> repo().insert(on_conflict: :replace_all, conflict_target: [:feed_id, :guid]) do
          {:ok, entry} ->
            Logger.debug("FeedFetcherWorker: Saved entry #{entry.id}: #{entry.title}")

          {:error, changeset} ->
            Logger.error("FeedFetcherWorker: Failed to save entry: #{inspect(changeset.errors)}")
        end
      rescue
        e ->
          Logger.error("FeedFetcherWorker: Exception saving entry: #{inspect(e)}")
          Logger.error("Entry data: #{inspect(entry_data)}")
      end
    end)
  end

  defp update_feed_metadata(feed, feed_data) do
    favicon_url = feed_data[:favicon_url] || feed.favicon_url

    favicon_url =
      if is_nil(favicon_url) and feed_data[:site_url] do
        case Discoverer.find_favicon(feed_data[:site_url]) do
          {:ok, url} -> url
          _ -> nil
        end
      else
        favicon_url
      end

    Content.update_feed(feed, %{
      title: feed_data[:title],
      description: feed_data[:description],
      site_url: feed_data[:site_url],
      favicon_url: favicon_url,
      feed_type: feed_data[:feed_type]
    })
  end

  defp update_feed_success(feed) do
    Content.update_feed(feed, %{
      last_fetched_at: DateTime.utc_now(),
      last_successful_fetch_at: DateTime.utc_now(),
      last_error: nil
    })
  end

  defp update_feed_error(feed, reason) do
    Content.update_feed(feed, %{
      last_fetched_at: DateTime.utc_now(),
      last_error: inspect(reason)
    })
  end

  defp broadcast_update(feed) do
    require Logger
    # Get all users subscribed to this feed
    user_ids =
      from(s in FuzzyRss.Content.Subscription,
        where: s.feed_id == ^feed.id,
        select: s.user_id,
        distinct: true
      )
      |> repo().all()

    Logger.info(
      "FeedFetcherWorker: Broadcasting update for feed #{feed.id} to #{length(user_ids)} users"
    )

    # Broadcast to each user's channel
    Enum.each(user_ids, fn user_id ->
      Phoenix.PubSub.broadcast(
        FuzzyRss.PubSub,
        "user:#{user_id}:feeds",
        {:feed_updated, feed}
      )
    end)
  end
end
