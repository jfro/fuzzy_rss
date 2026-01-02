defmodule FuzzyRss.Feeds.Fetcher do
  @moduledoc "HTTP fetching with conditional requests and error handling"

  require Logger

  def fetch_feed(feed) do
    headers = conditional_headers(feed)
    Logger.info("Fetcher: Requesting #{feed.url}")

    case Req.get(feed.url, headers: headers, max_redirects: 5, receive_timeout: 30_000) do
      {:ok, response} ->
        Logger.info(
          "Fetcher: Got #{response.status} from #{feed.url}, body size: #{byte_size(response.body)}"
        )

        {:ok, response.body}

      {:error, reason} ->
        Logger.error("Fetcher: Request failed for #{feed.url}: #{inspect(reason)}")
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
