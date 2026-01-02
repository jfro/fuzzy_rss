defmodule FuzzyRssWeb.FeedLive.Form do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :feed_url, "")}
  end

  @impl true
  def handle_event("save", %{"feed_url" => feed_url}, socket) do
    user = socket.assigns.current_user

    case Content.subscribe_to_feed(user, feed_url) do
      {:ok, _subscription} ->
        {:noreply,
         socket
         |> put_flash(:info, "Subscribed to feed successfully")
         |> push_navigate(to: ~p"/app/feeds")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to subscribe to feed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">Add Feed</h1>

      <form phx-submit="save" class="space-y-4">
        <div class="form-control">
          <label class="label">
            <span class="label-text">Feed URL</span>
          </label>
          <input
            type="url"
            name="feed_url"
            placeholder="https://example.com/feed.xml"
            class="input input-bordered w-full"
            required
          />
        </div>

        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary">Subscribe</button>
          <.link navigate={~p"/app/feeds"} class="btn btn-ghost">Cancel</.link>
        </div>
      </form>
    </div>
    """
  end
end
