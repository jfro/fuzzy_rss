defmodule FuzzyRss.Api.GReader do
  @moduledoc """
  Response formatters for the Google Reader API.

  Converts FuzzyRss data structures into GReader API-compliant formats.
  """

  alias FuzzyRss.Api.GReader.IdConverter

  @doc """
  Formats a subscription with categories (folders).

  ## Examples

      iex> format_subscription(subscription, folder, user_id)
      %{
        id: "feed/https://example.com/feed",
        title: "My Feed",
        categories: [%{id: "user/123/label/Tech", label: "Tech"}],
        ...
      }

  """
  def format_subscription(subscription, folder, user_id) do
    feed = subscription.feed

    categories =
      if folder do
        [
          %{
            id: "user/#{user_id}/label/#{folder.name}",
            label: folder.name
          }
        ]
      else
        []
      end

    %{
      id: "feed/#{feed.url}",
      title: feed.title || feed.url,
      categories: categories,
      url: feed.url,
      htmlUrl: feed.site_url || feed.url,
      iconUrl: "",
      firstitemmsec: datetime_to_msec(feed.inserted_at)
    }
  end

  @doc """
  Formats an entry as a GReader item with state tags.

  ## Examples

      iex> format_item(entry, user)
      %{
        id: "tag:google.com,2005:reader/item/...",
        title: "Entry Title",
        categories: ["user/123/state/com.google/read", ...],
        ...
      }

  """
  def format_item(entry, user) do
    state = get_entry_state(entry, user)
    categories = build_state_tags(state, user.id)

    %{
      id: IdConverter.to_long_item_id(entry.id),
      crawlTimeMsec: datetime_to_msec(entry.inserted_at),
      timestampUsec: datetime_to_usec(entry.published_at || entry.inserted_at),
      published: DateTime.to_unix(entry.published_at || entry.inserted_at),
      title: entry.title,
      summary: %{
        content: entry.content || entry.summary || "",
        direction: "ltr"
      },
      author: entry.author,
      canonical: [%{href: entry.url}],
      alternate: [%{href: entry.url, type: "text/html"}],
      categories: categories,
      origin: %{
        streamId: "feed/#{entry.feed.url}",
        title: entry.feed.title,
        htmlUrl: entry.feed.site_url || entry.feed.url
      }
    }
  end

  @doc """
  Formats unread count structure.

  ## Examples

      iex> format_unread_count("feed/https://example.com", 5, timestamp)
      %{id: "feed/https://example.com", count: 5, newestItemTimestampUsec: timestamp}

  """
  def format_unread_count(stream_id, count, timestamp) do
    %{
      id: stream_id,
      count: count,
      newestItemTimestampUsec: timestamp
    }
  end

  @doc """
  Formats tag list with default state tags and user folders.

  ## Examples

      iex> format_tag_list(folders, user_id)
      [
        %{id: "user/123/state/com.google/reading-list", sortid: "01"},
        %{id: "user/123/state/com.google/starred", sortid: "02"},
        ...
      ]

  """
  def format_tag_list(folders, user_id) do
    default_tags = [
      %{
        id: "user/#{user_id}/state/com.google/reading-list",
        sortid: "01",
        type: "state"
      },
      %{
        id: "user/#{user_id}/state/com.google/starred",
        sortid: "02",
        type: "state"
      },
      %{
        id: "user/#{user_id}/state/com.google/read",
        sortid: "03",
        type: "state"
      }
    ]

    folder_tags =
      Enum.map(folders, fn folder ->
        %{
          id: "user/#{user_id}/label/#{folder.name}",
          sortid: "A#{String.pad_leading(to_string(folder.id), 8, "0")}",
          type: "folder"
        }
      end)

    default_tags ++ folder_tags
  end

  # Private helpers

  defp get_entry_state(entry, user) do
    Enum.find(entry.user_entry_states, &(&1.user_id == user.id))
  end

  defp build_state_tags(nil, user_id) do
    ["user/#{user_id}/state/com.google/reading-list"]
  end

  defp build_state_tags(state, user_id) do
    tags = ["user/#{user_id}/state/com.google/reading-list"]
    tags = if state.read, do: ["user/#{user_id}/state/com.google/read" | tags], else: tags
    tags = if state.starred, do: ["user/#{user_id}/state/com.google/starred" | tags], else: tags
    tags
  end

  defp datetime_to_msec(nil), do: DateTime.to_unix(DateTime.utc_now(), :millisecond)
  defp datetime_to_msec(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)

  defp datetime_to_msec(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:millisecond)
  end

  defp datetime_to_usec(nil), do: DateTime.to_unix(DateTime.utc_now(), :microsecond)
  defp datetime_to_usec(%DateTime{} = dt), do: DateTime.to_unix(dt, :microsecond)

  defp datetime_to_usec(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:microsecond)
  end
end
