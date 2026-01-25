defmodule FuzzyRssWeb.Api.GReader.AuthController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.Accounts

  @doc """
  POST /accounts/ClientLogin

  Authenticates user with email and API password, returns auth tokens.
  The client sends the plain-text password, which we hash and compare to stored hash.
  """
  def client_login(conn, %{"Email" => email, "Passwd" => password}) do
    # First try to get user by email
    user = Accounts.get_user_by_email(email)

    cond do
      # User not found
      is_nil(user) ->
        conn
        |> put_status(:forbidden)
        |> text("Error=BadAuthentication")

      # User has no API password set
      is_nil(user.api_password) ->
        conn
        |> put_status(:forbidden)
        |> text("Error=BadAuthentication")

      # Hash the incoming password and verify it matches
      true ->
        hashed_password =
          :crypto.hash(:md5, "#{email}:#{password}") |> Base.encode16(case: :lower)

        if user.api_password == hashed_password do
          response = """
          SID=#{user.api_password}
          Auth=#{user.api_password}
          """

          text(conn, response)
        else
          conn
          |> put_status(:forbidden)
          |> text("Error=BadAuthentication")
        end
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
end
