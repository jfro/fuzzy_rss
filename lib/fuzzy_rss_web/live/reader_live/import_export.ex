defmodule FuzzyRssWeb.ReaderLive.ImportExport do
  use FuzzyRssWeb, :live_component

  alias FuzzyRss.Feeds.{OPML, FreshRSSJSON}

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:current_user, assigns.current_user)
      |> assign(:opml_file_upload, assigns.opml_file_upload)
      |> assign(:starred_file_upload, assigns.starred_file_upload)
      |> assign(:opml_filename, "fuzzyrss-subscriptions.opml")
      |> assign(:freshrss_filename, "fuzzyrss-starred.json")

    {:ok, socket}
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
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <div class="mb-6">
        <.link patch={~p"/app/settings"} class="btn btn-ghost btn-sm">← Settings</.link>
      </div>

      <h1 class="text-3xl font-bold mb-6">Import & Export</h1>
      
    <!-- OPML Section -->
      <div class="card bg-base-100 shadow-md mb-6">
        <div class="card-body">
          <h2 class="card-title text-lg">OPML Subscriptions</h2>
          <p class="text-sm text-base-content/60">
            Export your feed subscriptions in OPML format for use in other RSS readers.
          </p>

          <div class="card-actions mt-4">
            <button class="btn btn-primary" phx-click="export_opml" phx-target={@myself}>
              Download OPML
            </button>
          </div>

          <div class="divider">or</div>

          <p class="text-sm text-base-content/60 mb-3">Import subscriptions from an OPML file.</p>

          <form
            phx-submit="import_opml"
            phx-change="validate_opml"
            enctype="multipart/form-data"
          >
            <div class="form-control">
              <.live_file_input
                upload={@opml_file_upload}
                class="file-input file-input-bordered w-full"
                required
              />
              <button type="submit" class="btn btn-primary mt-2">Import OPML</button>
            </div>
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
            <button class="btn btn-primary" phx-click="export_starred" phx-target={@myself}>
              Download Starred Articles
            </button>
          </div>

          <div class="divider">or</div>

          <p class="text-sm text-base-content/60 mb-3">
            Import starred articles from a FreshRSS JSON file.
          </p>

          <form
            phx-submit="import_starred"
            phx-change="validate_starred"
            enctype="multipart/form-data"
          >
            <div class="form-control">
              <.live_file_input
                upload={@starred_file_upload}
                class="file-input file-input-bordered w-full"
                required
              />
              <button type="submit" class="btn btn-primary mt-2">Import Starred</button>
            </div>
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
          >
          </path>
        </svg>
        <span>
          OPML files can be imported from any RSS reader that supports the format. Starred
          articles can only be imported from FreshRSS JSON exports.
        </span>
      </div>
    </div>
    """
  end
end
