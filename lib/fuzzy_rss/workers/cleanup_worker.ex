defmodule FuzzyRss.Workers.CleanupWorker do
  use Oban.Worker, queue: :default

  import Ecto.Query
  alias FuzzyRss.Content.Entry

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  @impl Oban.Worker
  def perform(_job) do
    # Delete entries older than 90 days that are not starred
    cutoff_date = DateTime.utc_now() |> DateTime.add(-90, :day)

    from(e in Entry,
      left_join: ues in assoc(e, :user_entry_states),
      where: e.published_at < ^cutoff_date,
      where: is_nil(ues.starred) or ues.starred == false
    )
    |> repo().delete_all()

    :ok
  end
end
