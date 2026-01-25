defmodule FuzzyRssWeb.Api.GReader.StateController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.{Content, Api.GReader.IdConverter}

  @doc """
  POST /reader/api/0/edit-tag

  Add or remove state tags (read, starred) to/from entries.
  Supports batch operations and all 3 ID formats.
  """
  def edit_tag(conn, params) do
    user = conn.assigns.current_user

    with :ok <- verify_session_token(conn, params["T"]),
         {:ok, item_ids} <- parse_item_ids(params["i"]),
         {:ok, add_tags, remove_tags} <- parse_tags(params) do
      apply_state_changes(user, item_ids, add_tags, remove_tags)
      text(conn, "OK")
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:bad_request)
        |> text("Error")

      _ ->
        conn
        |> put_status(:bad_request)
        |> text("Error")
    end
  end

  @doc """
  POST /reader/api/0/mark-all-as-read

  Marks all entries in a stream as read.
  Supports optional timestamp parameter.
  """
  def mark_all_as_read(conn, %{"s" => stream_id} = params) do
    user = conn.assigns.current_user

    with :ok <- verify_session_token(conn, params["T"]),
         {:ok, stream_type} <- IdConverter.parse_stream_id(stream_id) do
      opts = build_mark_all_opts(stream_type, params)
      Content.mark_all_as_read(user, opts)
      text(conn, "OK")
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:bad_request)
        |> text("Error")

      _ ->
        conn
        |> put_status(:bad_request)
        |> text("Error")
    end
  end

  # Private helpers

  defp parse_item_ids(nil), do: {:error, :no_items}

  defp parse_item_ids(ids) when is_list(ids) do
    parsed =
      Enum.flat_map(ids, fn id ->
        case IdConverter.parse_item_id(id) do
          {:ok, entry_id} -> [entry_id]
          _ -> []
        end
      end)

    if Enum.empty?(parsed) do
      {:error, :invalid_ids}
    else
      {:ok, parsed}
    end
  end

  defp parse_item_ids(id) when is_binary(id) do
    parse_item_ids([id])
  end

  defp parse_tags(params) do
    add_tags = parse_tag_list(params["a"])
    remove_tags = parse_tag_list(params["r"])

    {:ok, add_tags, remove_tags}
  end

  defp parse_tag_list(nil), do: []
  defp parse_tag_list(tag) when is_binary(tag), do: [tag]
  defp parse_tag_list(tags) when is_list(tags), do: tags

  defp apply_state_changes(user, item_ids, add_tags, remove_tags) do
    # Apply add tags
    Enum.each(add_tags, fn tag ->
      case parse_state_tag(tag) do
        {:ok, :read} ->
          Enum.each(item_ids, &Content.mark_as_read(user, &1))

        {:ok, :starred} ->
          Enum.each(item_ids, fn id ->
            # Only star if not already starred
            case Content.get_user_entry_state(user, id) do
              nil -> Content.toggle_starred(user, id)
              state -> unless state.starred, do: Content.toggle_starred(user, id)
            end
          end)

        _ ->
          :ok
      end
    end)

    # Apply remove tags
    Enum.each(remove_tags, fn tag ->
      case parse_state_tag(tag) do
        {:ok, :read} ->
          Enum.each(item_ids, &Content.mark_as_unread(user, &1))

        {:ok, :starred} ->
          Enum.each(item_ids, fn id ->
            # Only unstar if currently starred
            case Content.get_user_entry_state(user, id) do
              nil -> :ok
              state -> if state.starred, do: Content.toggle_starred(user, id)
            end
          end)

        _ ->
          :ok
      end
    end)
  end

  defp parse_state_tag(tag) do
    cond do
      String.contains?(tag, "/state/com.google/read") -> {:ok, :read}
      String.contains?(tag, "/state/com.google/starred") -> {:ok, :starred}
      true -> {:error, :unknown_tag}
    end
  end

  defp build_mark_all_opts(stream_type, params) do
    opts = []

    # Parse optional timestamp parameter (ts in seconds)
    opts =
      if ts = params["ts"] do
        timestamp = String.to_integer(ts)
        Keyword.put(opts, :older_than, timestamp)
      else
        opts
      end

    # Add stream-specific filters
    case stream_type do
      :all -> opts
      {:folder, folder_name} -> Keyword.put(opts, :folder_name, folder_name)
      {:feed, feed_url} -> Keyword.put(opts, :feed_url, feed_url)
      _ -> opts
    end
  end

  defp verify_session_token(conn, token) do
    stored = get_session(conn, :greader_session_token)

    if stored && stored == token do
      :ok
    else
      {:error, :invalid_token}
    end
  end
end
