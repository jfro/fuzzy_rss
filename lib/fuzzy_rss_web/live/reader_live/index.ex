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
      |> assign(:show_feed_modal, false)
      |> assign(:show_add_feed_modal, false)
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
          |> assign(:selected_feed, String.to_integer(feed_id))
          |> assign(:filter, :all)
          |> load_entries()

        %{"folder_id" => folder_id} ->
          socket
          |> assign(:selected_folder, String.to_integer(folder_id))
          |> load_entries()

        _ ->
          case socket.assigns.live_action do
            :starred ->
              socket
              |> assign(:filter, :starred)
              |> load_entries()

            _ ->
              socket
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
    # Only allow toggling when viewing a specific feed
    if socket.assigns.selected_feed do
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
  def handle_event("toggle_feed_modal", _params, socket) do
    {:noreply, assign(socket, :show_feed_modal, !socket.assigns.show_feed_modal)}
  end

  @impl true
  def handle_event("toggle_add_feed_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_feed_modal, !socket.assigns.show_add_feed_modal)}
  end

  @impl true
  def handle_event("refresh_feed", %{"feed_id" => feed_id}, socket) do
    Content.refresh_feed(String.to_integer(feed_id))
    {:noreply, load_sidebar_data(socket)}
  end

  @impl true
  def handle_event("add_feed", %{"feed_url" => feed_url}, socket) do
    case Content.subscribe_to_feed(socket.assigns.current_user, feed_url) do
      {:ok, _feed} ->
        socket
        |> put_flash(:info, "Feed added successfully!")
        |> assign(:show_add_feed_modal, false)
        |> load_sidebar_data()
        |> load_entries()
        |> then(&{:noreply, &1})

      {:error, reason} ->
        socket
        |> put_flash(:error, "Failed to add feed: #{reason}")
        |> then(&{:noreply, &1})
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
  def handle_info({:toggle_feed_modal, _}, socket) do
    {:noreply, assign(socket, :show_feed_modal, !socket.assigns.show_feed_modal)}
  end

  defp is_read?(entry) do
    Enum.any?(entry.user_entry_states, & &1.read)
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
