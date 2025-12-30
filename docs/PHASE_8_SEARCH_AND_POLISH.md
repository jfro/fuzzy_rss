# Phase 8: Search & Polish

**Duration:** Week 7-8 (2-3 days)
**Previous Phase:** [Phase 7: REST API](PHASE_7_REST_API.md)
**Next Phase:** [Phase 9: Testing & Deployment](PHASE_9_TESTING_AND_DEPLOYMENT.md)

## Overview

Add full-text search, keyboard shortcuts, and UX enhancements for a polished experience.

## 8.1: Full-Text Search (Database-Agnostic)

The search implementation is in Phase 3 (Content context). Ensure it's properly integrated:

```elixir
# In lib/fuzzy_rss/content.ex
def search_entries(user, query) do
  adapter = Application.fetch_env!(:fuzzy_rss, FuzzyRss.Repo)[:adapter]

  from e in Entry,
    join: s in Subscription,
      on: s.feed_id == e.feed_id and s.user_id == ^user.id,
    where: search_where_clause(adapter, query),
    order_by: [desc: e.published_at],
    limit: 100

  |> Repo.all()
end

# Database-specific implementations
defp search_where_clause(Ecto.Adapters.MyXQL, query) do
  dynamic([e], fragment(
    "MATCH(title, content) AGAINST (? IN NATURAL LANGUAGE MODE)",
    ^query
  ))
end

defp search_where_clause(Ecto.Adapters.Postgres, query) do
  dynamic([e], fragment(
    "to_tsvector('english', title || ' ' || coalesce(content, '')) @@ plainto_tsquery('english', ?)",
    ^query
  ))
end

defp search_where_clause(Ecto.Adapters.SQLite3, query) do
  search_pattern = "%#{query}%"
  dynamic([e], fragment(
    "(title LIKE ? OR content LIKE ?)",
    ^search_pattern,
    ^search_pattern
  ))
end

defp search_where_clause(_, query) do
  search_pattern = "%#{query}%"
  dynamic([e], fragment(
    "(title LIKE ? OR content LIKE ?)",
    ^search_pattern,
    ^search_pattern
  ))
end
```

## 8.2: Keyboard Shortcuts

Create `assets/js/hooks/keyboard_shortcuts.js`:

```javascript
export const KeyboardShortcuts = {
  mounted() {
    this.handleKeyPress = (e) => {
      // Ignore if user is typing in input
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
        return;
      }

      switch (e.key) {
        case 'j':
          this.pushEvent('select_next_entry', {});
          break;
        case 'k':
          this.pushEvent('select_prev_entry', {});
          break;
        case 'm':
          this.pushEvent('mark_read', {});
          break;
        case 's':
          this.pushEvent('toggle_starred', {});
          break;
        case 'o':
          if (this.el.dataset.entryUrl) {
            window.open(this.el.dataset.entryUrl, '_blank');
          }
          break;
        case '/':
          e.preventDefault();
          document.querySelector('[data-search-input]')?.focus();
          break;
        case 'r':
          this.pushEvent('refresh_feeds', {});
          break;
        case '?':
          this.pushEvent('show_help', {});
          break;
      }
    };

    window.addEventListener('keydown', this.handleKeyPress);
  },

  destroyed() {
    window.removeEventListener('keydown', this.handleKeyPress);
  }
};
```

Register in `assets/js/app.js`:

```javascript
import { KeyboardShortcuts } from "./hooks/keyboard_shortcuts"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {...colocatedHooks, KeyboardShortcuts},
})
```

## 8.3: UX Enhancements

### Loading States

Add skeleton loaders in LiveView templates:

```heex
<div :if={Enum.empty?(@entries)} class="p-4 text-center">
  <.empty_state message="No articles to display" />
</div>

<div :if={@loading} class="space-y-2 p-4">
  <div class="skeleton h-12 w-full"></div>
  <div class="skeleton h-12 w-full"></div>
  <div class="skeleton h-12 w-full"></div>
</div>
```

### Toast Notifications

```elixir
# In LiveView
def handle_event("mark_read", %{"entry_id" => entry_id}, socket) do
  Content.mark_as_read(socket.assigns.current_user, entry_id)

  socket =
    socket
    |> put_flash(:info, "Marked as read")
    |> load_entries()

  {:noreply, socket}
end
```

### Optimistic UI Updates

```javascript
// Optimistic update before server confirmation
function markAsRead(entryId) {
  const el = document.querySelector(`[data-entry-id="${entryId}"]`);
  if (el) {
    el.classList.add('opacity-50');
  }
  // Server will update
}
```

### Reading Time Estimation

```elixir
# In Content context
def reading_time(content) when is_binary(content) do
  word_count =
    content
    |> Floki.text()
    |> String.split()
    |> length()

  # Average 200 words per minute
  minutes = div(word_count, 200)
  minutes
end
```

Display in template:

```heex
<span class="text-sm text-base-content/60">
  <%= @entry |> FuzzyRss.Content.reading_time() %> min read
</span>
```

### Smooth Transitions

Add to `assets/css/app.css`:

```css
@layer components {
  .entry-card {
    @apply transition-colors duration-200;
  }

  .entry-card.read {
    @apply bg-base-200/50 opacity-75;
  }

  .entry-card:hover {
    @apply bg-base-200;
  }

  .btn {
    @apply transition-all duration-150;
  }
}
```

## Completion Checklist

- [ ] Search function working with database adapter
- [ ] Keyboard shortcuts implemented
- [ ] Toast notifications for user feedback
- [ ] Loading skeletons in place
- [ ] Empty states added
- [ ] Smooth transitions and animations
- [ ] Reading time calculations
- [ ] Optimistic UI updates
- [ ] Tested with `mix phx.server`

## Testing Search

```bash
# Start app
mix phx.server

# Search in UI, verify results match different databases
```

## Next Steps

Proceed to [Phase 9: Testing & Deployment](PHASE_9_TESTING_AND_DEPLOYMENT.md).
