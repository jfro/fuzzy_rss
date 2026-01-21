defmodule FuzzyRssWeb.Plugs.FeverAuth do
  @moduledoc """
  Plug for authenticating Fever API requests.

  Extracts the `api_key` parameter from the request and authenticates the user.
  If authentication fails, returns a JSON response with `auth: 0` and halts the connection.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias FuzzyRss.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    # Fetch params if not already fetched
    conn = fetch_query_params(conn)

    with api_key when not is_nil(api_key) <- conn.params["api_key"],
         user when not is_nil(user) <- Accounts.get_user_by_api_password(api_key) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{api_version: 3, auth: 0})
        |> halt()
    end
  end
end
