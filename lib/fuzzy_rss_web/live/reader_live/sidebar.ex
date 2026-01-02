defmodule FuzzyRssWeb.ReaderLive.Sidebar do
  use FuzzyRssWeb, :live_component

  defp is_selected_folder?(node, live_action, selected_folder) do
    live_action == :folder and node.id == selected_folder
  end

  defp is_selected_feed?(node, live_action, selected_feed) do
    live_action == :feed and node.id == selected_feed
  end

  defp render_tree_node(
         node,
         expanded_folders,
         level,
         live_action,
         selected_feed,
         selected_folder
       ) do
    indent_px = min(level, 5) * 16

    case node.type do
      :folder ->
        is_expanded = MapSet.member?(expanded_folders, node.id)
        is_selected = is_selected_folder?(node, live_action, selected_folder)

        assigns = %{
          node: node,
          is_expanded: is_expanded,
          is_selected: is_selected,
          indent_px: indent_px,
          level: level,
          expanded_folders: expanded_folders,
          live_action: live_action,
          selected_feed: selected_feed,
          selected_folder: selected_folder
        }

        ~H"""
        <div>
          <div
            class={"flex items-center transition-colors pr-4 #{if @is_selected, do: "bg-primary/20", else: "hover:bg-base-300"}"}
            style={"padding-left: #{@indent_px}px"}
          >
            <button
              phx-click="toggle_folder"
              phx-value-folder_id={@node.id}
              class="btn btn-xs btn-ghost btn-square flex-shrink-0 p-0"
              title={if @is_expanded, do: "Collapse", else: "Expand"}
            >
              <.icon
                name={if @is_expanded, do: "hero-chevron-down", else: "hero-chevron-right"}
                class="size-3"
              />
            </button>

            <.icon name="hero-folder" class="size-4 flex-shrink-0 opacity-60" />

            <.link
              patch={~p"/app/folder/#{@node.id}"}
              class="flex-1 flex items-center justify-between py-2 text-xs min-w-0"
            >
              <span class="truncate">{@node.data.name}</span>
              <%= if @node.unread_count > 0 do %>
                <span class="badge badge-xs badge-primary flex-shrink-0 ml-2">
                  {@node.unread_count}
                </span>
              <% end %>
            </.link>
          </div>

          <%= if @is_expanded and length(@node.children) > 0 do %>
            <%= for child <- @node.children do %>
              {render_tree_node(
                child,
                @expanded_folders,
                @level + 1,
                @live_action,
                @selected_feed,
                @selected_folder
              )}
            <% end %>
          <% end %>
        </div>
        """

      :feed ->
        feed_indent_px = indent_px + 32
        is_selected = is_selected_feed?(node, live_action, selected_feed)

        assigns = %{
          node: node,
          feed_indent_px: feed_indent_px,
          is_selected: is_selected,
          live_action: live_action,
          selected_feed: selected_feed,
          selected_folder: selected_folder
        }

        ~H"""
        <.link
          patch={~p"/app/feed/#{@node.id}"}
          class={"flex items-center transition-colors px-4 py-2 text-xs #{if @is_selected, do: "bg-primary/20", else: "hover:bg-base-300"}"}
          style={"padding-left: #{@feed_indent_px}px"}
        >
          <.icon name="hero-rss" class="size-3 flex-shrink-0 opacity-60 mr-2" />
          <span class="flex-1 truncate">{@node.data.title || @node.data.url}</span>
          <%= if @node.unread_count > 0 do %>
            <span class="badge badge-xs badge-primary flex-shrink-0 ml-2">
              {@node.unread_count}
            </span>
          <% end %>
        </.link>
        """
    end
  end

  def render(assigns) do
    ~H"""
    <aside class="w-64 flex-shrink-0 bg-base-200 overflow-y-auto flex flex-col border-r border-base-300">
      <div class="p-4 border-b border-base-300">
        <h1 class="text-2xl font-bold text-primary">📰 FuzzyRSS</h1>
        <%= if @current_user do %>
          <p class="text-xs text-base-content/60 mt-1">{@current_user.email}</p>
        <% end %>
      </div>

      <div class="flex-1 overflow-y-auto">
        <div class="py-2">
          <div class="px-4 py-2">
            <span class="font-semibold text-sm text-base-content/70">Views</span>
          </div>
          <.link
            patch={~p"/app"}
            class={[
              "flex items-center gap-2 px-4 py-2 text-xs transition-colors",
              if(@live_action == :index, do: "bg-primary/20", else: "hover:bg-base-300")
            ]}
          >
            <.icon name="hero-newspaper" class="size-4 flex-shrink-0 opacity-60" />
            <span>All Unread</span>
          </.link>
          <.link
            patch={~p"/app/starred"}
            class={[
              "flex items-center gap-2 px-4 py-2 text-xs transition-colors",
              if(@live_action == :starred, do: "bg-primary/20", else: "hover:bg-base-300")
            ]}
          >
            <.icon name="hero-star" class="size-4 flex-shrink-0 opacity-60" />
            <span>Starred</span>
          </.link>
        </div>

        <div class="divider my-0"></div>

        <div class="px-4 py-2 flex items-center justify-between">
          <span class="font-semibold text-sm text-base-content/70">Feeds & Folders</span>
          <div class="flex gap-1">
            <.link
              patch={~p"/app/feeds"}
              class="btn btn-xs btn-circle btn-ghost"
              title="Manage feeds"
            >
              <.icon name="hero-cog-6-tooth" class="size-3" />
            </.link>
            <.link
              patch={~p"/app/feeds/new"}
              class="btn btn-xs btn-circle btn-ghost"
              title="Add feed"
            >
              <.icon name="hero-plus" class="size-3" />
            </.link>
          </div>
        </div>

        <div id="sidebar-tree" phx-hook="FolderTree" data-user-id={@current_user.id} class="space-y-0">
          <%= if Enum.empty?(@sidebar_tree) do %>
            <div class="px-4 py-2 text-xs opacity-50">No feeds yet</div>
          <% else %>
            <%= for node <- @sidebar_tree do %>
              {render_tree_node(
                node,
                @expanded_folders,
                0,
                @live_action,
                @selected_feed,
                @selected_folder
              )}
            <% end %>
          <% end %>
        </div>
      </div>

      <div class="border-t border-base-300 py-2">
        <.link
          patch={~p"/app/settings"}
          class={[
            "flex items-center gap-2 px-4 py-2 text-xs transition-colors",
            if(@live_action in [:settings, :settings_import_export, :account_settings],
              do: "bg-primary/20",
              else: "hover:bg-base-300"
            )
          ]}
        >
          <.icon name="hero-cog-6-tooth" class="size-4 flex-shrink-0 opacity-60" />
          <span>Settings</span>
        </.link>
        <.link
          href={~p"/users/log-out"}
          method="delete"
          class="flex items-center gap-2 px-4 py-2 text-xs transition-colors hover:bg-base-300"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-4 flex-shrink-0 opacity-60" />
          <span>Log out</span>
        </.link>
      </div>
    </aside>
    """
  end
end
