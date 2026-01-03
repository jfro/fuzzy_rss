defmodule FuzzyRssWeb.ReaderLive.EntryDetail do
  use FuzzyRssWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, :layout_mode, assigns[:layout_mode] || "vertical")
    {:ok, socket}
  end

  defp is_starred?(entry) do
    Enum.any?(entry.user_entry_states, & &1.starred)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :is_starred, is_starred?(assigns.selected_entry))

    ~H"""
    <article
      :if={assigns[:layout_mode] != "horizontal"}
      class="flex-1 bg-base-100 overflow-y-auto border-l border-base-300 min-w-0 hidden lg:block"
    >
      <div class="p-6">
        <div class="mb-6">
          <h1 class="text-3xl font-bold mb-3">{@selected_entry.title}</h1>

          <div class="flex flex-wrap gap-x-3 gap-y-2 items-center text-sm mb-4">
            <div class="inline-flex items-center rounded-lg border border-primary/30 bg-primary/5 px-2.5 py-1 text-xs font-semibold text-primary transition-colors max-w-full">
              <span class="break-words">{@selected_entry.feed.title}</span>
            </div>
            <div class="flex items-center gap-1.5 text-base-content/60 shrink-0">
              <.icon name="hero-calendar" class="size-4" />
              <span>{Calendar.strftime(@selected_entry.published_at, "%B %d, %Y")}</span>
            </div>
            <%= if @selected_entry.author do %>
              <div class="flex items-center gap-1.5 text-base-content/60 shrink-0">
                <.icon name="hero-user" class="size-4" />
                <span>{@selected_entry.author}</span>
              </div>
            <% end %>
          </div>

          <div class="flex gap-2">
            <button
              phx-click="toggle_starred"
              phx-value-entry_id={@selected_entry.id}
              class={[
                "btn btn-sm gap-2",
                if(@is_starred, do: "btn-primary", else: "btn-outline")
              ]}
            >
              <.icon
                name={if @is_starred, do: "hero-star-solid", else: "hero-star"}
                class="h-4 w-4"
              />
              {if @is_starred, do: "Starred", else: "Star"}
            </button>
            <%= if @selected_entry.url do %>
              <a href={@selected_entry.url} target="_blank" class="btn btn-sm btn-outline gap-2">
                <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> Open Original
              </a>
            <% end %>
          </div>
        </div>

        <div class="divider"></div>

        <%= if @selected_entry.image_url do %>
          <figure class="mb-6">
            <img src={@selected_entry.image_url} alt="" class="rounded-lg w-full" />
          </figure>
        <% end %>

        <div class="prose prose-sm lg:prose-base max-w-none">
          <%= if @selected_entry.content do %>
            {raw(sanitize_content(@selected_entry.content))}
          <% else %>
            <%= if @selected_entry.summary do %>
              <p>{raw(sanitize_summary(@selected_entry.summary))}</p>
            <% else %>
              <div class="alert alert-info">
                <span>No content available for this entry.</span>
              </div>
            <% end %>
          <% end %>
        </div>

        <%= if not Enum.empty?(@selected_entry.categories) do %>
          <div class="divider"></div>
          <div class="flex flex-wrap gap-2">
            <%= for category <- @selected_entry.categories do %>
              <div class="badge badge-secondary badge-outline h-auto py-1 px-3 whitespace-normal text-center">
                {category}
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </article>
    """
  end
end
