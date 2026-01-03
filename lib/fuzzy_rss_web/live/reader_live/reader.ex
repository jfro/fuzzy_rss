defmodule FuzzyRssWeb.ReaderLive.Reader do
  use FuzzyRssWeb, :live_component

  alias FuzzyRss.Content

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:entries, assigns.entries)
      |> assign(:selected_entry, assigns.selected_entry)
      |> assign(:selected_feed, assigns.selected_feed)
      |> assign(:selected_folder, assigns.selected_folder)
      |> assign(:filter, assigns.filter)
      |> assign(:current_user, assigns.current_user)
      |> assign(:feeds, assigns.feeds)
      |> assign(:folders, assigns.folders)

    {:ok, socket}
  end

  @impl true
  def handle_event("mark_read", %{"entry_id" => entry_id}, socket) do
    Content.mark_as_read(socket.assigns.current_user, String.to_integer(entry_id))
    send(self(), :reload_entries)
    {:noreply, socket}
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
    send(self(), :reload_entries)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_feed_filter", _params, socket) do
    # Only allow toggling when viewing a specific feed or folder
    if socket.assigns.selected_feed || socket.assigns.selected_folder do
      new_filter = if socket.assigns.filter == :unread, do: :all, else: :unread
      send(self(), {:filter_changed, new_filter})
      {:noreply, socket}
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

  defp is_read?(entry) do
    Enum.any?(entry.user_entry_states, & &1.read)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col bg-base-100 min-w-0">
      <div class="flex flex-col bg-base-200 border-b border-base-300 px-4 py-3 gap-3">
        <div class="flex items-center min-w-0">
          <h2 class="text-xl font-bold flex items-center gap-2 min-w-0">
            <%= if @selected_feed do %>
              <% feed =
                Enum.find(@feeds, &(&1.id == @selected_feed)) ||
                  %{title: "Feed", favicon_url: nil} %>
              <%= if feed.favicon_url do %>
                <img src={feed.favicon_url} class="size-5 rounded-sm shrink-0" />
              <% end %>
              <span class="truncate">{feed.title}</span>
            <% else %>
              <%= if @selected_folder do %>
                <span class="truncate">
                  {(Enum.find(@folders, &(&1.id == @selected_folder)) || %{name: "Folder"}).name}
                </span>
              <% else %>
                {if @filter == :starred, do: "⭐ Starred", else: "📰 All Entries"}
              <% end %>
            <% end %>
          </h2>
        </div>
        <div class="flex items-center gap-2">
          <%= if @selected_feed || @selected_folder do %>
            <button
              phx-click="toggle_feed_filter"
              phx-target={@myself}
              class="btn btn-sm btn-ghost bg-base-300/50 hover:bg-base-300 gap-2"
              title="Toggle between unread and all articles"
            >
              {if @filter == :unread, do: "📖 Unread", else: "📋 All"}
            </button>
          <% end %>
          <button phx-click="mark_all_read" phx-target={@myself} class="btn btn-sm btn-ghost gap-2">
            <.icon name="hero-check" class="h-4 w-4" /> Mark All Read
          </button>
        </div>
      </div>

      <div class="overflow-y-auto overflow-x-hidden flex-1 min-w-0">
        <%= if Enum.empty?(@entries) do %>
          <div class="flex items-center justify-center h-full">
            <div class="text-center">
              <p class="text-base-content/60 text-lg">No entries to display</p>
              <p class="text-base-content/40 text-sm mt-2">Add some feeds to get started!</p>
            </div>
          </div>
        <% else %>
          <%= for entry <- @entries do %>
            <% read = is_read?(entry) %>
            <div
              phx-click="select_entry"
              phx-value-entry_id={entry.id}
              phx-target={@myself}
              class={"card card-compact bg-base-100 hover:bg-base-200 cursor-pointer transition-colors border-b border-base-300 rounded-none #{if @selected_entry && @selected_entry.id == entry.id, do: "bg-primary/20"} #{if read, do: "opacity-60"}"}
            >
              <div class="card-body overflow-hidden">
                <h3 class={"card-title text-base break-words #{if read, do: "font-normal text-base-content/70", else: "font-semibold"}"}>
                  {entry.title}
                </h3>
                <div class="flex gap-2 items-center text-xs text-base-content/60 flex-wrap">
                  <span class="badge badge-ghost badge-sm gap-1 max-w-[150px] sm:max-w-[200px]">
                    <%= if entry.feed.favicon_url do %>
                      <img src={entry.feed.favicon_url} class="size-3 rounded-sm shrink-0" />
                    <% end %>
                    <span class="truncate">{entry.feed.title}</span>
                  </span>
                  <span>·</span>
                  <span>{Calendar.strftime(entry.published_at, "%b %d, %Y")}</span>
                </div>
                <%= if entry.summary do %>
                  <p class={"text-sm line-clamp-2 break-words #{if read, do: "text-base-content/50", else: "text-base-content/80"}"}>
                    {raw(FuzzyRss.Html.sanitize_summary(entry.summary))}
                  </p>
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
      
    <!-- Entry Detail -->
      <%= if @selected_entry do %>
        <.live_component
          module={FuzzyRssWeb.ReaderLive.EntryDetail}
          id="entry_detail"
          selected_entry={@selected_entry}
        />
      <% end %>
    </div>
    """
  end
end
