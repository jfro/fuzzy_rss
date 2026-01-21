defmodule FuzzyRssWeb.Api.FeverController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.{Content, Api.Fever}

  @doc """
  Main Fever API endpoint.

  Handles all Fever API requests via query parameters:
  - ?api - auth check
  - ?api&groups - list folders
  - ?api&feeds - list feeds with feeds_groups
  - ?api&items - list entries with pagination
  - ?api&unread_item_ids - comma-separated unread IDs
  - ?api&saved_item_ids - comma-separated starred IDs
  - ?api&favicons - empty array (not implemented)

  Write operations (POST):
  - mark=item&as=read&id=X
  - mark=item&as=unread&id=X
  - mark=item&as=saved&id=X
  - mark=item&as=unsaved&id=X
  - mark=feed&as=read&id=X&before=timestamp
  - mark=group&as=read&id=X&before=timestamp
  """
  def index(conn, params) do
    user = conn.assigns.current_user

    # Handle write operations first
    handle_mark_operations(user, params)

    # Base response always includes API version and auth status
    response = %{
      api_version: 3,
      auth: 1
    }

    # Add data based on query parameters
    response =
      response
      |> maybe_add_groups(conn, user, params)
      |> maybe_add_feeds(conn, user, params)
      |> maybe_add_items(conn, user, params)
      |> maybe_add_unread_item_ids(conn, user, params)
      |> maybe_add_saved_item_ids(conn, user, params)
      |> maybe_add_favicons(conn, user, params)

    json(conn, response)
  end

  # Handle mark operations (write operations)
  defp handle_mark_operations(user, %{"mark" => mark, "as" => as_action, "id" => id} = params) do
    case {mark, as_action} do
      {"item", "read"} ->
        parse_int(id, fn entry_id -> Content.mark_as_read(user, entry_id) end)

      {"item", "unread"} ->
        parse_int(id, fn entry_id -> Content.mark_as_unread(user, entry_id) end)

      {"item", "saved"} ->
        parse_int(id, fn entry_id -> Content.toggle_starred(user, entry_id) end)

      {"item", "unsaved"} ->
        parse_int(id, fn entry_id ->
          # Check if starred, and toggle if true
          state = Content.get_entry_state(user, entry_id)

          if state && state.starred do
            Content.toggle_starred(user, entry_id)
          end
        end)

      {"feed", "read"} ->
        feed_id = to_int(id)
        timestamp = to_int(params["before"])

        if feed_id && timestamp do
          Content.mark_feed_read_before(user, feed_id, timestamp)
        end

      {"group", "read"} ->
        folder_id = to_int(id)
        timestamp = to_int(params["before"])

        if folder_id && timestamp do
          Content.mark_folder_read_before(user, folder_id, timestamp)
        end

      _ ->
        :ok
    end
  end

  defp handle_mark_operations(_user, _params), do: :ok

  # Helper to parse integer ID and call function
  defp parse_int(id, fun) when is_integer(id), do: fun.(id)

  defp parse_int(id_string, fun) when is_binary(id_string) do
    case Integer.parse(id_string) do
      {int, _} -> fun.(int)
      :error -> :ok
    end
  end

  defp parse_int(_id, _fun), do: :ok

  # Helper to convert string or integer to integer
  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_int(_value), do: nil

  # Add groups if ?groups parameter is present
  defp maybe_add_groups(response, _conn, user, params) do
    if Map.has_key?(params, "groups") do
      folders = Content.list_user_folders(user)
      groups = Fever.format_groups(folders)
      Map.put(response, :groups, groups)
    else
      response
    end
  end

  # Add feeds and feeds_groups if ?feeds parameter is present
  defp maybe_add_feeds(response, _conn, user, params) do
    if Map.has_key?(params, "feeds") do
      subscriptions = Content.list_subscriptions(user)
      feeds = Fever.format_feeds(subscriptions)
      feeds_groups = Fever.format_feeds_groups(subscriptions)

      response
      |> Map.put(:feeds, feeds)
      |> Map.put(:feeds_groups, feeds_groups)
    else
      response
    end
  end

  # Add items if ?items parameter is present
  defp maybe_add_items(response, _conn, user, params) do
    if Map.has_key?(params, "items") do
      opts = build_items_opts(params)
      entries = Content.list_fever_items(user, opts)
      items = Fever.format_items(entries, user)

      response
      |> Map.put(:items, items)
      |> Map.put(:total_items, length(items))
    else
      response
    end
  end

  # Add unread_item_ids if parameter is present
  defp maybe_add_unread_item_ids(response, _conn, user, params) do
    if Map.has_key?(params, "unread_item_ids") do
      unread_ids = Content.get_unread_item_ids(user)
      Map.put(response, :unread_item_ids, unread_ids)
    else
      response
    end
  end

  # Add saved_item_ids if parameter is present
  defp maybe_add_saved_item_ids(response, _conn, user, params) do
    if Map.has_key?(params, "saved_item_ids") do
      saved_ids = Content.get_saved_item_ids(user)
      Map.put(response, :saved_item_ids, saved_ids)
    else
      response
    end
  end

  # Add favicons (empty array - not implemented)
  defp maybe_add_favicons(response, _conn, _user, params) do
    if Map.has_key?(params, "favicons") do
      Map.put(response, :favicons, [])
    else
      response
    end
  end

  # Build options for list_fever_items/2 from query parameters
  defp build_items_opts(params) do
    []
    |> maybe_add_opt(:since_id, params["since_id"])
    |> maybe_add_opt(:max_id, params["max_id"])
    |> maybe_add_opt(:with_ids, params["with_ids"])
  end

  defp maybe_add_opt(opts, _key, nil), do: opts

  defp maybe_add_opt(opts, key, value) when key in [:since_id, :max_id] do
    case Integer.parse(value) do
      {int, _} -> Keyword.put(opts, key, int)
      :error -> opts
    end
  end

  defp maybe_add_opt(opts, :with_ids, value) do
    Keyword.put(opts, :with_ids, value)
  end
end
