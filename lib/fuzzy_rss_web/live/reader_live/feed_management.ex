defmodule FuzzyRssWeb.ReaderLive.FeedManagement do
  use FuzzyRssWeb, :live_component

  alias FuzzyRss.Content

  @impl true
  def update(assigns, socket) do
    user = assigns.current_user
    feeds = Content.list_user_feeds(user)

    socket =
      socket
      |> assign(:current_user, assigns.current_user)
      |> assign(:feeds, feeds)

    {:ok, socket}
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
  def handle_event("unsubscribe_feed", %{"feed_id" => feed_id}, socket) do
    feed_id = String.to_integer(feed_id)

    case Content.unsubscribe_from_feed(socket.assigns.current_user, feed_id) do
      {:ok, :feed_deleted} ->
        socket
        |> put_flash(
          :info,
          "Unsubscribed successfully. Feed was removed (you were the last subscriber)."
        )
        |> assign(:feeds, Content.list_user_feeds(socket.assigns.current_user))
        |> then(&{:noreply, &1})

      {:ok, :unsubscribed} ->
        socket
        |> put_flash(:info, "Unsubscribed successfully.")
        |> assign(:feeds, Content.list_user_feeds(socket.assigns.current_user))
        |> then(&{:noreply, &1})

      {:ok, :not_subscribed} ->
        socket
        |> put_flash(:error, "You are not subscribed to this feed.")
        |> then(&{:noreply, &1})

      {:error, _reason} ->
        socket
        |> put_flash(:error, "Failed to unsubscribe from feed.")
        |> then(&{:noreply, &1})
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Manage Feeds</h1>
        <div class="flex gap-2">
          <button phx-click="refresh_all" phx-target={@myself} class="btn btn-secondary">
            Refresh All
          </button>
          <.link patch={~p"/app/feeds/new"} class="btn btn-primary">Add Feed</.link>
        </div>
      </div>

      <div class="grid gap-4">
        <%= for feed <- @feeds do %>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <div class="flex justify-between items-start">
                <div class="flex items-start gap-3 flex-1">
                  <%= if feed.favicon_url do %>
                    <img src={feed.favicon_url} class="size-8 rounded-md mt-1" />
                  <% else %>
                    <div class="size-8 bg-base-300 rounded-md flex items-center justify-center mt-1">
                      <.icon name="hero-rss" class="size-5 opacity-40" />
                    </div>
                  <% end %>
                  <div class="flex-1 min-w-0">
                    <h2 class="card-title truncate">{feed.title || feed.url}</h2>
                    <p class="text-sm text-base-content/60 truncate">{feed.url}</p>
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
                </div>
                <div class="flex gap-2">
                  <button
                    phx-click="refresh_feed"
                    phx-value-feed_id={feed.id}
                    phx-target={@myself}
                    class="btn btn-sm btn-ghost"
                  >
                    ↻ Refresh
                  </button>
                  <button
                    phx-click="unsubscribe_feed"
                    phx-value-feed_id={feed.id}
                    phx-target={@myself}
                    class="btn btn-sm btn-ghost text-error"
                    data-confirm="Are you sure you want to unsubscribe from this feed?"
                  >
                    Unsubscribe
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <div class="mt-8">
        <.link patch={~p"/app"} class="btn btn-ghost">← Back to Reader</.link>
      </div>
    </div>
    """
  end
end
