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
      |> assign(:layout_mode, assigns.layout_mode)

    {:ok, socket}
  end

  @impl true
  def handle_event("mark_read", %{"entry_id" => entry_id}, socket) do
    Content.mark_as_read(socket.assigns.current_user, String.to_integer(entry_id))
    send(self(), :reload_entries)
    {:noreply, socket}
  end

  defp is_read?(entry) do
    Enum.any?(entry.user_entry_states, & &1.read)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={[
      "flex-1 flex bg-base-100 min-w-0",
      if(@layout_mode == "horizontal", do: "flex-row", else: "flex-col")
    ]}>
      <!-- List Pane: Header + Entry List -->
      <div class={[
        "flex flex-col bg-base-100 min-w-0",
        if(@layout_mode == "horizontal", do: "w-[450px] border-r", else: "h-1/2 border-b")
      ]}>
        <!-- Header with Layout Toggle -->
        <div class="flex flex-col bg-base-200 border-b border-base-300 px-4 py-3 gap-3">
          <div class="flex items-center justify-between min-w-0">
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
            
    <!-- Layout Mode Toggle -->
            <div class="flex gap-1 shrink-0">
              <button
                phx-click="set_layout_mode"
                phx-value-mode="vertical"
                class={[
                  "btn btn-xs gap-1",
                  if(@layout_mode == "vertical", do: "btn-primary", else: "btn-ghost")
                ]}
                title="Vertical layout (list on top, article below)"
              >
                <.icon name="hero-rectangle-stack" class="h-4 w-4" />
              </button>
              <button
                phx-click="set_layout_mode"
                phx-value-mode="horizontal"
                class={[
                  "btn btn-xs gap-1",
                  if(@layout_mode == "horizontal", do: "btn-primary", else: "btn-ghost")
                ]}
                title="Horizontal layout (sidebar, list, and article side-by-side)"
              >
                <.icon name="hero-view-columns" class="h-4 w-4" />
              </button>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <%= if @selected_feed || @selected_folder do %>
              <button
                phx-click="toggle_feed_filter"
                class="btn btn-sm btn-ghost bg-base-300/50 hover:bg-base-300 gap-2"
                title="Toggle between unread and all articles"
              >
                {if @filter == :unread, do: "📖 Unread", else: "📋 All"}
              </button>
            <% end %>
            <button phx-click="mark_all_read" class="btn btn-sm btn-ghost gap-2">
              <.icon name="hero-check" class="h-4 w-4" /> Mark All Read
            </button>
          </div>
        </div>
        
    <!-- Entry List -->
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
      </div>
      
    <!-- Entry Detail Pane -->
      <%= if @layout_mode == "horizontal" or @selected_entry do %>
        <.live_component
          module={FuzzyRssWeb.ReaderLive.EntryDetail}
          id="entry_detail"
          selected_entry={@selected_entry}
          layout_mode={@layout_mode}
        />
      <% end %>
    </div>
    """
  end
end
