# Phase 2: Database Schema

**Duration:** Week 1-2 (2-3 days)
**Previous Phase:** [Phase 1: Dependencies & Authentication](PHASE_1_DEPENDENCIES_AND_AUTH.md)
**Next Phase:** [Phase 3: Phoenix Contexts](PHASE_3_PHOENIX_CONTEXTS.md)

## Overview

Create the core database schema with migrations for all entities (folders, feeds, subscriptions, entries, and user entry states). This phase establishes the data model that all future code will work with.

## 2.1: Create Core Migrations

Run migrations in order:

### Migration 1: Add Oban Jobs Table

Create `priv/repo/migrations/*_add_oban_jobs_table.exs`:

```elixir
use Ecto.Migration

def up do
  Oban.Migration.up(version: 12)
end

def down do
  Oban.Migration.down(version: 1)
end
```

### Migration 2: Create Folders

Create `priv/repo/migrations/*_create_folders.exs`:

```elixir
create table(:folders) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :name, :string, null: false
  add :slug, :string, null: false
  add :parent_id, references(:folders, on_delete: :delete_all)
  add :position, :integer, default: 0
  timestamps()
end

create index(:folders, [:user_id])
create unique_index(:folders, [:user_id, :slug])
```

### Migration 3: Create Feeds

Create `priv/repo/migrations/*_create_feeds.exs`:

```elixir
create table(:feeds) do
  add :url, :string, null: false
  add :title, :string
  add :description, :text
  add :site_url, :string
  add :feed_type, :string # "rss" or "atom"
  add :last_fetched_at, :utc_datetime
  add :last_successful_fetch_at, :utc_datetime
  add :last_error, :text
  add :fetch_interval, :integer, default: 60 # minutes
  add :etag, :string
  add :last_modified, :string
  add :favicon_url, :string
  add :active, :boolean, default: true
  timestamps()
end

create unique_index(:feeds, [:url])
create index(:feeds, [:last_fetched_at])
```

### Migration 4: Create Subscriptions

Create `priv/repo/migrations/*_create_subscriptions.exs`:

```elixir
create table(:subscriptions) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :feed_id, references(:feeds, on_delete: :delete_all), null: false
  add :folder_id, references(:folders, on_delete: :nilify_all)
  add :title_override, :string
  add :position, :integer, default: 0
  add :muted, :boolean, default: false
  timestamps()
end

create unique_index(:subscriptions, [:user_id, :feed_id])
create index(:subscriptions, [:user_id, :folder_id])
```

### Migration 5: Create Entries

Create `priv/repo/migrations/*_create_entries.exs`:

```elixir
defmodule FuzzyRss.Repo.Migrations.CreateEntries do
  use Ecto.Migration

  def change do
    create table(:entries) do
      add :feed_id, references(:feeds, on_delete: :delete_all), null: false
      add :guid, :string, null: false
      add :url, :string
      add :title, :string
      add :author, :string
      add :content, :text
      add :summary, :text
      add :published_at, :utc_datetime
      add :extracted_content, :text
      add :extracted_at, :utc_datetime
      add :image_url, :string
      # Note: SQLite doesn't support arrays, use TEXT with JSON encoding instead
      add :categories, {:array, :string}, default: []
      timestamps()
    end

    create unique_index(:entries, [:feed_id, :guid])
    create index(:entries, [:feed_id, :published_at])

    # Database-specific full-text search setup
    case Application.fetch_env(:fuzzy_rss, FuzzyRss.Repo)[:adapter] do
      Ecto.Adapters.MyXQL ->
        # MySQL FULLTEXT index
        execute "CREATE FULLTEXT INDEX idx_entries_search ON entries(title, content)"

      Ecto.Adapters.Postgres ->
        # PostgreSQL GiST index for full-text search
        execute """
        CREATE INDEX idx_entries_search ON entries
        USING GiST(to_tsvector('english', title || ' ' || coalesce(content, '')))
        """

      Ecto.Adapters.SQLite3 ->
        # SQLite will use the title/content columns with LIKE queries
        # Or configure FTS5 virtual table if full-text search is critical
        :ok

      _ ->
        :ok
    end
  end
end
```

### Migration 6: Create User Entry States

Create `priv/repo/migrations/*_create_user_entry_states.exs`:

```elixir
create table(:user_entry_states) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :entry_id, references(:entries, on_delete: :delete_all), null: false
  add :read, :boolean, default: false
  add :starred, :boolean, default: false
  add :read_at, :utc_datetime
  add :starred_at, :utc_datetime
  timestamps()
end

create unique_index(:user_entry_states, [:user_id, :entry_id])
create index(:user_entry_states, [:user_id, :read, :starred])
```

## 2.2: Run Migrations

```bash
mix ecto.migrate
```

## 2.3: Create Ecto Schemas

Create schema files for each table in `lib/fuzzy_rss/content/`:

### Folder Schema

`lib/fuzzy_rss/content/folder.ex`:

```elixir
defmodule FuzzyRss.Content.Folder do
  use Ecto.Schema
  import Ecto.Changeset

  schema "folders" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0

    belongs_to :user, FuzzyRss.Accounts.User
    belongs_to :parent, FuzzyRss.Content.Folder

    has_many :children, FuzzyRss.Content.Folder, foreign_key: :parent_id
    has_many :subscriptions, FuzzyRss.Content.Subscription

    timestamps()
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :slug, :position, :user_id, :parent_id])
    |> validate_required([:name, :user_id])
    |> unique_constraint([:user_id, :slug])
  end
end
```

### Feed Schema

`lib/fuzzy_rss/content/feed.ex`:

```elixir
defmodule FuzzyRss.Content.Feed do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feeds" do
    field :url, :string
    field :title, :string
    field :description, :string
    field :site_url, :string
    field :feed_type, :string
    field :last_fetched_at, :utc_datetime
    field :last_successful_fetch_at, :utc_datetime
    field :last_error, :string
    field :fetch_interval, :integer, default: 60
    field :etag, :string
    field :last_modified, :string
    field :favicon_url, :string
    field :active, :boolean, default: true

    has_many :entries, FuzzyRss.Content.Entry
    has_many :subscriptions, FuzzyRss.Content.Subscription

    timestamps()
  end

  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [:url, :title, :description, :site_url, :feed_type, :fetch_interval, :active])
    |> validate_required([:url])
    |> unique_constraint(:url)
  end
end
```

### Subscription Schema

`lib/fuzzy_rss/content/subscription.ex`:

```elixir
defmodule FuzzyRss.Content.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :title_override, :string
    field :position, :integer, default: 0
    field :muted, :boolean, default: false

    belongs_to :user, FuzzyRss.Accounts.User
    belongs_to :feed, FuzzyRss.Content.Feed
    belongs_to :folder, FuzzyRss.Content.Folder

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:user_id, :feed_id, :folder_id, :title_override, :position, :muted])
    |> validate_required([:user_id, :feed_id])
    |> unique_constraint([:user_id, :feed_id])
  end
end
```

### Entry Schema

`lib/fuzzy_rss/content/entry.ex`:

```elixir
defmodule FuzzyRss.Content.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "entries" do
    field :guid, :string
    field :url, :string
    field :title, :string
    field :author, :string
    field :content, :string
    field :summary, :string
    field :published_at, :utc_datetime
    field :extracted_content, :string
    field :extracted_at, :utc_datetime
    field :image_url, :string
    field :categories, {:array, :string}, default: []

    belongs_to :feed, FuzzyRss.Content.Feed

    has_many :user_entry_states, FuzzyRss.Content.UserEntryState

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:feed_id, :guid, :url, :title, :author, :content, :summary, :published_at, :image_url, :categories])
    |> validate_required([:feed_id, :guid])
    |> unique_constraint([:feed_id, :guid])
  end
end
```

### User Entry State Schema

`lib/fuzzy_rss/content/user_entry_state.ex`:

```elixir
defmodule FuzzyRss.Content.UserEntryState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_entry_states" do
    field :read, :boolean, default: false
    field :starred, :boolean, default: false
    field :read_at, :utc_datetime
    field :starred_at, :utc_datetime

    belongs_to :user, FuzzyRss.Accounts.User
    belongs_to :entry, FuzzyRss.Content.Entry

    timestamps()
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:user_id, :entry_id, :read, :starred, :read_at, :starred_at])
    |> validate_required([:user_id, :entry_id])
    |> unique_constraint([:user_id, :entry_id])
  end
end
```

## Completion Checklist

- [ ] Created all 6 migrations in `priv/repo/migrations/`
- [ ] Ran `mix ecto.migrate` successfully
- [ ] Created Folder schema
- [ ] Created Feed schema
- [ ] Created Subscription schema
- [ ] Created Entry schema
- [ ] Created UserEntryState schema
- [ ] All associations are defined correctly
- [ ] Verified with `mix compile` (no errors)

## Testing the Schema

```bash
# Test with default database
mix ecto.reset

# Test with MySQL
DATABASE_ADAPTER=mysql mix ecto.reset

# Test with SQLite
DATABASE_ADAPTER=sqlite mix ecto.reset
```

## Next Steps

Proceed to [Phase 3: Phoenix Contexts](PHASE_3_PHOENIX_CONTEXTS.md) to implement the business logic for managing feeds, entries, and user states.
