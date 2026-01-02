defmodule FuzzyRssWeb.SettingsLive.Index do
  use FuzzyRssWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">Settings</h1>

      <div class="grid gap-4">
        <.link
          navigate={~p"/app/settings/import-export"}
          class="card bg-base-100 shadow hover:shadow-lg transition-shadow"
        >
          <div class="card-body">
            <h2 class="card-title">Import & Export</h2>
            <p class="text-base-content/60">Manage your subscriptions and starred articles</p>
          </div>
        </.link>

        <.link
          navigate={~p"/app/feeds"}
          class="card bg-base-100 shadow hover:shadow-lg transition-shadow"
        >
          <div class="card-body">
            <h2 class="card-title">Manage Feeds</h2>
            <p class="text-base-content/60">View and manage your feed subscriptions</p>
          </div>
        </.link>

        <.link
          navigate={~p"/app/folders"}
          class="card bg-base-100 shadow hover:shadow-lg transition-shadow"
        >
          <div class="card-body">
            <h2 class="card-title">Manage Folders</h2>
            <p class="text-base-content/60">Organize your feeds into folders</p>
          </div>
        </.link>

        <.link
          navigate={~p"/users/settings"}
          class="card bg-base-100 shadow hover:shadow-lg transition-shadow"
        >
          <div class="card-body">
            <h2 class="card-title">Account Settings</h2>
            <p class="text-base-content/60">Update your email and password</p>
          </div>
        </.link>
      </div>

      <div class="mt-8">
        <.link navigate={~p"/app"} class="btn btn-ghost">
          ← Back to Reader
        </.link>
      </div>
    </div>
    """
  end
end
