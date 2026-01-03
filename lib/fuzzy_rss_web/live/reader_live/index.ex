defmodule FuzzyRssWeb.ReaderLive.Index do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Content

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FuzzyRss.PubSub, "user:#{socket.assigns.current_user.id}:feeds")
    end

    expanded_from_session =
      (session["expanded_folders"] || [])
      |> Enum.map(fn
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    socket =
      socket
      |> assign(:filter, :unread)
      |> assign(:selected_folder, nil)
      |> assign(:selected_feed, nil)
      |> assign(:entries, [])
      |> assign(:selected_entry, nil)
      |> assign(:view_mode, :list)
      |> assign(:page_mode, :reader)
      |> assign(:sidebar_tree, [])
      |> assign(:expanded_folders, expanded_from_session)
      |> allow_upload(:opml_file, accept: ~w(.xml), max_entries: 1)
      |> allow_upload(:starred_file, accept: ~w(.json), max_entries: 1)
      |> load_sidebar_data()
      |> load_entries()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case socket.assigns.live_action do
        action
        when action in [
               :feeds,
               :feeds_new,
               :feeds_discover,
               :folders,
               :settings,
               :settings_import_export,
               :account_settings
             ] ->
          assign(socket, :page_mode, :management)

        _ ->
          socket = assign(socket, :page_mode, :reader)

          case params do
            %{"feed_id" => feed_id} ->
              socket
              |> assign(:selected_feed, String.to_integer(feed_id))
              |> assign(:selected_folder, nil)
              |> assign(:filter, :unread)
              |> load_entries()

            %{"folder_id" => folder_id} ->
              socket
              |> assign(:selected_folder, String.to_integer(folder_id))
              |> assign(:selected_feed, nil)
              |> assign(:filter, :unread)
              |> load_entries()

            _ ->
              socket =
                socket
                |> assign(:selected_feed, nil)
                |> assign(:selected_folder, nil)

              case socket.assigns.live_action do
                :starred ->
                  socket
                  |> assign(:filter, :starred)
                  |> load_entries()

                _ ->
                  socket
                  |> assign(:filter, :unread)
                  |> load_entries()
              end
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("mark_read", %{"entry_id" => entry_id}, socket) do
    Content.mark_as_read(socket.assigns.current_user, String.to_integer(entry_id))
    {:noreply, load_entries(socket)}
  end

  @impl true
  def handle_event("toggle_starred", %{"entry_id" => entry_id}, socket) do
    entry_id = String.to_integer(entry_id)
    Content.toggle_starred(socket.assigns.current_user, entry_id)

    # Fetch fresh entry data with updated starred state
    fresh_entry = Content.get_entry!(entry_id) |> FuzzyRss.Repo.preload(:feed)
    state = Content.get_entry_state(socket.assigns.current_user, entry_id)

    fresh_entry =
      if state do
        Map.put(fresh_entry, :user_entry_states, [state])
      else
        Map.put(fresh_entry, :user_entry_states, [])
      end

    # Update the entry in the entries list to keep data in sync
    entries =
      Enum.map(socket.assigns.entries, fn e ->
        if e.id == entry_id, do: fresh_entry, else: e
      end)

    socket = assign(socket, :entries, entries)

    # Update selected_entry to the fresh version
    selected_entry =
      if socket.assigns.selected_entry && socket.assigns.selected_entry.id == entry_id,
        do: fresh_entry,
        else: socket.assigns.selected_entry

    {:noreply, assign(socket, :selected_entry, selected_entry)}
  end

  @impl true
  def handle_event("mark_all_read", _params, socket) do
    opts = [feed_id: socket.assigns.selected_feed, folder_id: socket.assigns.selected_folder]
    Content.mark_all_as_read(socket.assigns.current_user, opts)
    {:noreply, load_entries(socket)}
  end

  @impl true
  def handle_event("toggle_feed_filter", _params, socket) do
    # Only allow toggling when viewing a specific feed or folder
    if socket.assigns.selected_feed || socket.assigns.selected_folder do
      new_filter = if socket.assigns.filter == :unread, do: :all, else: :unread

      socket
      |> assign(:filter, new_filter)
      |> load_entries()
      |> then(&{:noreply, &1})
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_entry", %{"entry_id" => entry_id}, socket) do
    entry_id = String.to_integer(entry_id)
    entry = Enum.find(socket.assigns.entries, &(&1.id == entry_id))

    socket =
      if entry do
        # Mark as read in database
        Content.mark_as_read(socket.assigns.current_user, entry_id)

        # Fetch updated entry state to show read status in list
        state = Content.get_entry_state(socket.assigns.current_user, entry_id)

        updated_entry =
          if state do
            Map.put(entry, :user_entry_states, [state])
          else
            Map.put(entry, :user_entry_states, [])
          end

        # Update the entry in the entries list to reflect read state
        entries =
          Enum.map(socket.assigns.entries, fn e ->
            if e.id == entry_id, do: updated_entry, else: e
          end)

        socket
        |> assign(:entries, entries)
        |> assign(:selected_entry, updated_entry)
      else
        assign(socket, :selected_entry, entry)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_folder", %{"folder_id" => folder_id}, socket) do
    folder_id = String.to_integer(folder_id)
    expanded = socket.assigns.expanded_folders

    new_expanded =
      if MapSet.member?(expanded, folder_id) do
        MapSet.delete(expanded, folder_id)
      else
        MapSet.put(expanded, folder_id)
      end

    {:noreply,
     socket
     |> assign(:expanded_folders, new_expanded)
     |> push_event("update_expanded_folders_cookie", %{folder_ids: MapSet.to_list(new_expanded)})}
  end

  @impl true
  def handle_event("refresh_feed", %{"feed_id" => feed_id}, socket) do
    Content.refresh_feed(String.to_integer(feed_id))
    {:noreply, load_sidebar_data(socket)}
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

    Logger.debug("Index: Starting OPML import, uploads: #{inspect(socket.assigns.uploads)}")

    uploaded_files =
      consume_uploaded_entries(socket, :opml_file, fn %{path: path}, _entry ->
        Logger.debug("Index: Reading file from #{path}")
        {:ok, File.read!(path)}
      end)

    Logger.debug("Index: Consumed #{Enum.count(uploaded_files)} files")

    case uploaded_files do
      [xml | _] ->
        Logger.debug("Index: Importing OPML, size: #{byte_size(xml)}")

        case FuzzyRss.Feeds.OPML.import(xml, user) do
          {:ok, results} ->
            message =
              "Imported #{results.created_feeds} feeds and #{results.created_folders} folders"

            Logger.info("Index: #{message}")

            {:noreply,
             socket
             |> put_flash(:info, message)
             |> load_sidebar_data()
             |> load_entries()}

          {:error, reason} ->
            Logger.error("Index: Import failed: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end

      [] ->
        Logger.warning("Index: No files uploaded")
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
        case FuzzyRss.Feeds.FreshRSSJSON.import_starred(json, user) do
          {:ok, results} ->
            message =
              "Imported #{results.imported} starred articles (#{results.errors} errors)"

            {:noreply,
             socket
             |> put_flash(:info, message)
             |> load_entries()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "No file uploaded")}
    end
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
        |> load_sidebar_data()
        |> load_entries()
        |> then(&{:noreply, &1})

      {:ok, :unsubscribed} ->
        socket
        |> put_flash(:info, "Unsubscribed successfully.")
        |> load_sidebar_data()
        |> load_entries()
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
  def handle_info({:feed_updated, _feed}, socket) do
    socket
    |> load_sidebar_data()
    |> load_entries()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info({:import_completed, :opml}, socket) do
    socket
    |> load_sidebar_data()
    |> load_entries()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info({:import_completed, :starred}, socket) do
    socket
    |> load_entries()
    |> then(&{:noreply, &1})
  end

  defp is_read?(entry) do
    Enum.any?(entry.user_entry_states, & &1.read)
  end

  defp extract_feeds_from_tree(tree_nodes) do
    Enum.flat_map(tree_nodes, fn node ->
      case node.type do
        :feed -> [node.data]
        :folder -> extract_feeds_from_tree(node.children)
      end
    end)
  end

  defp load_sidebar_data(socket) do
    user = socket.assigns.current_user
    sidebar_tree = Content.build_sidebar_tree(user)
    unread_counts = Content.get_unread_counts(user)
    feeds = extract_feeds_from_tree(sidebar_tree)
    folders = Content.list_user_folders(user)

    socket
    |> assign(:sidebar_tree, sidebar_tree)
    |> assign(:feeds, feeds)
    |> assign(:folders, folders)
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
