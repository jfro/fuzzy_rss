defmodule FuzzyRssWeb.Api.GReader.AuthControllerTest do
  use FuzzyRssWeb.ConnCase

  import FuzzyRss.AccountsFixtures
  alias FuzzyRss.Accounts

  describe "POST /accounts/ClientLogin" do
    test "returns SID and Auth tokens for valid credentials", %{conn: conn} do
      user = user_fixture()
      # Set API password for the user
      {:ok, user} = Accounts.set_api_password(user, "validpassword123")

      conn =
        post(conn, "/accounts/ClientLogin", %{
          "Email" => user.email,
          "Passwd" => "validpassword123"
        })

      assert response = text_response(conn, 200)
      assert response =~ "SID="
      assert response =~ "Auth="

      # Parse the response
      lines = String.split(response, "\n", trim: true)
      assert length(lines) >= 2

      # Both tokens should be the same (MD5 hash)
      [sid_line, auth_line | _] = lines
      assert String.starts_with?(sid_line, "SID=")
      assert String.starts_with?(auth_line, "Auth=")

      sid_token = String.replace_prefix(sid_line, "SID=", "")
      auth_token = String.replace_prefix(auth_line, "Auth=", "")
      assert sid_token == auth_token
      # MD5 hash length
      assert String.length(sid_token) == 32
    end

    test "returns 403 with Error=BadAuthentication for invalid password", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.set_api_password(user, "validpassword123")

      conn =
        post(conn, "/accounts/ClientLogin", %{
          "Email" => user.email,
          "Passwd" => "wrongpassword"
        })

      assert response = text_response(conn, 403)
      assert response == "Error=BadAuthentication"
    end

    test "returns 403 for non-existent user", %{conn: conn} do
      conn =
        post(conn, "/accounts/ClientLogin", %{
          "Email" => "nonexistent@example.com",
          "Passwd" => "anypassword"
        })

      assert response = text_response(conn, 403)
      assert response == "Error=BadAuthentication"
    end
  end

  describe "GET /reader/api/0/token" do
    setup %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.set_api_password(user, "testpass")
      api_key = :crypto.hash(:md5, "#{user.email}:testpass") |> Base.encode16(case: :lower)

      conn =
        conn
        |> put_req_header("authorization", "GoogleLogin auth=#{api_key}")

      %{conn: conn, user: user}
    end

    test "returns 57-char session token for authenticated user", %{conn: conn} do
      conn = get(conn, "/reader/api/0/token")

      assert token = text_response(conn, 200)
      assert String.length(token) == 57
      assert token =~ ~r/^[a-zA-Z0-9]+$/
    end

    test "stores session token in conn session", %{conn: conn} do
      conn = get(conn, "/reader/api/0/token")

      token = text_response(conn, 200)
      assert get_session(conn, :greader_session_token) == token
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      # Remove auth header
      conn = delete_req_header(conn, "authorization")
      conn = get(conn, "/reader/api/0/token")

      assert conn.status == 401
    end
  end

  describe "GET /reader/api/0/user-info" do
    setup %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.set_api_password(user, "testpass")
      api_key = :crypto.hash(:md5, "#{user.email}:testpass") |> Base.encode16(case: :lower)

      conn =
        conn
        |> put_req_header("authorization", "GoogleLogin auth=#{api_key}")

      %{conn: conn, user: user}
    end

    test "returns user profile JSON", %{conn: conn, user: user} do
      conn = get(conn, "/reader/api/0/user-info")

      assert json = json_response(conn, 200)
      assert json["userId"] == "user/#{user.id}"
      assert json["userName"] == user.email
      assert json["userEmail"] == user.email
      assert json["userProfileId"] == "#{user.id}"
      assert json["isBloggerUser"] == false
      assert is_integer(json["signupTimeSec"])
      assert json["isMultiLoginEnabled"] == false
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = delete_req_header(conn, "authorization")
      conn = get(conn, "/reader/api/0/user-info")

      assert conn.status == 401
    end
  end
end
