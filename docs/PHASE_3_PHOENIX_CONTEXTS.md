# Phase 3: Phoenix Contexts

**Duration:** Week 2 (3-4 days)
**Previous Phase:** [Phase 2: Database Schema](PHASE_2_DATABASE_SCHEMA.md)
**Next Phase:** [Phase 4: Feed Processing](PHASE_4_FEED_PROCESSING.md)

## Overview

Build the Content context which contains all business logic for managing feeds, entries, folders, and subscriptions. This is the core layer between the database and UI.

## 3.1: Create Content Context

Create `lib/fuzzy_rss/content.ex` with all CRUD operations and query functions.

### Feed Management Functions

```elixir
def list_user_feeds(user) do
  from(s in Subscription,
    where: s.user_id == ^user.id,
    preload: :feed
  )
  |> Repo.all()
  |> Enum.map(& &1.feed)
end

def subscribe_to_feed(user, feed_url, opts \\ []) do
  # Find or create feed
  feed = Repo.get_by(Feed, url: feed_url) || create_feed(feed_url)

  # Create subscription
  %Subscription{}
  |> Subscription.changeset(%{
    user_id: user.id,
    feed_id: feed.id,
    folder_id: opts[:folder_id]
  })
  |> Repo.insert()
end

def unsubscribe_from_feed(user, feed_id) do
  Repo.delete_all(from(s in Subscription, where: s.user_id == ^user.id and s.feed_id == ^feed_id))
end

def update_subscription(subscription, attrs) do
  subscription
  |> Subscription.changeset(attrs)
  |> Repo.update()
end

defp create_feed(url) do
  %Feed{}
  |> Feed.changeset(%{url: url})
  |> Repo.insert!()
end
```

### Folder Management Functions

```elixir
def list_user_folders(user) do
  from(f in Folder, where: f.user_id == ^user.id)
  |> Repo.all()
end

def create_folder(user, attrs) do
  %Folder{}
  |> Folder.changeset(attrs |> Map.put("user_id", user.id))
  |> Repo.insert()
end

def update_folder(folder, attrs) do
  folder
  |> Folder.changeset(attrs)
  |> Repo.update()
end

def delete_folder(folder) do
  # Move subscriptions to root
  Repo.update_all(
    from(s in Subscription, where: s.folder_id == ^folder.id),
    set: [folder_id: nil]
  )

  Repo.delete(folder)
end
```

### Entry Query Functions

```elixir
def list_entries(user, opts \\ []) do
  filter = opts[:filter] || :all
  folder_id = opts[:folder_id]
  feed_id = opts[:feed_id]
  limit = opts[:limit] || 50
  offset = opts[:offset] || 0

  query =
    from e in Entry,
      join: s in Subscription, on: s.feed_id == e.feed_id,
      left_join: ues in UserEntryState, on: ues.entry_id == e.id and ues.user_id == ^user.id,
      where: s.user_id == ^user.id,
      order_by: [desc: e.published_at],
      limit: ^limit,
      offset: ^offset,
      preload: [:feed, :user_entry_states]

  query =
    case filter do
      :unread -> where(query, [e, ues], is_nil(ues.read) or ues.read == false)
      :starred -> where(query, [ues], ues.starred == true)
      _ -> query
    end

  query =
    if folder_id do
      where(query, [e, s, ues], s.folder_id == ^folder_id)
    else
      query
    end

  query =
    if feed_id do
      where(query, [e], e.feed_id == ^feed_id)
    else
      query
    end

  Repo.all(query)
end

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

def get_entry!(id) do
  Repo.get!(Entry, id)
end

def get_unread_counts(user) do
  from s in Subscription,
    left_join: e in Entry, on: e.feed_id == s.feed_id,
    left_join: ues in UserEntryState, on: ues.entry_id == e.id and ues.user_id == ^user.id,
    where: s.user_id == ^user.id and (is_nil(ues.read) or ues.read == false),
    group_by: s.feed_id,
    select: {s.feed_id, count(e.id)}

  |> Repo.all()
  |> Enum.into(%{}, &{elem(&1, 0), elem(&1, 1)})
end
```

### Entry State Functions

```elixir
def mark_as_read(user, entry_id) do
  %UserEntryState{}
  |> UserEntryState.changeset(%{
    user_id: user.id,
    entry_id: entry_id,
    read: true,
    read_at: DateTime.utc_now()
  })
  |> Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :entry_id])
end

def mark_as_unread(user, entry_id) do
  %UserEntryState{}
  |> UserEntryState.changeset(%{
    user_id: user.id,
    entry_id: entry_id,
    read: false
  })
  |> Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :entry_id])
end

def toggle_starred(user, entry_id) do
  case Repo.get_by(UserEntryState, user_id: user.id, entry_id: entry_id) do
    nil ->
      %UserEntryState{}
      |> UserEntryState.changeset(%{
        user_id: user.id,
        entry_id: entry_id,
        starred: true,
        starred_at: DateTime.utc_now()
      })
      |> Repo.insert()

    state ->
      state
      |> UserEntryState.changeset(%{
        starred: !state.starred,
        starred_at: if(!state.starred, do: DateTime.utc_now(), else: nil)
      })
      |> Repo.update()
  end
end

def mark_all_as_read(user, opts \\ []) do
  feed_id = opts[:feed_id]
  folder_id = opts[:folder_id]

  query =
    from e in Entry,
      join: s in Subscription, on: s.feed_id == e.feed_id,
      where: s.user_id == ^user.id

  query =
    if feed_id do
      where(query, [e], e.feed_id == ^feed_id)
    else
      query
    end

  query =
    if folder_id do
      where(query, [e, s], s.folder_id == ^folder_id)
    else
      query
    end

  entry_ids = query |> select([e], e.id) |> Repo.all()

  Repo.insert_all(
    UserEntryState,
    Enum.map(entry_ids, &%{
      user_id: user.id,
      entry_id: &1,
      read: true,
      read_at: DateTime.utc_now(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }),
    on_conflict: :replace_all,
    conflict_target: [:user_id, :entry_id]
  )
end
```

## Completion Checklist

- [ ] Created `lib/fuzzy_rss/content.ex` context module
- [ ] Implemented all feed management functions
- [ ] Implemented all folder management functions
- [ ] Implemented all entry query functions
- [ ] Implemented database-specific search functions
- [ ] Implemented all entry state functions
- [ ] Verified all functions compile with `mix compile`
- [ ] (Optional) Added tests in `test/fuzzy_rss/content_test.exs`

## Testing the Context

```bash
# Test basic functionality
iex -S mix

# Try it out
user = FuzzyRss.Accounts.get_user!(1)
FuzzyRss.Content.list_user_feeds(user)
FuzzyRss.Content.list_entries(user)
```

## Next Steps

Proceed to [Phase 4: Feed Processing](PHASE_4_FEED_PROCESSING.md) to implement the feed fetching and parsing services.
