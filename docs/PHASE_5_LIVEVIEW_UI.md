# Phase 5: LiveView UI

**Duration:** Week 3-4 (4-5 days)
**Previous Phase:** [Phase 4: Feed Processing](PHASE_4_FEED_PROCESSING.md)
**Next Phase:** [Phase 6: PWA Features](PHASE_6_PWA_FEATURES.md)

## Overview

Build the main reader interface using Phoenix LiveView with real-time updates, feed management, and settings pages.

## 5.1: Router Updates

Update `lib/fuzzy_rss_web/router.ex`:

```elixir
scope "/app", FuzzyRssWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :authenticated,
    on_mount: [{FuzzyRssWeb.UserAuth, :ensure_authenticated}] do

    live "/", ReaderLive.Index, :index
    live "/folder/:folder_id", ReaderLive.Index, :folder
    live "/feed/:feed_id", ReaderLive.Index, :feed
    live "/starred", ReaderLive.Index, :starred

    live "/feeds", FeedLive.Index, :index
    live "/feeds/new", FeedLive.Form, :new
    live "/feeds/discover", FeedLive.Discover, :discover

    live "/folders", FolderLive.Index, :index

    live "/settings", SettingsLive.Index, :index
    live "/settings/import-export", SettingsLive.ImportExport, :import_export
  end
end
```

## 5.2: Main Reader LiveView

Create `lib/fuzzy_rss_web/live/reader_live/index.ex`:

```elixir
defmodule FuzzyRssWeb.ReaderLive.Index do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Content

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FuzzyRss.PubSub, "user:#{socket.assigns.current_user.id}:feeds")
    end

    socket =
      socket
      |> assign(:filter, :unread)
      |> assign(:selected_folder, nil)
      |> assign(:selected_feed, nil)
      |> assign(:entries, [])
      |> assign(:selected_entry, nil)
      |> assign(:view_mode, :list)
      |> load_sidebar_data()
      |> load_entries()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case params do
        %{"feed_id" => feed_id} ->
          socket
          |> assign(:selected_feed, feed_id)
          |> assign(:filter, :all)
          |> load_entries()

        %{"folder_id" => folder_id} ->
          socket
          |> assign(:selected_folder, folder_id)
          |> load_entries()

        %{"filter" => filter} ->
          socket
          |> assign(:filter, String.to_atom(filter))
          |> load_entries()

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_read", %{"entry_id" => entry_id}, socket) do
    Content.mark_as_read(socket.assigns.current_user, entry_id)
    {:noreply, load_entries(socket)}
  end

  @impl true
  def handle_event("toggle_starred", %{"entry_id" => entry_id}, socket) do
    Content.toggle_starred(socket.assigns.current_user, entry_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    opts = [feed_id: socket.assigns.selected_feed, folder_id: socket.assigns.selected_folder]
    Content.mark_all_as_read(socket.assigns.current_user, opts)
    {:noreply, load_entries(socket)}
  end

  @impl true
  def handle_info({:feed_updated, _feed}, socket) do
    {:noreply, load_entries(socket)}
  end

  defp load_sidebar_data(socket) do
    user = socket.assigns.current_user
    folders = Content.list_user_folders(user)
    feeds = Content.list_user_feeds(user)
    unread_counts = Content.get_unread_counts(user)

    socket
    |> assign(:folders, folders)
    |> assign(:feeds, feeds)
    |> assign(:unread_counts, unread_counts)
  end

  defp load_entries(socket) do
    user = socket.assigns.current_user
    filter = socket.assigns.filter
    folder_id = socket.assigns.selected_folder
    feed_id = socket.assigns.selected_feed

    opts = [
      filter: filter,
      folder_id: folder_id,
      feed_id: feed_id,
      limit: 50
    ]

    entries = Content.list_entries(user, opts)
    assign(socket, :entries, entries)
  end
end
```

Template `lib/fuzzy_rss_web/live/reader_live/index.html.heex`:

```heex
<div class="flex h-screen">
  <!-- Sidebar -->
  <.live_component module={FuzzyRssWeb.ReaderLive.Sidebar} id="sidebar" {...assigns} />

  <!-- Main Content -->
  <div class="flex-1 flex flex-col">
    <!-- Entry List -->
    <.live_component module={FuzzyRssWeb.ReaderLive.EntryList} id="entry_list" {...assigns} />

    <!-- Entry Detail -->
    <% if assigns.selected_entry do %>
      <.live_component module={FuzzyRssWeb.ReaderLive.EntryDetail} id="entry_detail" {...assigns} />
    <% end %>
  </div>
</div>
```

## 5.3: Components

### Sidebar Component

Create `lib/fuzzy_rss_web/live/reader_live/sidebar.ex`:

```elixir
defmodule FuzzyRssWeb.ReaderLive.Sidebar do
  use FuzzyRssWeb, :live_component

  def render(assigns) do
    ~H"""
    <aside class="w-64 bg-base-200 overflow-y-auto">
      <div class="p-4">
        <h1 class="text-xl font-bold">FuzzyRSS</h1>
      </div>

      <nav class="p-4 space-y-2">
        <div class="font-semibold mb-3">Folders</div>
        <%= for folder <- @folders do %>
          <.link navigate={~p"/app/folder/#{folder.id}"} class="block p-2 rounded hover:bg-base-300">
            <%= folder.name %>
            <span class="float-right badge"><%= Map.get(@unread_counts, folder.id, 0) %></span>
          </.link>
        <% end %>

        <div class="font-semibold mt-6 mb-3">Subscriptions</div>
        <%= for feed <- @feeds do %>
          <.link navigate={~p"/app/feed/#{feed.id}"} class="block p-2 rounded hover:bg-base-300">
            <%= feed.title %>
            <span class="float-right badge"><%= Map.get(@unread_counts, feed.id, 0) %></span>
          </.link>
        <% end %>
      </nav>
    </aside>
    """
  end
end
```

### Entry List Component

Create `lib/fuzzy_rss_web/live/reader_live/entry_list.ex`:

```elixir
defmodule FuzzyRssWeb.ReaderLive.EntryList do
  use FuzzyRssWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="flex-1 border-r overflow-y-auto">
      <div class="p-4 border-b flex gap-2">
        <.button phx-click="mark_all_read">Mark All Read</.button>
      </div>

      <div id="entries" phx-update="stream">
        <%= for {_id, entry} <- @streams.entries do %>
          <.entry_card entry={entry} {...assigns} />
        <% end %>
      </div>
    </div>
    """
  end
end
```

### Entry Detail Component

Create `lib/fuzzy_rss_web/live/reader_live/entry_detail.ex`:

```elixir
defmodule FuzzyRssWeb.ReaderLive.EntryDetail do
  use FuzzyRssWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="w-96 bg-base-200 overflow-y-auto p-4">
      <h2 class="text-lg font-bold"><%= @selected_entry.title %></h2>
      <p class="text-sm text-base-content/60"><%= @selected_entry.feed.title %></p>

      <div class="mt-4 prose prose-sm max-w-none">
        <%= raw(@selected_entry.content) %>
      </div>

      <div class="mt-4 flex gap-2">
        <.button phx-click="toggle_starred" phx-value-entry-id={@selected_entry.id}>
          Star
        </.button>
        <.link href={@selected_entry.url} target="_blank" class="btn btn-sm">
          Open
        </.link>
      </div>
    </div>
    """
  end
end
```

## 5.4: Settings & Import/Export UI

Create `lib/fuzzy_rss_web/live/settings_live/import_export.ex`:

```elixir
defmodule FuzzyRssWeb.SettingsLive.ImportExport do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Feeds.{OPML, FreshRSSJSON}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:opml_filename, "fuzzyrss-subscriptions.opml")
     |> assign(:freshrss_filename, "fuzzyrss-starred.json")}
  end

  @impl true
  def handle_event("export_opml", _params, socket) do
    user = socket.assigns.current_user

    case OPML.export(user) do
      {:ok, xml} ->
        {:noreply,
         socket
         |> put_flash(:info, "OPML exported successfully")
         |> push_event("download_file", %{
           content: xml,
           filename: socket.assigns.opml_filename,
           type: "text/xml"
         })}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to export OPML")}
    end
  end

  @impl true
  def handle_event("export_starred", _params, socket) do
    user = socket.assigns.current_user

    case FreshRSSJSON.export_starred(user) do
      {:ok, json} ->
        {:noreply,
         socket
         |> put_flash(:info, "Starred articles exported")
         |> push_event("download_file", %{
           content: json,
           filename: socket.assigns.freshrss_filename,
           type: "application/json"
         })}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to export starred articles")}
    end
  end

  @impl true
  def handle_event("import_opml", %{"file" => file}, socket) do
    user = socket.assigns.current_user

    case file_to_string(file) do
      {:ok, xml} ->
        case OPML.import(xml, user) do
          {:ok, results} ->
            message =
              "Imported #{results.created_feeds} feeds and #{results.created_folders} folders"

            {:noreply, put_flash(socket, :info, message)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to read file")}
    end
  end

  @impl true
  def handle_event("import_starred", %{"file" => file}, socket) do
    user = socket.assigns.current_user

    case file_to_string(file) do
      {:ok, json} ->
        case FreshRSSJSON.import_starred(json, user) do
          {:ok, results} ->
            message =
              "Imported #{results.imported} starred articles (#{results.errors} errors)"

            {:noreply, put_flash(socket, :info, message)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to read file")}
    end
  end

  defp file_to_string(file) do
    case file do
      %{path: path} ->
        {:ok, File.read!(path)}

      _ ->
        {:error, :invalid_file}
    end
  end
end
```

Template `lib/fuzzy_rss_web/live/settings_live/import_export.html.heex`:

```heex
<div class="max-w-2xl mx-auto p-6">
  <h1 class="text-3xl font-bold mb-6">Import & Export</h1>

  <!-- OPML Section -->
  <div class="card bg-base-100 shadow-md mb-6">
    <div class="card-body">
      <h2 class="card-title text-lg">OPML Subscriptions</h2>
      <p class="text-sm text-base-content/60">
        Export your feed subscriptions in OPML format for use in other RSS readers.
      </p>

      <div class="card-actions mt-4">
        <button class="btn btn-primary" phx-click="export_opml">
          Download OPML
        </button>
      </div>

      <div class="divider">or</div>

      <p class="text-sm text-base-content/60 mb-3">
        Import subscriptions from an OPML file.
      </p>

      <form phx-change="import_opml" class="flex gap-2">
        <input
          type="file"
          name="file"
          accept=".opml,.xml"
          class="file-input file-input-bordered w-full max-w-xs"
        />
      </form>
    </div>
  </div>

  <!-- FreshRSS Starred Articles Section -->
  <div class="card bg-base-100 shadow-md mb-6">
    <div class="card-body">
      <h2 class="card-title text-lg">Starred Articles</h2>
      <p class="text-sm text-base-content/60">
        Export your starred articles in FreshRSS JSON format.
      </p>

      <div class="card-actions mt-4">
        <button class="btn btn-primary" phx-click="export_starred">
          Download Starred Articles
        </button>
      </div>

      <div class="divider">or</div>

      <p class="text-sm text-base-content/60 mb-3">
        Import starred articles from a FreshRSS JSON file.
      </p>

      <form phx-change="import_starred" class="flex gap-2">
        <input
          type="file"
          name="file"
          accept=".json"
          class="file-input file-input-bordered w-full max-w-xs"
        />
      </form>
    </div>
  </div>

  <!-- Info Card -->
  <div class="alert alert-info">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      class="stroke-current shrink-0 w-6 h-6"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      ></path>
    </svg>
    <span>
      OPML files can be imported from any RSS reader that supports the format. Starred
      articles can only be imported from FreshRSS JSON exports.
    </span>
  </div>
</div>
```

Add download handler to `assets/js/app.js`:

```javascript
window.addEventListener("phx:download_file", (event) => {
  const { content, filename, type } = event.detail;
  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
});
```

## 5.5: Enhanced CoreComponents

Add to `lib/fuzzy_rss_web/components/core_components.ex`:

```elixir
@doc "Entry card with image, title, summary, metadata"
attr :entry, :map, required: true
def entry_card(assigns) do
  ~H"""
  <div class="border-b p-4 hover:bg-base-300 cursor-pointer">
    <h3 class="font-semibold"><%= @entry.title %></h3>
    <p class="text-sm text-base-content/60"><%= @entry.feed.title %></p>
    <p class="text-sm mt-2 line-clamp-2"><%= Enum.join(@entry.categories, ", ") %></p>
  </div>
  """
end

@doc "Feed item in sidebar with unread badge"
attr :feed, :map, required: true
attr :unread_count, :integer, default: 0
def feed_item(assigns) do
  ~H"""
  <div class="flex justify-between items-center p-2">
    <span><%= @feed.title %></span>
    <span class="badge"><%= @unread_count %></span>
  </div>
  """
end
```

## Completion Checklist

- [ ] Updated router with authenticated routes
- [ ] Created ReaderLive.Index
- [ ] Created Sidebar component
- [ ] Created EntryList component
- [ ] Created EntryDetail component
- [ ] Added entry_card component
- [ ] Created SettingsLive.ImportExport component
- [ ] Added OPML import/export UI
- [ ] Added starred articles import/export UI
- [ ] Added download handler to app.js
- [ ] Verified compilation: `mix compile`
- [ ] Tested UI: `mix phx.server`

## Next Steps

Proceed to [Phase 6: PWA Features](PHASE_6_PWA_FEATURES.md).
