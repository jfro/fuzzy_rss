defmodule FuzzyRss.Workers.FeedSchedulerWorker do
  use Oban.Worker, queue: :default

  alias FuzzyRss.Content
  alias FuzzyRss.Workers.FeedFetcherWorker

  @impl Oban.Worker
  def perform(_job) do
    # Query feeds that need updating
    feeds = Content.feeds_due_for_fetch()

    Enum.each(feeds, fn feed ->
      %{feed_id: feed.id}
      |> FeedFetcherWorker.new()
      |> Oban.insert()
    end)

    :ok
  end
end
