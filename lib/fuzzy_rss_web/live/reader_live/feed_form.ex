defmodule FuzzyRssWeb.ReaderLive.FeedForm do
  use FuzzyRssWeb, :live_component

  alias FuzzyRss.Content

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:current_user, assigns.current_user)
      |> assign(:feed_url, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"feed_url" => feed_url}, socket) do
    user = socket.assigns.current_user

    case Content.subscribe_to_feed(user, feed_url) do
      {:ok, _subscription} ->
        {:noreply,
         socket
         |> put_flash(:info, "Subscribed to feed successfully")
         |> push_patch(to: ~p"/app/feeds")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to subscribe to feed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">Add Feed</h1>

      <form phx-submit="save" phx-target={@myself} class="space-y-4">
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
          <.link patch={~p"/app/feeds"} class="btn btn-ghost">Cancel</.link>
        </div>
      </form>
    </div>
    """
  end
end
