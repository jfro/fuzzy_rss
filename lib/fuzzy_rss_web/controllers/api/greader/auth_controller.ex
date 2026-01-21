defmodule FuzzyRssWeb.Api.GReader.AuthController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.Accounts

  @doc """
  POST /accounts/ClientLogin

  Authenticates user with email and password, returns auth tokens.
  """
  def client_login(conn, %{"Email" => email, "Passwd" => password}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_status(:forbidden)
        |> text("Error=BadAuthentication")

      user ->
        # Ensure user has API password set
        user = ensure_api_password(user, password)

        response = """
        SID=#{user.api_password}
        Auth=#{user.api_password}
        """

        text(conn, response)
    end
  end

  def client_login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> text("Error=BadRequest")
  end

  @doc """
  GET /reader/api/0/token

  Returns a session token for CSRF protection in write operations.
  """
  def token(conn, _params) do
    session_token = Accounts.generate_greader_session_token()

    conn
    |> put_session(:greader_session_token, session_token)
    |> text(session_token)
  end

  @doc """
  GET /reader/api/0/user-info

  Returns user profile information.
  """
  def user_info(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      userId: "user/#{user.id}",
      userName: user.email,
      userEmail: user.email,
      userProfileId: "#{user.id}",
      isBloggerUser: false,
      signupTimeSec: DateTime.to_unix(user.inserted_at),
      isMultiLoginEnabled: false
    })
  end

  # Private helpers

  defp ensure_api_password(%{api_password: nil} = user, password) do
    {:ok, user} = Accounts.set_api_password(user, password)
    user
  end

  defp ensure_api_password(user, _password), do: user
end
