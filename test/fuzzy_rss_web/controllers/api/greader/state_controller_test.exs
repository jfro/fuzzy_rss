defmodule FuzzyRssWeb.Api.GReader.StateControllerTest do
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

  describe "POST /reader/api/0/edit-tag with read state" do
    test "marks entry as read", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "a" => "user/-/state/com.google/read",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify entry is marked as read
      ues = Content.get_user_entry_state(user, entry.id)
      assert ues.read == true
    end

    test "marks entry as unread", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Mark as read first
      Content.mark_as_read(user, entry.id)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      # Mark as unread
      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "r" => "user/-/state/com.google/read",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify entry is marked as unread
      ues = Content.get_user_entry_state(user, entry.id)
      assert ues.read == false
    end

    test "handles batch operations", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)
      entry3 = entry_fixture(feed)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      # Mark multiple entries as read
      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => ["#{entry1.id}", "#{entry2.id}", "#{entry3.id}"],
          "a" => "user/-/state/com.google/read",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify all marked as read
      assert Content.get_user_entry_state(user, entry1.id).read == true
      assert Content.get_user_entry_state(user, entry2.id).read == true
      assert Content.get_user_entry_state(user, entry3.id).read == true
    end

    test "supports hex format IDs", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      hex_id = Integer.to_string(entry.id, 16) |> String.pad_leading(16, "0")

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => hex_id,
          "a" => "user/-/state/com.google/read",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"
      assert Content.get_user_entry_state(user, entry.id).read == true
    end

    test "supports long format IDs", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      hex_id = Integer.to_string(entry.id, 16) |> String.pad_leading(16, "0")
      long_id = "tag:google.com,2005:reader/item/#{hex_id}"

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => long_id,
          "a" => "user/-/state/com.google/read",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"
      assert Content.get_user_entry_state(user, entry.id).read == true
    end

    test "returns error without session token", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "a" => "user/-/state/com.google/read"
        })

      assert text_response(conn, 400) == "Error"
    end
  end

  describe "POST /reader/api/0/edit-tag with starred state" do
    test "marks entry as starred", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "a" => "user/-/state/com.google/starred",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify entry is starred
      ues = Content.get_user_entry_state(user, entry.id)
      assert ues.starred == true
    end

    test "marks entry as unstarred", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Star first
      Content.toggle_starred(user, entry.id)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      # Unstar
      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "r" => "user/-/state/com.google/starred",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify entry is unstarred
      ues = Content.get_user_entry_state(user, entry.id)
      assert ues.starred == false
    end

    test "handles combined read and star operations", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      # Mark as both read and starred
      conn =
        post(conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "a" => ["user/-/state/com.google/read", "user/-/state/com.google/starred"],
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify both states
      ues = Content.get_user_entry_state(user, entry.id)
      assert ues.read == true
      assert ues.starred == true
    end
  end

  describe "POST /reader/api/0/mark-all-as-read" do
    test "marks all entries in stream as read", %{conn: conn, user: user, api_key: api_key} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)
      entry3 = entry_fixture(feed)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      # Mark all as read
      conn =
        post(conn, "/reader/api/0/mark-all-as-read", %{
          "s" => "user/-/state/com.google/reading-list",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify all marked as read
      assert Content.get_user_entry_state(user, entry1.id).read == true
      assert Content.get_user_entry_state(user, entry2.id).read == true
      assert Content.get_user_entry_state(user, entry3.id).read == true
    end

    test "marks all in specific feed as read", %{conn: conn, user: user, api_key: api_key} do
      feed1 = feed_fixture(%{url: "https://example.com/feed1.xml"})
      feed2 = feed_fixture(%{url: "https://example.com/feed2.xml"})
      _sub1 = subscription_fixture(user, feed1)
      _sub2 = subscription_fixture(user, feed2)

      entry1 = entry_fixture(feed1)
      entry2 = entry_fixture(feed2)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      # Mark all in feed1 as read
      conn =
        post(conn, "/reader/api/0/mark-all-as-read", %{
          "s" => "feed/https://example.com/feed1.xml",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify only feed1 entries are marked
      assert Content.get_user_entry_state(user, entry1.id).read == true
      refute Content.get_user_entry_state(user, entry2.id)
    end

    test "marks all in folder as read", %{conn: conn, user: user, api_key: api_key} do
      folder = folder_fixture(user, %{name: "Tech"})
      feed1 = feed_fixture()
      feed2 = feed_fixture()
      _sub1 = subscription_fixture(user, feed1, %{folder_id: folder.id})
      _sub2 = subscription_fixture(user, feed2)

      entry1 = entry_fixture(feed1)
      entry2 = entry_fixture(feed2)

      # Get session token
      conn = get(conn, "/reader/api/0/token")
      session_token = text_response(conn, 200)
      conn = recycle(conn) |> auth_conn(api_key)

      # Mark all in folder as read
      conn =
        post(conn, "/reader/api/0/mark-all-as-read", %{
          "s" => "user/-/label/Tech",
          "T" => session_token
        })

      assert text_response(conn, 200) == "OK"

      # Verify only folder entries are marked
      assert Content.get_user_entry_state(user, entry1.id).read == true
      refute Content.get_user_entry_state(user, entry2.id)
    end

    test "returns error without session token", %{conn: conn} do
      conn =
        post(conn, "/reader/api/0/mark-all-as-read", %{
          "s" => "user/-/state/com.google/reading-list"
        })

      assert text_response(conn, 400) == "Error"
    end
  end
end
