defmodule FuzzyRss.Content do
  @moduledoc """
  The Content context.
  """

  import Ecto.Query, warn: false
  alias FuzzyRss.Content.{Feed, Folder, Subscription, Entry, UserEntryState, StarredEntry}

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
  Lists all subscriptions for a user with preloaded feed and folder.
  """
  def list_subscriptions(user) do
    from(s in Subscription,
      where: s.user_id == ^user.id,
      preload: [:feed, :folder]
    )
    |> repo().all()
  end

  @doc """
  Subscribes a user to a feed by URL.
  Creates the feed if it doesn't exist.
  """
  def subscribe_to_feed(user, feed_url, opts \\ []) do
    require Logger

    with :ok <- validate_url(feed_url),
         feed <- get_or_create_feed(feed_url),
         {:ok, subscription} <-
           %Subscription{}
           |> Subscription.changeset(%{
             user_id: user.id,
             feed_id: feed.id,
             folder_id: opts[:folder_id]
           })
           |> repo().insert() do
      # Queue immediate fetch for new subscriptions
      Logger.info("Content: Queueing immediate fetch for feed #{feed.id} (#{feed.url})")

      %{feed_id: feed.id}
      |> FuzzyRss.Workers.FeedFetcherWorker.new()
      |> Oban.insert()

      {:ok, subscription}
    else
      error -> error
    end
  end

  defp validate_url(url) when is_binary(url) and byte_size(url) > 0, do: :ok
  defp validate_url(_), do: {:error, "Invalid URL"}

  defp get_or_create_feed(feed_url) do
    case repo().get_by(Feed, url: feed_url) do
      %Feed{} = feed ->
        feed

      nil ->
        case create_feed(feed_url) do
          {:ok, feed} -> feed
          {:error, _} -> raise "Failed to create feed"
        end
    end
  end

  defp create_feed(url) do
    %Feed{}
    |> Feed.changeset(%{url: url})
    |> repo().insert()
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
          # No more subscriptions - archive starred entries before deleting the feed
          archive_starred_entries_from_feed(feed_id)

          # Delete the feed (database cascades will handle entries and user_entry_states)
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

  # Archives all starred entries from a feed before deletion.
  # This preserves the user's starred content even after the feed is deleted.
  defp archive_starred_entries_from_feed(feed_id) do
    # Find all entries in this feed that have been starred by any user
    # Also get the feed information
    starred_entries =
      from(e in Entry,
        join: ues in UserEntryState,
        on: ues.entry_id == e.id,
        join: f in Feed,
        on: f.id == e.feed_id,
        where: e.feed_id == ^feed_id and ues.starred == true,
        select: {ues.user_id, e, ues.starred_at, f.title, f.url}
      )
      |> repo().all()

    # Archive each starred entry for its user
    Enum.each(starred_entries, fn {user_id, entry, starred_at, feed_title, feed_url} ->
      %StarredEntry{}
      |> StarredEntry.changeset(%{
        user_id: user_id,
        guid: entry.guid,
        url: entry.url,
        title: entry.title,
        author: entry.author,
        content: entry.content,
        summary: entry.summary,
        published_at: entry.published_at,
        image_url: entry.image_url,
        categories: entry.categories,
        feed_title: feed_title,
        feed_url: feed_url,
        starred_at: starred_at || DateTime.utc_now()
      })
      |> repo().insert(on_conflict: :nothing)
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
  Gets a user's subscription by feed URL.
  """
  def get_user_subscription_by_url(user, feed_url) do
    from(s in Subscription,
      join: f in Feed,
      on: s.feed_id == f.id,
      where: s.user_id == ^user.id and f.url == ^feed_url,
      preload: [:feed, :folder]
    )
    |> repo().one()
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
               "? + (INTERVAL '1 MINUTE' * ?) < ?",
               f.last_fetched_at,
               f.fetch_interval,
               ^now
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
  Builds a hierarchical tree of folders and feeds for the sidebar.
  Returns a list of root-level tree nodes (folders and uncategorized feeds).

  Each tree node has the structure:
  %{
    type: :folder | :feed,
    id: integer,
    data: %Folder{} | %Feed{},
    subscription: %Subscription{} | nil,  # Only for feeds
    unread_count: integer,
    children: [tree_node],  # Only for folders, empty for feeds
    level: integer
  }
  """
  def build_sidebar_tree(user) do
    # Fetch all folders with children and subscriptions preloaded
    all_folders =
      from(f in Folder,
        where: f.user_id == ^user.id,
        preload: [:children, :subscriptions],
        order_by: [asc: f.position, asc: f.name]
      )
      |> repo().all()

    # Fetch all subscriptions with feeds preloaded
    all_subscriptions =
      from(s in Subscription,
        where: s.user_id == ^user.id,
        preload: :feed,
        order_by: [asc: s.position]
      )
      |> repo().all()

    # Get unread counts
    unread_counts = get_unread_counts(user)

    # Build maps for quick lookup
    folders_by_id = Enum.into(all_folders, %{}, &{&1.id, &1})

    subscriptions_by_folder_id =
      Enum.group_by(all_subscriptions, & &1.folder_id)

    # Build tree starting from root-level folders
    root_folders =
      all_folders
      |> Enum.filter(&is_nil(&1.parent_id))
      |> Enum.map(
        &build_tree_node(&1, :folder, folders_by_id, subscriptions_by_folder_id, unread_counts, 0)
      )

    # Add root-level feeds (feeds not assigned to any folder)
    root_feeds =
      subscriptions_by_folder_id
      |> Map.get(nil, [])
      |> Enum.map(
        &build_tree_node(
          &1.feed,
          :feed,
          folders_by_id,
          subscriptions_by_folder_id,
          unread_counts,
          0,
          &1
        )
      )

    # Combine and sort
    (root_folders ++ root_feeds)
    |> Enum.sort_by(fn node ->
      case node do
        %{type: :folder, data: folder} -> {0, folder.position, folder.name}
        %{type: :feed, data: feed} -> {1, feed.title || feed.url}
      end
    end)
  end

  # Builds a single tree node for a folder
  defp build_tree_node(
         folder,
         :folder,
         folders_by_id,
         subscriptions_by_folder_id,
         unread_counts,
         level
       ) do
    # Get child folders (already preloaded)
    child_folders =
      (folder.children || [])
      |> Enum.map(
        &build_tree_node(
          &1,
          :folder,
          folders_by_id,
          subscriptions_by_folder_id,
          unread_counts,
          level + 1
        )
      )

    # Get feeds in this folder
    child_feeds =
      (subscriptions_by_folder_id[folder.id] || [])
      |> Enum.map(
        &build_tree_node(
          &1.feed,
          :feed,
          folders_by_id,
          subscriptions_by_folder_id,
          unread_counts,
          level + 1,
          &1
        )
      )

    children = child_folders ++ child_feeds

    # Calculate folder unread count (aggregate from children)
    folder_unread_count =
      calculate_folder_unread_count(
        folder.id,
        subscriptions_by_folder_id,
        folders_by_id,
        unread_counts
      )

    %{
      type: :folder,
      id: folder.id,
      data: folder,
      subscription: nil,
      unread_count: folder_unread_count,
      children: children,
      level: level
    }
  end

  # Builds a single tree node for a feed
  defp build_tree_node(
         feed,
         :feed,
         _folders_by_id,
         _subscriptions_by_folder_id,
         unread_counts,
         level,
         subscription
       ) do
    %{
      type: :feed,
      id: feed.id,
      data: feed,
      subscription: subscription,
      unread_count: Map.get(unread_counts, feed.id, 0),
      children: [],
      level: level
    }
  end

  # Calculates the total unread count for a folder and all its descendants
  defp calculate_folder_unread_count(
         folder_id,
         subscriptions_by_folder_id,
         folders_by_id,
         unread_counts
       ) do
    # Get direct feed subscriptions in this folder
    direct_feeds_unread =
      subscriptions_by_folder_id
      |> Map.get(folder_id, [])
      |> Enum.reduce(0, fn sub, acc ->
        acc + Map.get(unread_counts, sub.feed_id, 0)
      end)

    # Get unread counts from child folders recursively
    folder = folders_by_id[folder_id]
    child_folders = folder.children || []

    child_folders_unread =
      Enum.reduce(child_folders, 0, fn child_folder, acc ->
        acc +
          calculate_folder_unread_count(
            child_folder.id,
            subscriptions_by_folder_id,
            folders_by_id,
            unread_counts
          )
      end)

    direct_feeds_unread + child_folders_unread
  end

  @doc """
  Creates a new folder for a user.
  """
  def create_folder(user, attrs) do
    %Folder{}
    |> Folder.changeset(Map.put(attrs, :user_id, user.id))
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

  @doc """
  Gets a user's folder by name.
  """
  def get_user_folder_by_name(user, name) do
    repo().get_by(Folder, user_id: user.id, name: name)
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
    older_than = opts[:older_than]
    newer_than = opts[:newer_than]
    exclude_read = opts[:exclude_read]
    order = opts[:order] || :desc

    query =
      from e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        left_join: ues in UserEntryState,
        on: ues.entry_id == e.id and ues.user_id == ^user.id,
        where: s.user_id == ^user.id,
        preload: [:feed]

    query = apply_entry_filter(query, filter)
    query = apply_folder_filter(query, folder_id)
    query = apply_feed_filter(query, feed_id)
    query = apply_timestamp_filter(query, older_than, newer_than)
    query = apply_order(query, order)

    # If exclude_read is true, filter out read entries
    query = if exclude_read do
      where(query, [e, s, ues], is_nil(ues.id) or ues.read == false)
    else
      query
    end

    # For starred filter, also include archived starred entries
    if filter == :starred && is_nil(feed_id) && is_nil(folder_id) do
      live_entries =
        query
        |> repo().all()
        |> repo().preload(
          user_entry_states: from(ues in UserEntryState, where: ues.user_id == ^user.id)
        )

      archived_entries =
        repo().all(
          from se in StarredEntry,
            where: se.user_id == ^user.id,
            order_by: [desc: se.starred_at]
        )

      # Convert archived entries to Entry-like format with the original feed info
      archived_as_entries =
        Enum.map(archived_entries, fn se ->
          %Entry{
            # Use negative ID to distinguish from real entries
            id: -se.id,
            guid: se.guid,
            url: se.url,
            title: se.title,
            author: se.author,
            content: se.content,
            summary: se.summary,
            published_at: se.published_at,
            image_url: se.image_url,
            categories: se.categories,
            feed: %Feed{title: se.feed_title || "Archived", url: se.feed_url},
            user_entry_states: [],
            inserted_at: se.inserted_at
          }
        end)

      # Combine and sort by published_at, then apply limit/offset
      combined =
        (live_entries ++ archived_as_entries)
        |> Enum.sort_by(&(&1.published_at || DateTime.utc_now()), {:desc, DateTime})
        |> Enum.slice(offset, limit)

      combined
    else
      entries =
        query
        |> limit(^limit)
        |> offset(^offset)
        |> repo().all()

      # Manually load user entry states for the result
      entries
      |> repo().preload(
        user_entry_states: from(ues in UserEntryState, where: ues.user_id == ^user.id)
      )
    end
  end

  @doc """
  Counts unread entries for a user with optional feed_id or folder_id filters.
  """
  def count_unread_entries(user, opts \\ []) do
    folder_id = opts[:folder_id]
    feed_id = opts[:feed_id]

    query =
      from e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        left_join: ues in UserEntryState,
        on: ues.entry_id == e.id and ues.user_id == ^user.id,
        where: s.user_id == ^user.id

    query = apply_entry_filter(query, :unread)
    query = apply_folder_filter(query, folder_id)
    query = apply_feed_filter(query, feed_id)

    repo().aggregate(query, :count, :id)
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
  Gets multiple entries by their IDs.
  Returns entries with feed and user_entry_states preloaded.
  """
  def get_entries_by_ids(_user, entry_ids) when is_list(entry_ids) do
    from(e in Entry,
      where: e.id in ^entry_ids,
      preload: [:feed, :user_entry_states]
    )
    |> repo().all()
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
  Gets the user entry state for a specific entry.
  Returns nil if the state doesn't exist.
  """
  def get_user_entry_state(user, entry_id) do
    repo().get_by(UserEntryState, user_id: user.id, entry_id: entry_id)
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
  - `:feed_url` - Only mark entries from feed with this URL as read
  - `:folder_name` - Only mark entries in folder with this name as read
  """
  def mark_all_as_read(user, opts \\ []) do
    # Resolve feed_url to feed_id if provided
    feed_id =
      cond do
        opts[:feed_id] -> opts[:feed_id]
        opts[:feed_url] ->
          case repo().get_by(Feed, url: opts[:feed_url]) do
            nil -> nil
            feed -> feed.id
          end
        true -> nil
      end

    # Resolve folder_name to folder_id if provided
    folder_id =
      cond do
        opts[:folder_id] -> opts[:folder_id]
        opts[:folder_name] ->
          case get_user_folder_by_name(user, opts[:folder_name]) do
            nil -> nil
            folder -> folder.id
          end
        true -> nil
      end

    query =
      from e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        where: s.user_id == ^user.id

    query = apply_feed_filter(query, feed_id)
    query = apply_folder_filter(query, folder_id)

    entry_ids = query |> select([e], e.id) |> repo().all()

    now_utc = DateTime.utc_now() |> DateTime.truncate(:second)
    now_naive = DateTime.to_naive(now_utc)

    repo().insert_all(
      UserEntryState,
      Enum.map(entry_ids, fn entry_id ->
        %{
          user_id: user.id,
          entry_id: entry_id,
          read: true,
          read_at: now_utc,
          inserted_at: now_naive,
          updated_at: now_naive
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

  @doc """
  Gets entry states for multiple entries at once (batch operation).

  Returns a list of UserEntryState structs for the given entry IDs.
  More efficient than calling get_entry_state/2 multiple times.
  """
  def get_entry_states(user, entry_ids) when is_list(entry_ids) do
    from(ues in UserEntryState,
      where: ues.user_id == ^user.id,
      where: ues.entry_id in ^entry_ids
    )
    |> repo().all()
  end

  @doc """
  Deletes an archived starred entry.
  Use this when the entry ID is negative (indicating an archived entry).
  """
  def delete_archived_entry(user, archived_entry_id) when archived_entry_id < 0 do
    # Convert negative ID back to positive for the database lookup
    real_id = -archived_entry_id

    case repo().get_by(StarredEntry, user_id: user.id, id: real_id) do
      nil -> {:error, :not_found}
      entry -> repo().delete(entry)
    end
  end

  @doc """
  Deletes a starred entry.
  If it's a live entry (positive ID), just unstar it.
  If it's an archived entry (negative ID), delete it from the archive.
  """
  def delete_starred_entry(user, entry_id) when entry_id < 0 do
    delete_archived_entry(user, entry_id)
  end

  def delete_starred_entry(user, entry_id) do
    case get_entry_state(user, entry_id) do
      nil ->
        {:error, :not_found}

      state ->
        state
        |> UserEntryState.changeset(%{starred: false, starred_at: nil})
        |> repo().update()
    end
  end

  ## Fever API

  @doc """
  Lists entries for Fever API with pagination options.

  ## Options

    * `:since_id` - Return entries with ID greater than this value
    * `:max_id` - Return entries with ID less than or equal to this value
    * `:with_ids` - Comma-separated string of entry IDs to fetch
    * `:limit` - Maximum number of entries to return (default: 50)

  """
  def list_fever_items(user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    base_query =
      from(e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        where: s.user_id == ^user.id,
        order_by: [desc: e.id],
        limit: ^limit,
        preload: [:feed]
      )

    query =
      cond do
        ids_string = Keyword.get(opts, :with_ids) ->
          # Parse comma-separated IDs
          ids =
            ids_string
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.map(&Integer.parse/1)
            |> Enum.filter(fn
              {_int, _} -> true
              :error -> false
            end)
            |> Enum.map(fn {int, _} -> int end)

          from(e in base_query, where: e.id in ^ids)

        since_id = Keyword.get(opts, :since_id) ->
          from(e in base_query, where: e.id > ^since_id)

        max_id = Keyword.get(opts, :max_id) ->
          from(e in base_query, where: e.id <= ^max_id)

        true ->
          base_query
      end

    repo().all(query)
  end

  @doc """
  Returns comma-separated string of unread entry IDs for a user.
  """
  def get_unread_item_ids(user) do
    query =
      from(e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        left_join: ues in UserEntryState,
        on: ues.entry_id == e.id and ues.user_id == ^user.id,
        where: s.user_id == ^user.id,
        where: is_nil(ues.id) or ues.read == false,
        select: e.id,
        order_by: [asc: e.id]
      )

    repo().all(query)
    |> Enum.map(&Integer.to_string/1)
    |> Enum.join(",")
  end

  @doc """
  Returns comma-separated string of starred entry IDs for a user.
  """
  def get_saved_item_ids(user) do
    query =
      from(e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        join: ues in UserEntryState,
        on: ues.entry_id == e.id and ues.user_id == ^user.id,
        where: s.user_id == ^user.id,
        where: ues.starred == true,
        select: e.id,
        order_by: [asc: e.id]
      )

    repo().all(query)
    |> Enum.map(&Integer.to_string/1)
    |> Enum.join(",")
  end

  @doc """
  Marks all entries in a feed as read before a given Unix timestamp.

  Returns `{:ok, count}` where count is the number of entries marked as read.
  """
  def mark_feed_read_before(user, feed_id, unix_timestamp) do
    cutoff_datetime = DateTime.from_unix!(unix_timestamp)

    # Get all entry IDs that need to be marked as read
    entry_ids =
      from(e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        where: s.user_id == ^user.id,
        where: e.feed_id == ^feed_id,
        where: e.published_at < ^cutoff_datetime,
        select: e.id
      )
      |> repo().all()

    # Bulk insert/update user entry states
    now_utc = DateTime.utc_now() |> DateTime.truncate(:second)
    now_naive = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    states =
      Enum.map(entry_ids, fn entry_id ->
        %{
          user_id: user.id,
          entry_id: entry_id,
          read: true,
          read_at: now_utc,
          starred: false,
          inserted_at: now_naive,
          updated_at: now_naive
        }
      end)

    {count, _} =
      repo().insert_all(
        UserEntryState,
        states,
        on_conflict: {:replace, [:read, :read_at, :updated_at]},
        conflict_target: [:user_id, :entry_id]
      )

    {:ok, count}
  end

  @doc """
  Marks all entries in a folder as read before a given Unix timestamp.

  Returns `{:ok, count}` where count is the number of entries marked as read.
  """
  def mark_folder_read_before(user, folder_id, unix_timestamp) do
    cutoff_datetime = DateTime.from_unix!(unix_timestamp)

    # Get all entry IDs in the folder that need to be marked as read
    entry_ids =
      from(e in Entry,
        join: s in Subscription,
        on: s.feed_id == e.feed_id,
        where: s.user_id == ^user.id,
        where: s.folder_id == ^folder_id,
        where: e.published_at < ^cutoff_datetime,
        select: e.id
      )
      |> repo().all()

    # Bulk insert/update user entry states
    now_utc = DateTime.utc_now() |> DateTime.truncate(:second)
    now_naive = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    states =
      Enum.map(entry_ids, fn entry_id ->
        %{
          user_id: user.id,
          entry_id: entry_id,
          read: true,
          read_at: now_utc,
          starred: false,
          inserted_at: now_naive,
          updated_at: now_naive
        }
      end)

    {count, _} =
      repo().insert_all(
        UserEntryState,
        states,
        on_conflict: {:replace, [:read, :read_at, :updated_at]},
        conflict_target: [:user_id, :entry_id]
      )

    {:ok, count}
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

  defp apply_timestamp_filter(query, nil, nil), do: query

  defp apply_timestamp_filter(query, older_than, nil) when not is_nil(older_than) do
    timestamp = DateTime.from_unix!(older_than)
    where(query, [e], e.published_at < ^timestamp)
  end

  defp apply_timestamp_filter(query, nil, newer_than) when not is_nil(newer_than) do
    timestamp = DateTime.from_unix!(newer_than)
    where(query, [e], e.published_at > ^timestamp)
  end

  defp apply_timestamp_filter(query, older_than, newer_than) do
    older_timestamp = DateTime.from_unix!(older_than)
    newer_timestamp = DateTime.from_unix!(newer_than)
    where(query, [e], e.published_at < ^older_timestamp and e.published_at > ^newer_timestamp)
  end

  defp apply_order(query, :asc) do
    order_by(query, [e], asc: e.published_at)
  end

  defp apply_order(query, :desc) do
    order_by(query, [e], desc: e.published_at)
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
