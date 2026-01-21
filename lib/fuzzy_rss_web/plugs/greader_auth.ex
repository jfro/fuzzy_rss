defmodule FuzzyRssWeb.Plugs.GReaderAuth do
  @moduledoc """
  Plug for authenticating Google Reader API requests.

  Extracts the auth token from the `Authorization` header in the format:
  `Authorization: GoogleLogin auth=TOKEN`

  If authentication fails, returns a 401 Unauthorized response and halts the connection.

  Skips authentication for the `/accounts/ClientLogin` endpoint.
  """

  import Plug.Conn

  alias FuzzyRss.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    if skip_auth?(conn) do
      conn
    else
      authenticate(conn)
    end
  end

  defp skip_auth?(conn) do
    # ClientLogin endpoint doesn't require auth
    conn.request_path == "/accounts/ClientLogin"
  end

  defp authenticate(conn) do
    with [auth_header] <- get_req_header(conn, "authorization"),
         {:ok, token} <- parse_auth_header(auth_header),
         user when not is_nil(user) <- Accounts.get_user_by_api_password(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(:unauthorized, "Unauthorized")
        |> halt()
    end
  end

  defp parse_auth_header("GoogleLogin auth=" <> token) do
    {:ok, String.trim(token)}
  end

  defp parse_auth_header(_), do: {:error, :invalid_format}
end
