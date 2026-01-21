defmodule FuzzyRssWeb.Api.GReader.StreamController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.{Content, Api.GReader, Api.GReader.IdConverter}

  @doc """
  GET /reader/api/0/stream/contents/:stream_id

  Returns entries for a stream (reading-list, starred, folder, or feed).
  """
  def contents(conn, %{"stream_id" => stream_id_parts} = params) do
    user = conn.assigns.current_user
    stream_id = reconstruct_stream_id(stream_id_parts)

    with {:ok, stream_type} <- IdConverter.parse_stream_id(stream_id) do
      opts = build_query_opts(params)
      entries = fetch_stream_entries(user, stream_type, opts)

      items = Enum.map(entries, &GReader.format_item(&1, user))

      response = %{
        id: stream_id,
        title: stream_title(stream_type),
        items: items
      }

      # Add continuation token if there might be more results
      response = maybe_add_continuation(response, entries, opts)

      json(conn, response)
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid stream ID"})
    end
  end

  @doc """
  GET /reader/api/0/stream/items/ids

  Returns only item IDs for a stream (lightweight).
  """
  def ids(conn, %{"s" => stream_id} = params) do
    user = conn.assigns.current_user

    with {:ok, stream_type} <- IdConverter.parse_stream_id(stream_id) do
      opts = build_query_opts(params)
      entries = fetch_stream_entries(user, stream_type, opts)

      item_refs = Enum.map(entries, fn entry ->
        %{
          id: IdConverter.to_long_item_id(entry.id),
          directStreamIds: datetime_to_usec(entry.published_at || entry.inserted_at),
          timestampUsec: datetime_to_usec(entry.published_at || entry.inserted_at)
        }
      end)

      response = %{
        itemRefs: item_refs
      }

      # Add continuation token if there might be more results
      response = maybe_add_continuation(response, entries, opts)

      json(conn, response)
    else
      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid stream ID"})
    end
  end

  @doc """
  POST /reader/api/0/stream/items/contents

  Returns full entries for specific item IDs (supports all 3 ID formats).
  """
  def batch_contents(conn, %{"i" => item_ids}) when is_list(item_ids) do
    user = conn.assigns.current_user

    # Parse all item IDs (supports decimal, hex, and long format)
    entry_ids = Enum.flat_map(item_ids, fn id ->
      case IdConverter.parse_item_id(id) do
        {:ok, entry_id} -> [entry_id]
        _ -> []
      end
    end)

    entries = Content.get_entries_by_ids(user, entry_ids)
    items = Enum.map(entries, &GReader.format_item(&1, user))

    json(conn, %{items: items})
  end

  def batch_contents(conn, _params) do
    json(conn, %{items: []})
  end

  @doc """
  GET /reader/api/0/unread-count

  Returns unread counts for all subscriptions, folders, and the reading list.
  """
  def unread_count(conn, _params) do
    user = conn.assigns.current_user

    # Get all subscriptions with unread counts
    subscriptions = Content.list_subscriptions(user)
    folders = Content.list_user_folders(user)

    unreadcounts = []

    # Reading list total (all unread)
    total_unread = calculate_total_unread(user, subscriptions)
    reading_list_count = GReader.format_unread_count(
      "user/#{user.id}/state/com.google/reading-list",
      total_unread,
      DateTime.to_unix(DateTime.utc_now(), :microsecond)
    )
    unreadcounts = [reading_list_count | unreadcounts]

    # Per-feed counts
    feed_counts = Enum.map(subscriptions, fn sub ->
      unread = Content.count_unread_entries(user, feed_id: sub.feed_id)
      newest_timestamp = get_newest_timestamp(user, feed_id: sub.feed_id)
      GReader.format_unread_count("feed/#{sub.feed.url}", unread, newest_timestamp)
    end)
    unreadcounts = unreadcounts ++ feed_counts

    # Per-folder counts
    folder_counts = Enum.map(folders, fn folder ->
      unread = Content.count_unread_entries(user, folder_id: folder.id)
      newest_timestamp = get_newest_timestamp(user, folder_id: folder.id)
      GReader.format_unread_count("user/#{user.id}/label/#{folder.name}", unread, newest_timestamp)
    end)
    unreadcounts = unreadcounts ++ folder_counts

    json(conn, %{max: 1000, unreadcounts: unreadcounts})
  end

  # Private helpers

  defp reconstruct_stream_id(parts) when is_list(parts) do
    # Handle feed URLs that got split by Phoenix glob matching
    # Phoenix trims empty strings, so ["feed", "https:", "example.com", "feed1.xml"]
    # should become "feed/https://example.com/feed1.xml"
    case parts do
      ["feed" | url_parts] ->
        # Reconstruct URL from split parts
        url = case url_parts do
          # With empty string (shouldn't happen with Phoenix but handle it)
          ["https:", "" | rest] -> "https://" <> Enum.join(rest, "/")
          ["http:", "" | rest] -> "http://" <> Enum.join(rest, "/")
          # Without empty string (Phoenix trims them)
          ["https:" | rest] -> "https://" <> Enum.join(rest, "/")
          ["http:" | rest] -> "http://" <> Enum.join(rest, "/")
          _ -> Enum.join(url_parts, "/")
        end
        "feed/#{url}"

      _ ->
        # For non-feed streams, simple join works fine
        Enum.join(parts, "/")
    end
  end

  defp build_query_opts(params) do
    opts = []

    # Limit (n parameter)
    opts = if n = params["n"], do: Keyword.put(opts, :limit, String.to_integer(n)), else: opts

    # Older than timestamp (ot parameter) - in seconds
    opts = if ot = params["ot"], do: Keyword.put(opts, :older_than, String.to_integer(ot)), else: opts

    # Newer than timestamp (nt parameter) - in seconds
    opts = if nt = params["nt"], do: Keyword.put(opts, :newer_than, String.to_integer(nt)), else: opts

    # Exclude target (xt parameter) - e.g., "user/-/state/com.google/read"
    opts = if xt = params["xt"] do
      case IdConverter.parse_stream_id(xt) do
        {:ok, :read} -> Keyword.put(opts, :exclude_read, true)
        _ -> opts
      end
    else
      opts
    end

    # Reverse order (r parameter)
    opts = if params["r"] == "o", do: Keyword.put(opts, :order, :asc), else: opts

    # Continuation token (c parameter) - encoded as timestamp in microseconds
    # Use it as older_than filter if not already specified
    opts = if c = params["c"] do
      timestamp_sec = String.to_integer(c) |> div(1_000_000)
      if Keyword.has_key?(opts, :older_than) do
        opts
      else
        Keyword.put(opts, :older_than, timestamp_sec)
      end
    else
      opts
    end

    opts
  end

  defp fetch_stream_entries(user, stream_type, opts) do
    case stream_type do
      :all ->
        Content.list_entries(user, opts)

      :starred ->
        Content.list_entries(user, Keyword.put(opts, :filter, :starred))

      :read ->
        Content.list_entries(user, Keyword.put(opts, :filter, :read))

      {:folder, folder_name} ->
        case Content.get_user_folder_by_name(user, folder_name) do
          nil -> []
          folder -> Content.list_entries(user, Keyword.put(opts, :folder_id, folder.id))
        end

      {:feed, feed_url} ->
        case Content.get_user_subscription_by_url(user, feed_url) do
          nil -> []
          subscription -> Content.list_entries(user, Keyword.put(opts, :feed_id, subscription.feed_id))
        end
    end
  end

  defp stream_title(stream_type) do
    case stream_type do
      :all -> "Reading List"
      :starred -> "Starred"
      :read -> "Read"
      {:folder, name} -> name
      {:feed, url} -> url
    end
  end

  defp maybe_add_continuation(response, entries, opts) do
    limit = Keyword.get(opts, :limit, 20)

    if length(entries) == limit do
      # Create continuation token from last entry timestamp
      last_entry = List.last(entries)
      continuation = datetime_to_usec(last_entry.published_at || last_entry.inserted_at)
                     |> Integer.to_string()

      Map.put(response, :continuation, continuation)
    else
      response
    end
  end

  defp calculate_total_unread(user, subscriptions) do
    # Sum unread across all subscriptions
    Enum.reduce(subscriptions, 0, fn sub, acc ->
      acc + Content.count_unread_entries(user, feed_id: sub.feed_id)
    end)
  end

  defp get_newest_timestamp(user, opts) do
    case Content.list_entries(user, Keyword.merge(opts, limit: 1, order: :desc)) do
      [entry | _] -> datetime_to_usec(entry.published_at || entry.inserted_at)
      [] -> 0
    end
  end

  defp datetime_to_usec(%DateTime{} = dt) do
    DateTime.to_unix(dt, :microsecond)
  end

  defp datetime_to_usec(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:microsecond)
  end
end
