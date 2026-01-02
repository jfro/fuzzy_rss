defmodule FuzzyRssWeb.ReaderLive.FeedDiscover do
  use FuzzyRssWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, :current_user, assigns.current_user)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">Discover Feeds</h1>
      <p class="text-base-content/60">Feed discovery coming soon...</p>

      <div class="mt-8">
        <.link patch={~p"/app/feeds"} class="btn btn-ghost">← Back to Feeds</.link>
      </div>
    </div>
    """
  end
end
