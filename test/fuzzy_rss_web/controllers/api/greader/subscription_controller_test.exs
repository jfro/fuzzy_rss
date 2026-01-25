defmodule FuzzyRssWeb.Api.GReader.SubscriptionControllerTest do
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

  describe "GET /reader/api/0/subscription/list" do
    test "returns all subscriptions with folders", %{conn: conn, user: user} do
      folder = folder_fixture(user, %{name: "Tech"})
      feed1 = feed_fixture(%{title: "Feed 1"})
      feed2 = feed_fixture(%{title: "Feed 2"})
      _sub1 = subscription_fixture(user, feed1, %{folder_id: folder.id})
      _sub2 = subscription_fixture(user, feed2)

      conn = get(conn, "/reader/api/0/subscription/list")

      assert json = json_response(conn, 200)
      assert subscriptions = json["subscriptions"]
      assert length(subscriptions) == 2

      # Check that folder is included in categories
      sub_with_folder = Enum.find(subscriptions, &(&1["title"] == "Feed 1"))
      assert [category] = sub_with_folder["categories"]
      assert category["label"] == "Tech"
    end

    test "returns empty array when user has no feeds", %{conn: conn} do
      conn = get(conn, "/reader/api/0/subscription/list")

      assert json = json_response(conn, 200)
      assert json["subscriptions"] == []
    end
  end

  describe "POST /reader/api/0/subscription/quickadd" do
    test "subscribes to feed by URL", %{conn: conn, user: user, api_key: api_key} do
      # Get session token first
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)

      feed_url = "https://example.com/feed.xml"

      # Recycle conn to keep session, then re-add auth
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/subscription/quickadd", %{
          "quickadd" => feed_url,
          "T" => session_token
        })

      assert json = json_response(conn, 200)
      assert json["streamId"] == "feed/#{feed_url}"
      assert json["numResults"] == 1

      # Verify subscription was created
      assert Content.get_user_subscription_by_url(user, feed_url)
    end

    test "returns error without session token", %{conn: conn} do
      conn =
        post(conn, "/reader/api/0/subscription/quickadd", %{
          "quickadd" => "https://example.com/feed.xml"
        })

      assert json_response(conn, 400)
    end
  end

  describe "POST /reader/api/0/subscription/edit with ac=subscribe" do
    test "subscribes to feed with folder", %{conn: conn, user: user, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      folder = folder_fixture(user, %{name: "News"})
      feed_url = "https://example.com/news.xml"

      conn =
        post(conn, "/reader/api/0/subscription/edit", %{
          "ac" => "subscribe",
          "s" => "feed/#{feed_url}",
          "a" => "user/#{user.id}/label/News",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify subscription with folder
      sub = Content.get_user_subscription_by_url(user, feed_url)
      assert sub.folder_id == folder.id
    end
  end

  describe "POST /reader/api/0/subscription/edit with ac=edit" do
    test "moves feed to different folder", %{conn: conn, user: user, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      folder1 = folder_fixture(user, %{name: "Tech"})
      folder2 = folder_fixture(user, %{name: "News"})
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed, %{folder_id: folder1.id})

      conn =
        post(conn, "/reader/api/0/subscription/edit", %{
          "ac" => "edit",
          "s" => "feed/#{feed.url}",
          "a" => "user/#{user.id}/label/News",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify folder changed
      sub = Content.get_user_subscription_by_url(user, feed.url)
      assert sub.folder_id == folder2.id
    end

    test "removes feed from folder", %{conn: conn, user: user, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      folder = folder_fixture(user, %{name: "Tech"})
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed, %{folder_id: folder.id})

      conn =
        post(conn, "/reader/api/0/subscription/edit", %{
          "ac" => "edit",
          "s" => "feed/#{feed.url}",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify folder removed
      sub = Content.get_user_subscription_by_url(user, feed.url)
      assert sub.folder_id == nil
    end
  end

  describe "POST /reader/api/0/subscription/edit with ac=unsubscribe" do
    test "unsubscribes from feed", %{conn: conn, user: user, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)

      conn =
        post(conn, "/reader/api/0/subscription/edit", %{
          "ac" => "unsubscribe",
          "s" => "feed/#{feed.url}",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify subscription removed
      refute Content.get_user_subscription_by_url(user, feed.url)
    end

    test "returns OK even if not subscribed", %{conn: conn, api_key: api_key} do
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/subscription/edit", %{
          "ac" => "unsubscribe",
          "s" => "feed/https://example.com/notsubscribed.xml",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"
    end
  end
end
