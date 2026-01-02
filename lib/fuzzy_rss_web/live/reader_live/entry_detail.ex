defmodule FuzzyRssWeb.ReaderLive.EntryDetail do
  use FuzzyRssWeb, :live_component

  defp is_starred?(entry) do
    Enum.any?(entry.user_entry_states, & &1.starred)
  end

  def render(assigns) do
    assigns = assign(assigns, :is_starred, is_starred?(assigns.selected_entry))

    ~H"""
    <article class="w-1/2 bg-base-100 overflow-y-auto border-l border-base-300">
      <div class="p-6">
        <div class="mb-6">
          <h1 class="text-3xl font-bold mb-3">{@selected_entry.title}</h1>

          <div class="flex flex-wrap gap-2 items-center text-sm mb-4">
            <div class="badge badge-primary badge-outline">{@selected_entry.feed.title}</div>
            <span class="text-base-content/60">
              {Calendar.strftime(@selected_entry.published_at, "%B %d, %Y")}
            </span>
            <%= if @selected_entry.author do %>
              <span class="text-base-content/60">by {@selected_entry.author}</span>
            <% end %>
          </div>

          <div class="flex gap-2">
            <button
              phx-click="toggle_starred"
              phx-value-entry_id={@selected_entry.id}
              class={
                if @is_starred,
                  do: "btn btn-sm btn-primary gap-2",
                  else: "btn btn-sm btn-outline gap-2"
              }
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-4 w-4"
                fill={if @is_starred, do: "currentColor", else: "none"}
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"
                />
              </svg>
              {if @is_starred, do: "Starred", else: "Star"}
            </button>
            <%= if @selected_entry.url do %>
              <a href={@selected_entry.url} target="_blank" class="btn btn-sm btn-outline gap-2">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-4 w-4"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                  />
                </svg>
                Open Original
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
            {raw(@selected_entry.content)}
          <% else %>
            <%= if @selected_entry.summary do %>
              <p>{@selected_entry.summary}</p>
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
              <div class="badge badge-secondary badge-outline">{category}</div>
            <% end %>
          </div>
        <% end %>
      </div>
    </article>
    """
  end
end
