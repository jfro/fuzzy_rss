defmodule FuzzyRssWeb.Plugs.GReaderAuthTest do
  use FuzzyRssWeb.ConnCase

  import FuzzyRss.AccountsFixtures
  alias FuzzyRss.Accounts
  alias FuzzyRssWeb.Plugs.GReaderAuth

  describe "call/2" do
    setup do
      user = user_fixture()
      {:ok, user} = Accounts.set_api_password(user, "testpass")
      api_key = :crypto.hash(:md5, "#{user.email}:testpass") |> Base.encode16(case: :lower)
      %{user: user, api_key: api_key}
    end

    test "authenticates user with valid Authorization header", %{
      conn: conn,
      user: user,
      api_key: api_key
    } do
      conn =
        conn
        |> put_req_header("authorization", "GoogleLogin auth=#{api_key}")
        |> GReaderAuth.call(%{})

      assert conn.assigns.current_user.id == user.id
      refute conn.halted
    end

    test "returns 401 for invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "GoogleLogin auth=invalid")
        |> GReaderAuth.call(%{})

      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body == "Unauthorized"
    end

    test "returns 401 for missing header", %{conn: conn} do
      conn = GReaderAuth.call(conn, %{})

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 for malformed header (missing GoogleLogin)", %{conn: conn, api_key: api_key} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{api_key}")
        |> GReaderAuth.call(%{})

      assert conn.halted
      assert conn.status == 401
    end

    test "returns 401 for malformed header (missing auth=)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "GoogleLogin sometoken")
        |> GReaderAuth.call(%{})

      assert conn.halted
      assert conn.status == 401
    end

    test "skips auth for /accounts/ClientLogin path", %{conn: conn} do
      conn =
        %{conn | request_path: "/accounts/ClientLogin"}
        |> GReaderAuth.call(%{})

      refute conn.halted
      refute Map.has_key?(conn.assigns, :current_user)
    end
  end
end
