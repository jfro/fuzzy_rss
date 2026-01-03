defmodule FuzzyRssWeb.ReaderLive.FeedManagement do
  use FuzzyRssWeb, :live_component

  alias FuzzyRss.Content
  alias FuzzyRss.Feeds.{OPML, FreshRSSJSON}

  @impl true
  def update(assigns, socket) do
    user = assigns.current_user
    feeds = Content.list_user_feeds(user)

    socket =
      socket
      |> assign(:current_user, assigns.current_user)
      |> assign(:feeds, feeds)
      |> assign(:active_tab, :feeds)
      |> assign(:opml_filename, "fuzzyrss-subscriptions.opml")
      |> assign(:freshrss_filename, "fuzzyrss-starred.json")

    # Only set up uploads if not already done
    socket =
      if socket.assigns[:uploads] do
        socket
      else
        socket
        |> allow_upload(:opml_file, accept: ~w(.xml), max_entries: 1)
        |> allow_upload(:starred_file, accept: ~w(.json), max_entries: 1)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_atom(tab))}
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
  def handle_event("export_opml", _params, socket) do
    user = socket.assigns.current_user
    {:ok, xml} = OPML.export(user)

    {:noreply,
     socket
     |> put_flash(:info, "OPML exported successfully")
     |> push_event("download_file", %{
       content: xml,
       filename: socket.assigns.opml_filename,
       type: "text/xml"
     })}
  end

  @impl true
  def handle_event("export_starred", _params, socket) do
    user = socket.assigns.current_user
    {:ok, json} = FreshRSSJSON.export_starred(user)

    {:noreply,
     socket
     |> put_flash(:info, "Starred articles exported")
     |> push_event("download_file", %{
       content: json,
       filename: socket.assigns.freshrss_filename,
       type: "application/json"
     })}
  end

  @impl true
  def handle_event("validate_opml", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_starred", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("import_opml", _params, socket) do
    require Logger
    user = socket.assigns.current_user

    Logger.debug(
      "ImportExport: Starting OPML import, uploads: #{inspect(socket.assigns.uploads)}"
    )

    uploaded_files =
      consume_uploaded_entries(socket, :opml_file, fn %{path: path}, _entry ->
        Logger.debug("ImportExport: Reading file from #{path}")
        {:ok, File.read!(path)}
      end)

    Logger.debug("ImportExport: Consumed #{Enum.count(uploaded_files)} files")

    case uploaded_files do
      [xml | _] ->
        Logger.debug("ImportExport: Importing OPML, size: #{byte_size(xml)}")

        case OPML.import(xml, user) do
          {:ok, results} ->
            message =
              "Imported #{results.created_feeds} feeds and #{results.created_folders} folders"

            Logger.info("ImportExport: #{message}")

            {:noreply,
             socket
             |> put_flash(:info, message)
             |> assign(:feeds, Content.list_user_feeds(user))}

          {:error, reason} ->
            Logger.error("ImportExport: Import failed: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end

      [] ->
        Logger.warning("ImportExport: No files uploaded")
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end

  @impl true
  def handle_event("import_starred", _params, socket) do
    user = socket.assigns.current_user

    uploaded_files =
      consume_uploaded_entries(socket, :starred_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case uploaded_files do
      [json | _] ->
        case FreshRSSJSON.import_starred(json, user) do
          {:ok, results} ->
            message =
              "Imported #{results.imported} starred articles (#{results.errors} errors)"

            {:noreply,
             socket
             |> put_flash(:info, message)
             |> assign(:feeds, Content.list_user_feeds(user))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold">Manage Feeds</h1>
      </div>

      <%!-- Tab Navigation --%>
      <div class="tabs tabs-bordered mb-6" role="tablist">
        <button
          id="feeds-tab"
          role="tab"
          phx-click="switch_tab"
          phx-value-tab="feeds"
          phx-target={@myself}
          class={["tab font-semibold", @active_tab == :feeds && "tab-active"]}
          aria-selected={@active_tab == :feeds}
        >
          My Feeds
        </button>
        <button
          id="import-export-tab"
          role="tab"
          phx-click="switch_tab"
          phx-value-tab="import_export"
          phx-target={@myself}
          class={["tab font-semibold", @active_tab == :import_export && "tab-active"]}
          aria-selected={@active_tab == :import_export}
        >
          Import & Export
        </button>
      </div>

      <%!-- My Feeds Tab --%>
      <%= if @active_tab == :feeds do %>
        <div id="feeds-panel">
          <div class="flex gap-2 mb-6">
            <button phx-click="refresh_all" phx-target={@myself} class="btn btn-secondary">
              Refresh All
            </button>
            <.link patch={~p"/app/feeds/new"} class="btn btn-primary">Add Feed</.link>
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
                            Last fetched: {Calendar.strftime(
                              feed.last_fetched_at,
                              "%Y-%m-%d %H:%M:%S"
                            )}
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
        </div>
      <% end %>

      <%!-- Import & Export Tab --%>
      <%= if @active_tab == :import_export do %>
        <div id="import-export-panel">
          <%!-- OPML Section --%>
          <div class="card bg-base-100 shadow-md mb-6">
            <div class="card-body">
              <h2 class="card-title text-lg">OPML Subscriptions</h2>
              <p class="text-sm text-base-content/60">
                Export your feed subscriptions in OPML format for use in other RSS readers.
              </p>

              <div class="card-actions mt-4">
                <button
                  id="export-opml-btn"
                  class="btn btn-primary"
                  phx-click="export_opml"
                  phx-target={@myself}
                >
                  Download OPML
                </button>
              </div>

              <div class="divider">or</div>

              <p class="text-sm text-base-content/60 mb-3">Import subscriptions from an OPML file.</p>

              <form
                id="import-opml-form"
                phx-submit="import_opml"
                phx-change="validate_opml"
                phx-target={@myself}
                enctype="multipart/form-data"
              >
                <div class="form-control">
                  <.live_file_input
                    upload={@uploads.opml_file}
                    class="file-input file-input-bordered w-full"
                    required
                  />
                  <button type="submit" class="btn btn-primary mt-2">Import OPML</button>
                </div>
              </form>
            </div>
          </div>

          <%!-- FreshRSS Starred Articles Section --%>
          <div class="card bg-base-100 shadow-md mb-6">
            <div class="card-body">
              <h2 class="card-title text-lg">Starred Articles</h2>
              <p class="text-sm text-base-content/60">
                Export your starred articles in FreshRSS JSON format.
              </p>

              <div class="card-actions mt-4">
                <button
                  id="export-starred-btn"
                  class="btn btn-primary"
                  phx-click="export_starred"
                  phx-target={@myself}
                >
                  Download Starred Articles
                </button>
              </div>

              <div class="divider">or</div>

              <p class="text-sm text-base-content/60 mb-3">
                Import starred articles from a FreshRSS JSON file.
              </p>

              <form
                id="import-starred-form"
                phx-submit="import_starred"
                phx-change="validate_starred"
                phx-target={@myself}
                enctype="multipart/form-data"
              >
                <div class="form-control">
                  <.live_file_input
                    upload={@uploads.starred_file}
                    class="file-input file-input-bordered w-full"
                    required
                  />
                  <button type="submit" class="btn btn-primary mt-2">Import Starred</button>
                </div>
              </form>
            </div>
          </div>

          <%!-- Info Card --%>
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
              >
              </path>
            </svg>
            <span>
              OPML files can be imported from any RSS reader that supports the format. Starred
              articles can only be imported from FreshRSS JSON exports.
            </span>
          </div>
        </div>
      <% end %>

      <div class="mt-8">
        <.link patch={~p"/app"} class="btn btn-ghost">← Back to Reader</.link>
      </div>
    </div>
    """
  end
end
