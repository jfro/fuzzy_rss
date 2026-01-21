defmodule FuzzyRss.Api.Fever do
  @moduledoc """
  Response formatters for the Fever API.

  Converts FuzzyRss data structures into Fever API-compliant formats.
  """

  alias FuzzyRss.Content

  @doc """
  Formats folders as Fever groups.

  Returns a list of maps with `:id` and `:title` keys.

  ## Examples

      iex> format_groups([%Folder{id: 1, name: "Tech"}])
      [%{id: 1, title: "Tech"}]
  """
  def format_groups(folders) do
    Enum.map(folders, fn folder ->
      %{
        id: folder.id,
        title: folder.name
      }
    end)
  end

  @doc """
  Formats subscriptions as Fever feeds.

  Returns a list of maps with feed metadata in Fever format.

  ## Examples

      iex> format_feeds([subscription])
      [%{id: 1, favicon_id: 1, title: "...", ...}]
  """
  def format_feeds(subscriptions) do
    Enum.map(subscriptions, fn subscription ->
      feed = subscription.feed

      %{
        id: feed.id,
        favicon_id: feed.id,
        title: feed.title,
        url: feed.url,
        site_url: feed.site_url || "",
        is_spark: 0,
        last_updated_on_time: datetime_to_unix(feed.last_successful_fetch_at || feed.inserted_at)
      }
    end)
  end

  @doc """
  Formats entries as Fever items with user-specific read/starred state.

  ## Examples

      iex> format_items([entry], user)
      [%{id: 1, feed_id: 1, title: "...", is_read: 0, is_saved: 0, ...}]
  """
  def format_items(entries, user) do
    # Preload user entry states for all entries
    entry_ids = Enum.map(entries, & &1.id)
    states = Content.get_entry_states(user, entry_ids)

    states_by_entry_id =
      states
      |> Enum.map(fn state -> {state.entry_id, state} end)
      |> Map.new()

    Enum.map(entries, fn entry ->
      state = Map.get(states_by_entry_id, entry.id)

      %{
        id: entry.id,
        feed_id: entry.feed_id,
        title: entry.title,
        author: entry.author || "",
        html: entry.content || entry.summary || "",
        url: entry.url,
        is_saved: if(state && state.starred, do: 1, else: 0),
        is_read: if(state && state.read, do: 1, else: 0),
        created_on_time: datetime_to_unix(entry.published_at)
      }
    end)
  end

  @doc """
  Creates feed-to-folder mappings for Fever feeds_groups.

  Returns a list of maps with `:group_id` and `:feed_ids` (comma-separated string).

  ## Examples

      iex> format_feeds_groups(subscriptions)
      [%{group_id: 1, feed_ids: "1,2,3"}]
  """
  def format_feeds_groups(subscriptions) do
    subscriptions
    |> Enum.filter(fn s -> not is_nil(s.folder_id) end)
    |> Enum.group_by(fn s -> s.folder_id end)
    |> Enum.map(fn {folder_id, subs} ->
      feed_ids =
        subs
        |> Enum.map(fn s -> s.feed_id end)
        |> Enum.sort()
        |> Enum.map(&Integer.to_string/1)
        |> Enum.join(",")

      %{
        group_id: folder_id,
        feed_ids: feed_ids
      }
    end)
  end

  # Helper: Convert DateTime/NaiveDateTime to Unix timestamp
  defp datetime_to_unix(%DateTime{} = dt) do
    DateTime.to_unix(dt)
  end

  defp datetime_to_unix(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end

  defp datetime_to_unix(nil), do: 0
end
