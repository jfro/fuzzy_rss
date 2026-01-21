defmodule FuzzyRssWeb.Api.GReader.TagController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.{Content, Api.GReader, Api.GReader.IdConverter}

  @doc """
  GET /reader/api/0/tag/list

  Returns all tags (default state tags + user folders as labels).
  """
  def list(conn, _params) do
    user = conn.assigns.current_user
    folders = Content.list_user_folders(user)

    tags = GReader.format_tag_list(folders, user.id)

    json(conn, %{tags: tags})
  end

  @doc """
  POST /reader/api/0/rename-tag

  Renames a folder/label.
  """
  def rename_tag(conn, %{"s" => source, "dest" => dest} = params) do
    user = conn.assigns.current_user

    with :ok <- verify_session_token(conn, params["T"]),
         {:ok, {:folder, old_name}} <- IdConverter.parse_stream_id(source),
         {:ok, {:folder, new_name}} <- IdConverter.parse_stream_id(dest),
         folder when not is_nil(folder) <- Content.get_user_folder_by_name(user, old_name),
         {:ok, _folder} <- Content.update_folder(folder, %{name: new_name}) do
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
  POST /reader/api/0/disable-tag

  Deletes a folder/label. Subscriptions in the folder are moved to root.
  """
  def disable_tag(conn, %{"s" => stream_id} = params) do
    user = conn.assigns.current_user

    with :ok <- verify_session_token(conn, params["T"]),
         {:ok, {:folder, folder_name}} <- IdConverter.parse_stream_id(stream_id) do
      case Content.get_user_folder_by_name(user, folder_name) do
        nil ->
          # Folder doesn't exist, but that's OK (idempotent)
          text(conn, "OK")

        folder ->
          # Delete folder (subscriptions will have folder_id set to nil via update)
          Content.delete_folder(folder)
          text(conn, "OK")
      end
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

  defp verify_session_token(conn, token) do
    stored = get_session(conn, :greader_session_token)

    if stored && stored == token do
      :ok
    else
      {:error, :invalid_token}
    end
  end
end
