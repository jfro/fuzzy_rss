defmodule FuzzyRssWeb.ReaderLive.Index do
  use FuzzyRssWeb, :live_view

  alias FuzzyRss.Content
  alias FuzzyRss.Accounts

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

    layout_mode =
      (socket.assigns.current_user.preferences || %{})
      |> Map.get("layout_mode", "vertical")

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
      |> assign(:layout_mode, layout_mode)
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
  def handle_event("set_layout_mode", %{"mode" => mode}, socket)
      when mode in ["vertical", "horizontal"] do
    case Accounts.update_user_preference(socket.assigns.current_user, "layout_mode", mode) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:layout_mode, mode)
         |> assign(:current_user, updated_user)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update layout preference")}
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
  def handle_event("mark_all_read", _params, socket) do
    opts = [
      feed_id: socket.assigns.selected_feed,
      folder_id: socket.assigns.selected_folder
    ]

    Content.mark_all_as_read(socket.assigns.current_user, opts)

    socket
    |> load_sidebar_data()
    |> load_entries()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_event("toggle_feed_filter", _params, socket) do
    new_filter = if socket.assigns.filter == :unread, do: :all, else: :unread

    socket
    |> assign(:filter, new_filter)
    |> load_entries()
    |> then(&{:noreply, &1})
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

  @impl true
  def handle_info(:reload_entries, socket) do
    socket
    |> load_sidebar_data()
    |> load_entries()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info({:filter_changed, new_filter}, socket) do
    socket
    |> assign(:filter, new_filter)
    |> load_entries()
    |> then(&{:noreply, &1})
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
