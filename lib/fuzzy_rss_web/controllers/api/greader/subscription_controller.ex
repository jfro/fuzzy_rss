defmodule FuzzyRssWeb.Api.GReader.SubscriptionController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.{Content, Api.GReader, Api.GReader.IdConverter}

  @doc """
  GET /reader/api/0/subscription/list

  Returns all subscriptions with their categories (folders).
  """
  def list(conn, _params) do
    user = conn.assigns.current_user
    subscriptions = Content.list_subscriptions(user)

    formatted =
      Enum.map(subscriptions, fn sub ->
        GReader.format_subscription(sub, sub.folder, user.id)
      end)

    json(conn, %{subscriptions: formatted})
  end

  @doc """
  POST /reader/api/0/subscription/quickadd

  Quick subscribe to a feed by URL.
  """
  def quickadd(conn, %{"quickadd" => url} = params) do
    user = conn.assigns.current_user

    with :ok <- verify_session_token(conn, params["T"]),
         {:ok, subscription} <- Content.subscribe_to_feed(user, url) do
      subscription = Content.get_subscription!(subscription.id) |> repo().preload(:feed)

      json(conn, %{
        streamId: "feed/#{subscription.feed.url}",
        numResults: 1,
        query: url
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid session token"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: inspect(reason)})
    end
  end

  @doc """
  POST /reader/api/0/subscription/edit

  Handles subscribe, edit, and unsubscribe actions.
  """
  def edit(conn, %{"ac" => action, "s" => stream_id} = params) do
    user = conn.assigns.current_user

    with :ok <- verify_session_token(conn, params["T"]),
         {:ok, {:feed, feed_url}} <- IdConverter.parse_stream_id(stream_id) do
      handle_edit_action(action, user, feed_url, params)
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

  defp handle_edit_action("subscribe", user, feed_url, params) do
    folder_id = extract_folder_id(params["a"], user)
    Content.subscribe_to_feed(user, feed_url, folder_id: folder_id)
  end

  defp handle_edit_action("edit", user, feed_url, params) do
    case Content.get_user_subscription_by_url(user, feed_url) do
      nil ->
        :ok

      subscription ->
        folder_id = extract_folder_id(params["a"], user)
        Content.update_subscription(subscription, %{folder_id: folder_id})
    end
  end

  defp handle_edit_action("unsubscribe", user, feed_url, _params) do
    case Content.get_user_subscription_by_url(user, feed_url) do
      nil -> :ok
      subscription -> Content.unsubscribe_from_feed(user, subscription.feed_id)
    end
  end

  defp extract_folder_id(nil, _user), do: nil

  defp extract_folder_id(tag, user) do
    case IdConverter.parse_stream_id(tag) do
      {:ok, {:folder, name}} ->
        case Content.get_user_folder_by_name(user, name) do
          nil -> nil
          folder -> folder.id
        end

      _ ->
        nil
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

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)
end
