defmodule FuzzyRssWeb.FeedLive.Index do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Content

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    feeds = Content.list_user_feeds(user)

    {:ok, assign(socket, :feeds, feeds)}
  end

  @impl true
  def handle_event("refresh_feed", %{"feed_id" => feed_id}, socket) do
    Content.refresh_feed(String.to_integer(feed_id))
    {:noreply, put_flash(socket, :info, "Feed refresh queued")}
  end

  @impl true
  def handle_event("refresh_all", _params, socket) do
    user = socket.assigns.current_user
    {:ok, count} = Content.refresh_all_feeds(user)
    {:noreply, put_flash(socket, :info, "Queued refresh for #{count} feeds")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Manage Feeds</h1>
        <div class="flex gap-2">
          <button phx-click="refresh_all" class="btn btn-secondary">Refresh All</button>
          <.link navigate={~p"/app/feeds/new"} class="btn btn-primary">Add Feed</.link>
        </div>
      </div>

      <div class="grid gap-4">
        <%= for feed <- @feeds do %>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <div class="flex justify-between items-start">
                <div class="flex-1">
                  <h2 class="card-title">{feed.title || feed.url}</h2>
                  <p class="text-sm text-base-content/60">{feed.url}</p>
                  <p class="text-xs text-base-content/40 mt-2">
                    <%= if feed.last_fetched_at do %>
                      Last fetched: {Calendar.strftime(feed.last_fetched_at, "%Y-%m-%d %H:%M:%S")}
                    <% else %>
                      Never fetched
                    <% end %>
                  </p>
                  <%= if feed.last_error do %>
                    <p class="text-xs text-error mt-1">Error: {feed.last_error}</p>
                  <% end %>
                </div>
                <button
                  phx-click="refresh_feed"
                  phx-value-feed_id={feed.id}
                  class="btn btn-sm btn-ghost"
                >
                  ↻ Refresh
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="mt-8">
        <.link navigate={~p"/app"} class="btn btn-ghost">← Back to Reader</.link>
      </div>
    </div>
    """
  end
end
