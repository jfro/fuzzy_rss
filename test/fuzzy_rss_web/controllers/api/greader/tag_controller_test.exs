defmodule FuzzyRssWeb.Api.GReader.TagControllerTest do
  use FuzzyRssWeb.ConnCase

  import FuzzyRss.AccountsFixtures
  import FuzzyRss.ContentFixtures
  alias FuzzyRss.{Accounts, Content}

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, user} = Accounts.set_api_password(user, "testpass")
    api_key = :crypto.hash(:md5, "#{user.email}:testpass") |> Base.encode16(case: :lower)

    conn =
      conn
      |> put_req_header("authorization", "GoogleLogin auth=#{api_key}")

    %{conn: conn, user: user, api_key: api_key}
  end

  defp auth_conn(conn, api_key) do
    put_req_header(conn, "authorization", "GoogleLogin auth=#{api_key}")
  end

  describe "GET /reader/api/0/tag/list" do
    test "returns default state tags", %{conn: conn, user: user} do
      conn = get(conn, "/reader/api/0/tag/list")

      assert json = json_response(conn, 200)
      assert tags = json["tags"]
      assert length(tags) >= 3

      # Check default tags
      reading_list =
        Enum.find(tags, &(&1["id"] == "user/#{user.id}/state/com.google/reading-list"))

      assert reading_list["sortid"] == "01"

      starred = Enum.find(tags, &(&1["id"] == "user/#{user.id}/state/com.google/starred"))
      assert starred["sortid"] == "02"

      read = Enum.find(tags, &(&1["id"] == "user/#{user.id}/state/com.google/read"))
      assert read["sortid"] == "03"
    end

    test "includes user folders as label tags", %{conn: conn, user: user} do
      _folder1 = folder_fixture(user, %{name: "Tech"})
      _folder2 = folder_fixture(user, %{name: "News"})

      conn = get(conn, "/reader/api/0/tag/list")

      assert json = json_response(conn, 200)
      assert tags = json["tags"]
      assert length(tags) == 5

      tech_tag = Enum.find(tags, &(&1["id"] == "user/#{user.id}/label/Tech"))
      assert tech_tag
      assert String.starts_with?(tech_tag["sortid"], "A")

      news_tag = Enum.find(tags, &(&1["id"] == "user/#{user.id}/label/News"))
      assert news_tag
      assert String.starts_with?(news_tag["sortid"], "A")
    end

    test "returns empty folders list when user has no folders", %{conn: conn} do
      conn = get(conn, "/reader/api/0/tag/list")

      assert json = json_response(conn, 200)
      assert tags = json["tags"]
      # Only default state tags
      assert length(tags) == 3
    end
  end

  describe "POST /reader/api/0/rename-tag" do
    test "renames a folder", %{conn: conn, user: user, api_key: api_key} do
      folder = folder_fixture(user, %{name: "OldName"})

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/rename-tag", %{
          "s" => "user/#{user.id}/label/OldName",
          "dest" => "user/#{user.id}/label/NewName",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify folder was renamed
      folder = Content.get_folder!(folder.id)
      assert folder.name == "NewName"
    end

    test "returns error without session token", %{conn: conn, user: user} do
      _folder = folder_fixture(user, %{name: "OldName"})

      conn =
        post(conn, "/reader/api/0/rename-tag", %{
          "s" => "user/#{user.id}/label/OldName",
          "dest" => "user/#{user.id}/label/NewName"
        })

      assert text_response(conn, 400) == "Error"
    end

    test "returns error for non-existent folder", %{conn: conn, user: user, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/rename-tag", %{
          "s" => "user/#{user.id}/label/NonExistent",
          "dest" => "user/#{user.id}/label/NewName",
          "T" => session_token
        })

      assert text_response(conn, 400) == "Error"
    end

    test "returns error for invalid stream ID format", %{conn: conn, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/rename-tag", %{
          "s" => "invalid/stream/id",
          "dest" => "user/-/label/NewName",
          "T" => session_token
        })

      assert text_response(conn, 400) == "Error"
    end
  end

  describe "POST /reader/api/0/disable-tag" do
    test "deletes a folder and moves subscriptions to root", %{
      conn: conn,
      user: user,
      api_key: api_key
    } do
      folder = folder_fixture(user, %{name: "Tech"})
      feed = feed_fixture()
      sub = subscription_fixture(user, feed, %{folder_id: folder.id})

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/disable-tag", %{
          "s" => "user/#{user.id}/label/Tech",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify folder was deleted
      assert_raise Ecto.NoResultsError, fn ->
        Content.get_folder!(folder.id)
      end

      # Verify subscription moved to root (folder_id = nil)
      subscription = Content.get_subscription!(sub.id)
      assert subscription.folder_id == nil
    end

    test "returns OK even if folder doesn't exist", %{conn: conn, user: user, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/disable-tag", %{
          "s" => "user/#{user.id}/label/NonExistent",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"
    end

    test "returns error without session token", %{conn: conn, user: user} do
      _folder = folder_fixture(user, %{name: "Tech"})

      conn =
        post(conn, "/reader/api/0/disable-tag", %{
          "s" => "user/#{user.id}/label/Tech"
        })

      assert text_response(conn, 400) == "Error"
    end

    test "returns error for invalid stream ID format", %{conn: conn, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/disable-tag", %{
          "s" => "invalid/stream/id",
          "T" => session_token
        })

      assert text_response(conn, 400) == "Error"
    end
  end
end
