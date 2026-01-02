defmodule FuzzyRss.Workers.EntryExtractorWorker do
  use Oban.Worker, queue: :extractor

  alias FuzzyRss.Content
  alias FuzzyRss.Content.Entry
  alias FuzzyRss.Feeds.Extractor

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => entry_id}}) do
    entry = Content.get_entry!(entry_id)

    with {:ok, extracted} <- Extractor.extract_article(entry.url) do
      entry
      |> Entry.changeset(%{
        extracted_content: extracted.content,
        extracted_at: DateTime.utc_now()
      })
      |> repo().update()

      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
