defmodule FuzzyRssWeb.ReaderLive.Sidebar do
  use FuzzyRssWeb, :live_component

  def handle_event("toggle_feed_modal", _params, socket) do
    send(socket.root_pid, {:toggle_feed_modal, {}})
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <aside class="w-64 bg-base-200 overflow-y-auto flex flex-col border-r border-base-300">
      <div class="p-4 border-b border-base-300">
        <h1 class="text-2xl font-bold text-primary">📰 FuzzyRSS</h1>
        <%= if @current_user do %>
          <p class="text-xs text-base-content/60 mt-1">{@current_user.email}</p>
        <% end %>
      </div>

      <div class="flex-1 overflow-y-auto">
        <ul class="menu menu-compact p-2">
          <li class="menu-title">
            <span>Views</span>
          </li>
          <li>
            <.link navigate={~p"/app"} class="gap-2">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-4 w-4 flex-shrink-0"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 20H5a2 2 0 01-2-2V6a2 2 0 012-2h10a2 2 0 012 2v1m2 13a2 2 0 01-2-2V7m2 13a2 2 0 002-2V9a2 2 0 00-2-2h-2m-4-3H9M7 16h6M7 8h6v4H7V8z"
                />
              </svg>
              <span>All Unread</span>
            </.link>
          </li>
          <li>
            <.link navigate={~p"/app/starred"} class="gap-2">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-4 w-4 flex-shrink-0"
                fill="none"
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
              <span>Starred</span>
            </.link>
          </li>
        </ul>

        <div class="divider my-0"></div>

        <ul class="menu menu-compact p-2">
          <li class="menu-title">
            <span>Folders</span>
          </li>
          <%= if Enum.empty?(@folders) do %>
            <li class="disabled"><a class="text-xs opacity-50">No folders</a></li>
          <% else %>
            <%= for folder <- @folders do %>
              <li>
                <.link navigate={~p"/app/folder/#{folder.id}"} class="flex items-center gap-2">
                  <span class="flex-1 truncate">{folder.name}</span>
                  <%= if Map.get(@unread_counts, folder.id, 0) > 0 do %>
                    <span class="badge badge-sm badge-primary flex-shrink-0">
                      {Map.get(@unread_counts, folder.id, 0)}
                    </span>
                  <% end %>
                </.link>
              </li>
            <% end %>
          <% end %>
        </ul>

        <div class="divider my-0"></div>

        <div class="px-4 py-2 flex items-center justify-between">
          <span class="font-semibold text-sm text-base-content/70">Feeds</span>
          <div class="flex gap-1">
            <button
              phx-click="toggle_feed_modal"
              class="btn btn-xs btn-circle btn-ghost"
              title="Manage feeds"
            >
              <.icon name="hero-cog-6-tooth" class="size-3" />
            </button>
            <button
              phx-click="toggle_add_feed_modal"
              class="btn btn-xs btn-circle btn-ghost"
              title="Add feed"
            >
              <.icon name="hero-plus" class="size-3" />
            </button>
          </div>
        </div>

        <div class="space-y-0">
          <%= if Enum.empty?(@feeds) do %>
            <div class="px-4 py-2 text-xs opacity-50">No feeds yet</div>
          <% else %>
            <%= for feed <- @feeds do %>
              <.link
                navigate={~p"/app/feed/#{feed.id}"}
                class="flex items-center justify-between px-4 py-2 text-xs hover:bg-base-300 transition-colors block w-full"
              >
                <span class="flex-1 truncate">{feed.title || feed.url}</span>
                <%= if Map.get(@unread_counts, feed.id, 0) > 0 do %>
                  <span class="badge badge-xs badge-primary flex-shrink-0 ml-2">
                    {Map.get(@unread_counts, feed.id, 0)}
                  </span>
                <% end %>
              </.link>
            <% end %>
          <% end %>
        </div>
      </div>

      <div class="border-t border-base-300">
        <ul class="menu menu-compact p-2">
          <li>
            <.link navigate={~p"/app/settings"} class="gap-2">
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
                  d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
              Settings
            </.link>
          </li>
          <li>
            <.link href={~p"/users/log-out"} method="delete" class="gap-2">
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
                  d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                />
              </svg>
              Log out
            </.link>
          </li>
        </ul>
      </div>
    </aside>
    """
  end
end
