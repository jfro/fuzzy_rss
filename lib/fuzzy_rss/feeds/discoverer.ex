defmodule FuzzyRss.Feeds.Discoverer do
  @moduledoc "Discover feeds from website URLs"

  def find_feeds(url) do
    case Req.get(url, max_redirects: 5) do
      {:ok, response} ->
        feeds = extract_feed_urls(response.body, url)

        if Enum.empty?(feeds) do
          try_common_paths(url)
        else
          {:ok, feeds}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def find_favicon(site_url) when is_binary(site_url) do
    case Req.get(site_url, max_redirects: 5, receive_timeout: 10_000) do
      {:ok, response} ->
        case Floki.parse_document(response.body) do
          {:ok, document} ->
            favicon =
              document
              |> Floki.find(
                "link[rel~='icon'], link[rel~='shortcut icon'], link[rel='apple-touch-icon']"
              )
              |> Enum.find_value(fn link ->
                case Floki.attribute(link, "href") do
                  [href | _] -> resolve_url(href, site_url)
                  _ -> nil
                end
              end)

            if favicon do
              {:ok, favicon}
            else
              fallback_favicon(site_url)
            end

          _ ->
            fallback_favicon(site_url)
        end

      _ ->
        fallback_favicon(site_url)
    end
  end

  def find_favicon(_), do: {:error, :invalid_url}

  defp fallback_favicon(site_url) do
    uri = URI.parse(site_url)
    fallback = "#{uri.scheme}://#{uri.host}/favicon.ico"

    case Req.head(fallback) do
      {:ok, %{status: status}} when status in 200..299 -> {:ok, fallback}
      _ -> {:error, :not_found}
    end
  end

  defp extract_feed_urls(html, base_url) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.find(
          "link[rel~='alternate'][type*='rss'], link[rel~='alternate'][type*='atom'], link[rel~='alternate'][type*='feed']"
        )
        |> Enum.map(fn link ->
          case Floki.attribute(link, "href") do
            [href | _] -> resolve_url(href, base_url)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp resolve_url(url, base) when is_binary(url) and byte_size(url) > 0 do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") -> url
      String.starts_with?(url, "//") -> "https:" <> url
      String.starts_with?(url, "/") -> URI.parse(base) |> URI.merge(url) |> URI.to_string()
      true -> url
    end
  end

  defp resolve_url(_, _), do: nil

  defp try_common_paths(base_url) do
    paths = ["/feed", "/rss", "/atom.xml", "/feed.xml", "/rss.xml"]

    feeds =
      paths
      |> Enum.filter(fn path ->
        url = base_url <> path

        case Req.head(url) do
          {:ok, %{status: status}} when status in 200..299 -> true
          _ -> false
        end
      end)
      |> Enum.map(fn path -> base_url <> path end)

    if Enum.empty?(feeds) do
      {:error, :no_feeds_found}
    else
      {:ok, feeds}
    end
  end
end
