defmodule FuzzyRss.Feeds.FreshRSSJSON do
  @moduledoc "FreshRSS JSON format import/export for starred articles"

  import Ecto.Query
  alias FuzzyRss.Content
  alias FuzzyRss.Content.{Entry, Subscription, UserEntryState, Feed}

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  def export_starred(user) do
    entries =
      from(e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        join: ues in UserEntryState,
        on: ues.entry_id == e.id and ues.user_id == ^user.id,
        where: s.user_id == ^user.id and ues.starred == true,
        order_by: [desc: e.published_at],
        select: e,
        preload: :feed
      )
      |> repo().all()

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
            {:ok, _} -> %{acc | imported: acc.imported + 1}
            _ -> %{acc | errors: acc.errors + 1}
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

    case repo().get_by(Feed, url: feed_url) do
      nil ->
        {:error, :feed_not_found}

      feed ->
        case repo().get_by(Entry, feed_id: feed.id, url: entry_url) do
          nil -> {:error, :entry_not_found}
          entry -> Content.toggle_starred(user, entry.id)
        end
    end
  end
end
