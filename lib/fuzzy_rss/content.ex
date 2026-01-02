defmodule FuzzyRss.Content do
  @moduledoc """
  The Content context.
  """

  import Ecto.Query, warn: false
  alias FuzzyRss.Content.{Feed, Folder, Subscription, Entry, UserEntryState}

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  ## Feed management

  @doc """
  Lists all feeds a user is subscribed to.
  """
  def list_user_feeds(user) do
    from(s in Subscription,
      where: s.user_id == ^user.id,
      preload: :feed
    )
    |> repo().all()
    |> Enum.map(& &1.feed)
  end

  @doc """
  Subscribes a user to a feed by URL.
  Creates the feed if it doesn't exist.
  """
  def subscribe_to_feed(user, feed_url, opts \\ []) do
    require Logger
    feed = repo().get_by(Feed, url: feed_url) || create_feed!(feed_url)

    result =
      %Subscription{}
      |> Subscription.changeset(%{
        user_id: user.id,
        feed_id: feed.id,
        folder_id: opts[:folder_id]
      })
      |> repo().insert()

    # Queue immediate fetch for new subscriptions
    Logger.info("Content: Queueing immediate fetch for feed #{feed.id} (#{feed.url})")

    %{feed_id: feed.id}
    |> FuzzyRss.Workers.FeedFetcherWorker.new()
    |> Oban.insert()

    result
  end

  @doc """
  Unsubscribes a user from a feed.
  If this is the last subscription, the feed is deleted entirely.
  Returns {:ok, :unsubscribed}, {:ok, :feed_deleted}, or {:ok, :not_subscribed}
  """
  def unsubscribe_from_feed(user, feed_id) do
    repo().transaction(fn ->
      # Delete the subscription
      {count, _} =
        repo().delete_all(
          from(s in Subscription,
            where: s.user_id == ^user.id and s.feed_id == ^feed_id
          )
        )

      if count > 0 do
        # Check if any subscriptions remain for this feed
        remaining_subs =
          repo().one(
            from(s in Subscription,
              where: s.feed_id == ^feed_id,
              select: count(s.id)
            )
          )

        if remaining_subs == 0 do
          # No more subscriptions - delete the feed
          # Database cascades will handle entries and user_entry_states
          feed = repo().get(Feed, feed_id)

          if feed do
            repo().delete(feed)
            :feed_deleted
          else
            :unsubscribed
          end
        else
          :unsubscribed
        end
      else
        :not_subscribed
      end
    end)
  end

  @doc """
  Updates a subscription's attributes (folder, title override, etc).
  """
  def update_subscription(subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Gets a single subscription by ID.
  """
  def get_subscription!(id) do
    repo().get!(Subscription, id)
  end

  @doc """
  Gets a user's subscription to a specific feed.
  """
  def get_user_subscription(user, feed_id) do
    repo().get_by(Subscription, user_id: user.id, feed_id: feed_id)
  end

  @doc """
  Gets a feed by ID.
  """
  def get_feed!(id) do
    repo().get!(Feed, id)
  end

  @doc """
  Updates a feed's metadata (typically called by feed fetcher).
  """
  def update_feed(feed, attrs) do
    feed
    |> Feed.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Returns feeds that are due for fetching based on their fetch interval.
  """
  def feeds_due_for_fetch do
    now = DateTime.utc_now()

    from(f in Feed,
      where:
        f.active == true and
          (is_nil(f.last_fetched_at) or
             fragment(
               "? < ? - INTERVAL '1 MINUTE' * ?",
               f.last_fetched_at,
               ^now,
               f.fetch_interval
             )),
      limit: 100
    )
    |> repo().all()
  end

  @doc """
  Manually queues a refresh job for a specific feed.
  """
  def refresh_feed(feed_id) do
    require Logger
    Logger.info("Content: Manual refresh requested for feed #{feed_id}")

    %{feed_id: feed_id}
    |> FuzzyRss.Workers.FeedFetcherWorker.new()
    |> Oban.insert()
  end

  @doc """
  Manually queues refresh jobs for all user's feeds.
  """
  def refresh_all_feeds(user) do
    feeds = list_user_feeds(user)

    Enum.each(feeds, fn feed ->
      %{feed_id: feed.id}
      |> FuzzyRss.Workers.FeedFetcherWorker.new()
      |> Oban.insert()
    end)

    {:ok, length(feeds)}
  end

  defp create_feed!(url) do
    %Feed{}
    |> Feed.changeset(%{url: url})
    |> repo().insert!()
  end

  ## Folder management

  @doc """
  Lists all folders for a user.
  """
  def list_user_folders(user) do
    from(f in Folder,
      where: f.user_id == ^user.id,
      order_by: [asc: f.position, asc: f.name]
    )
    |> repo().all()
  end

  @doc """
  Creates a new folder for a user.
  """
  def create_folder(user, attrs) do
    %Folder{}
    |> Folder.changeset(Map.put(attrs, "user_id", user.id))
    |> repo().insert()
  end

  @doc """
  Updates a folder's attributes.
  """
  def update_folder(folder, attrs) do
    folder
    |> Folder.changeset(attrs)
    |> repo().update()
  end

  @doc """
  Deletes a folder and moves its subscriptions to the root level.
  """
  def delete_folder(folder) do
    repo().update_all(
      from(s in Subscription, where: s.folder_id == ^folder.id),
      set: [folder_id: nil]
    )

    repo().delete(folder)
  end

  @doc """
  Gets a single folder by ID.
  """
  def get_folder!(id) do
    repo().get!(Folder, id)
  end

  @doc """
  Gets a user's folder by slug.
  """
  def get_user_folder_by_slug(user, slug) do
    repo().get_by(Folder, user_id: user.id, slug: slug)
  end

  ## Entry queries

  @doc """
  Lists entries for a user with various filtering options.

  ## Options
  - `:filter` - `:all`, `:unread`, or `:starred` (default: `:all`)
  - `:folder_id` - Filter by folder
  - `:feed_id` - Filter by feed
  - `:limit` - Maximum entries to return (default: 50)
  - `:offset` - Offset for pagination (default: 0)
  """
  def list_entries(user, opts \\ []) do
    filter = opts[:filter] || :all
    folder_id = opts[:folder_id]
    feed_id = opts[:feed_id]
    limit = opts[:limit] || 50
    offset = opts[:offset] || 0

    query =
      from e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        left_join: ues in UserEntryState,
        on: ues.entry_id == e.id and ues.user_id == ^user.id,
        where: s.user_id == ^user.id,
        order_by: [desc: e.published_at],
        preload: [:feed]

    query = apply_entry_filter(query, filter)
    query = apply_folder_filter(query, folder_id)
    query = apply_feed_filter(query, feed_id)

    entries = query
      |> limit(^limit)
      |> offset(^offset)
      |> repo().all()

    # Manually load user entry states for the result
    entries
    |> repo().preload([user_entry_states: from(ues in UserEntryState, where: ues.user_id == ^user.id)])
  end

  @doc """
  Searches entries for a user using database-specific full-text search.
  """
  def search_entries(user, search_query) do
    adapter = Application.fetch_env!(:fuzzy_rss, FuzzyRss.Repo)[:adapter]

    from(e in Entry,
      join: s in Subscription,
      on: s.feed_id == e.feed_id and s.user_id == ^user.id,
      where: ^search_where_clause(adapter, search_query),
      order_by: [desc: e.published_at],
      limit: 100,
      preload: [:feed]
    )
    |> repo().all()
  end

  @doc """
  Gets a single entry by ID.
  """
  def get_entry!(id) do
    repo().get!(Entry, id)
  end

  @doc """
  Gets unread counts per feed for a user.
  Returns a map of feed_id => count.
  """
  def get_unread_counts(user) do
    from(s in Subscription,
      left_join: e in Entry,
      on: e.feed_id == s.feed_id,
      left_join: ues in UserEntryState,
      on: ues.entry_id == e.id and ues.user_id == ^user.id,
      where: s.user_id == ^user.id and (is_nil(ues.id) or ues.read == false),
      group_by: s.feed_id,
      select: {s.feed_id, count(e.id)}
    )
    |> repo().all()
    |> Enum.into(%{})
  end

  ## Entry state management

  @doc """
  Marks an entry as read for a user.
  """
  def mark_as_read(user, entry_id) do
    %UserEntryState{}
    |> UserEntryState.changeset(%{
      user_id: user.id,
      entry_id: entry_id,
      read: true,
      read_at: DateTime.utc_now()
    })
    |> repo().insert(
      on_conflict: {:replace, [:read, :read_at]},
      conflict_target: [:user_id, :entry_id]
    )
  end

  @doc """
  Marks an entry as unread for a user.
  """
  def mark_as_unread(user, entry_id) do
    %UserEntryState{}
    |> UserEntryState.changeset(%{
      user_id: user.id,
      entry_id: entry_id,
      read: false
    })
    |> repo().insert(
      on_conflict: {:replace, [:read]},
      conflict_target: [:user_id, :entry_id]
    )
  end

  @doc """
  Toggles the starred status of an entry for a user.
  """
  def toggle_starred(user, entry_id) do
    case repo().get_by(UserEntryState, user_id: user.id, entry_id: entry_id) do
      nil ->
        %UserEntryState{}
        |> UserEntryState.changeset(%{
          user_id: user.id,
          entry_id: entry_id,
          starred: true,
          starred_at: DateTime.utc_now()
        })
        |> repo().insert()

      state ->
        state
        |> UserEntryState.changeset(%{
          starred: !state.starred,
          starred_at: if(!state.starred, do: DateTime.utc_now(), else: nil)
        })
        |> repo().update()
    end
  end

  @doc """
  Marks all entries as read for a user.

  ## Options
  - `:feed_id` - Only mark entries from this feed as read
  - `:folder_id` - Only mark entries in this folder as read
  """
  def mark_all_as_read(user, opts \\ []) do
    feed_id = opts[:feed_id]
    folder_id = opts[:folder_id]

    query =
      from e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        where: s.user_id == ^user.id

    query = apply_feed_filter(query, feed_id)
    query = apply_folder_filter(query, folder_id)

    entry_ids = query |> select([e], e.id) |> repo().all()

    now = DateTime.utc_now()

    repo().insert_all(
      UserEntryState,
      Enum.map(entry_ids, fn entry_id ->
        %{
          user_id: user.id,
          entry_id: entry_id,
          read: true,
          read_at: now,
          inserted_at: now,
          updated_at: now
        }
      end),
      on_conflict: :replace_all,
      conflict_target: [:user_id, :entry_id]
    )
  end

  @doc """
  Gets the state for a specific entry and user.
  """
  def get_entry_state(user, entry_id) do
    repo().get_by(UserEntryState, user_id: user.id, entry_id: entry_id)
  end

  ## Private helpers

  defp apply_entry_filter(query, :unread) do
    where(query, [e, s, ues], is_nil(ues.id) or ues.read == false)
  end

  defp apply_entry_filter(query, :starred) do
    where(query, [e, s, ues], not is_nil(ues.id) and ues.starred == true)
  end

  defp apply_entry_filter(query, _), do: query

  defp apply_folder_filter(query, nil), do: query

  defp apply_folder_filter(query, folder_id) do
    where(query, [e, s], s.folder_id == ^folder_id)
  end

  defp apply_feed_filter(query, nil), do: query

  defp apply_feed_filter(query, feed_id) do
    where(query, [e], e.feed_id == ^feed_id)
  end

  defp search_where_clause(Ecto.Adapters.MyXQL, query) do
    dynamic(
      [e],
      fragment(
        "MATCH(title, content) AGAINST (? IN NATURAL LANGUAGE MODE)",
        ^query
      )
    )
  end

  defp search_where_clause(Ecto.Adapters.Postgres, query) do
    dynamic(
      [e],
      fragment(
        "to_tsvector('english', title || ' ' || coalesce(content, '')) @@ plainto_tsquery('english', ?)",
        ^query
      )
    )
  end

  defp search_where_clause(Ecto.Adapters.SQLite3, query) do
    search_pattern = "%#{query}%"

    dynamic(
      [e],
      fragment(
        "(title LIKE ? OR content LIKE ?)",
        ^search_pattern,
        ^search_pattern
      )
    )
  end

  defp search_where_clause(_, query) do
    search_pattern = "%#{query}%"

    dynamic(
      [e],
      fragment(
        "(title LIKE ? OR content LIKE ?)",
        ^search_pattern,
        ^search_pattern
      )
    )
  end
end
