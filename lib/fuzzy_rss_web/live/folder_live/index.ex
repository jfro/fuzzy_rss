defmodule FuzzyRssWeb.FolderLive.Index do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Content

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    folders = Content.list_user_folders(user)

    {:ok, assign(socket, :folders, folders)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">Manage Folders</h1>

      <div class="grid gap-4">
        <%= for folder <- @folders do %>
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title">{folder.name}</h2>
              <p class="text-sm text-base-content/60">Slug: {folder.slug}</p>
            </div>
          </div>
        <% end %>
      </div>

      <%= if Enum.empty?(@folders) do %>
        <p class="text-center text-base-content/50 mt-8">No folders yet</p>
      <% end %>

      <div class="mt-8">
        <.link navigate={~p"/app"} class="btn btn-ghost">← Back to Reader</.link>
      </div>
    </div>
    """
  end
end
