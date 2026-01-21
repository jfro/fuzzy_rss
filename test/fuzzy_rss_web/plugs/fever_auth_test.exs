defmodule FuzzyRssWeb.Plugs.FeverAuthTest do
  use FuzzyRssWeb.ConnCase

  import FuzzyRss.AccountsFixtures

  alias FuzzyRssWeb.Plugs.FeverAuth
  alias FuzzyRss.Accounts

  setup do
    user = user_fixture()
    {:ok, user} = Accounts.set_api_password(user, "testpass")
    api_key = :crypto.hash(:md5, "#{user.email}:testpass") |> Base.encode16(case: :lower)
    %{user: user, api_key: api_key}
  end

  describe "call/2" do
    test "authenticates user with valid API key in POST params", %{
      conn: conn,
      user: user,
      api_key: api_key
    } do
      conn =
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> Map.put(:params, %{"api_key" => api_key})
        |> FeverAuth.call(%{})

      assert conn.assigns.current_user.id == user.id
      refute conn.halted
    end

    test "halts with 401 and returns auth:0 for invalid API key", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"api_key" => "invalid"})
        |> FeverAuth.call(%{})

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"api_version" => 3, "auth" => 0}
    end

    test "halts with 401 and returns auth:0 when API key is missing", %{conn: conn} do
      conn = FeverAuth.call(conn, %{})

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"api_version" => 3, "auth" => 0}
    end

    test "authenticates user with valid API key in GET query params", %{
      conn: conn,
      user: user,
      api_key: api_key
    } do
      conn =
        conn
        |> Map.put(:params, %{"api_key" => api_key})
        |> FeverAuth.call(%{})

      assert conn.assigns.current_user.id == user.id
      refute conn.halted
    end
  end
end
