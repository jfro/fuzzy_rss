defmodule FuzzyRssWeb.SettingsLive.ImportExport do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Feeds.{OPML, FreshRSSJSON}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:opml_filename, "fuzzyrss-subscriptions.opml")
     |> assign(:freshrss_filename, "fuzzyrss-starred.json")
     |> allow_upload(:opml_file,
       accept: ~w(.xml),
       max_entries: 1,
       auto_upload: true
     )
     |> allow_upload(:starred_file,
       accept: ~w(.json),
       max_entries: 1,
       auto_upload: true
     )}
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

    Logger.debug("ImportExport: Starting OPML import, uploads: #{inspect(socket.assigns.uploads)}")

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
            {:noreply, put_flash(socket, :info, message)}

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

            {:noreply, put_flash(socket, :info, message)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
  end
end
