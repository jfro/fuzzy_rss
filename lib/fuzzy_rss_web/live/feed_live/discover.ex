defmodule FuzzyRssWeb.FeedLive.Discover do
  use FuzzyRssWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">Discover Feeds</h1>
      <p class="text-base-content/60">Feed discovery coming soon...</p>

      <div class="mt-8">
        <.link navigate={~p"/app/feeds"} class="btn btn-ghost">← Back to Feeds</.link>
      </div>
    </div>
    """
  end
end
