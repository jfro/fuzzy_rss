defmodule FuzzyRssWeb.Plugs.ExpandedFolders do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user
    cookie_name = if user, do: "expanded_folders_#{user.id}", else: "expanded_folders"

    expanded_folders =
      case conn.cookies[cookie_name] do
        nil ->
          []

        json_str ->
          # Decode the cookie value in case it was URI encoded (which we do in JS)
          decoded_json = URI.decode(json_str)

          case Jason.decode(decoded_json) do
            {:ok, list} when is_list(list) -> list
            _ -> []
          end
      end

    put_session(conn, "expanded_folders", expanded_folders)
  end
end
