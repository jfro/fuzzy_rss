defmodule FuzzyRss.Feeds.Extractor do
  @moduledoc "Extract full article content from URLs"

  def extract_article(url) do
    with {:ok, response} <- Req.get(url, max_redirects: 5, receive_timeout: 30_000),
         {:ok, document} <- Floki.parse_document(response.body) do
      readable = Readability.summarize(document)

      {:ok,
       %{
         content: Readability.readable_html(readable),
         title: Readability.title(readable),
         excerpt: extract_excerpt(readable)
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_excerpt(readable) do
    content = Readability.readable_text(readable)

    content
    |> String.slice(0, 300)
    |> String.trim()
  end
end
