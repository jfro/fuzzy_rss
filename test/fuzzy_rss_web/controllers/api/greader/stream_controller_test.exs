defmodule FuzzyRssWeb.Api.GReader.StreamControllerTest do
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

  describe "GET /reader/api/0/stream/contents/:stream_id" do
    test "returns entries for reading-list stream", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry1 = entry_fixture(feed, %{title: "Entry 1"})
      entry2 = entry_fixture(feed, %{title: "Entry 2"})

      conn = get(conn, "/reader/api/0/stream/contents/user/-/state/com.google/reading-list")

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 2

      titles = Enum.map(items, & &1["title"])
      assert "Entry 1" in titles
      assert "Entry 2" in titles
    end

    test "returns entries for starred stream", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry1 = entry_fixture(feed, %{title: "Starred Entry"})
      entry2 = entry_fixture(feed, %{title: "Unstarred Entry"})

      Content.toggle_starred(user, entry1.id)

      conn = get(conn, "/reader/api/0/stream/contents/user/-/state/com.google/starred")

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 1
      assert hd(items)["title"] == "Starred Entry"
    end

    test "returns entries for folder stream", %{conn: conn, user: user} do
      folder = folder_fixture(user, %{name: "Tech"})
      feed1 = feed_fixture(%{title: "Tech Feed"})
      feed2 = feed_fixture(%{title: "News Feed"})
      _sub1 = subscription_fixture(user, feed1, %{folder_id: folder.id})
      _sub2 = subscription_fixture(user, feed2)

      entry1 = entry_fixture(feed1, %{title: "Tech Entry"})
      _entry2 = entry_fixture(feed2, %{title: "News Entry"})

      conn = get(conn, "/reader/api/0/stream/contents/user/-/label/Tech")

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 1
      assert hd(items)["title"] == "Tech Entry"
    end

    test "returns entries for feed stream", %{conn: conn, user: user} do
      feed1 = feed_fixture(%{url: "https://example.com/feed1.xml"})
      feed2 = feed_fixture(%{url: "https://example.com/feed2.xml"})
      _sub1 = subscription_fixture(user, feed1)
      _sub2 = subscription_fixture(user, feed2)

      entry1 = entry_fixture(feed1, %{title: "Feed1 Entry"})
      _entry2 = entry_fixture(feed2, %{title: "Feed2 Entry"})

      conn = get(conn, "/reader/api/0/stream/contents/feed/https://example.com/feed1.xml")

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 1
      assert hd(items)["title"] == "Feed1 Entry"
    end

    test "supports pagination with n parameter", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)

      # Create 5 entries
      for i <- 1..5 do
        entry_fixture(feed, %{title: "Entry #{i}"})
      end

      conn = get(conn, "/reader/api/0/stream/contents/user/-/state/com.google/reading-list?n=3")

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 3
    end

    test "supports continuation token for pagination", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)

      # Create entries with specific timestamps
      entries =
        for i <- 1..5 do
          entry_fixture(feed, %{title: "Entry #{i}"})
        end

      # First request gets 3 items
      conn1 = get(conn, "/reader/api/0/stream/contents/user/-/state/com.google/reading-list?n=3")
      json1 = json_response(conn1, 200)
      assert length(json1["items"]) == 3

      # If continuation token is present, use it
      if continuation = json1["continuation"] do
        conn2 =
          get(
            conn,
            "/reader/api/0/stream/contents/user/-/state/com.google/reading-list?n=3&c=#{continuation}"
          )

        json2 = json_response(conn2, 200)
        assert length(json2["items"]) <= 2
      end
    end

    test "supports exclude target (xt) parameter", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry1 = entry_fixture(feed, %{title: "Read Entry"})
      entry2 = entry_fixture(feed, %{title: "Unread Entry"})

      Content.mark_as_read(user, entry1.id)

      conn =
        get(
          conn,
          "/reader/api/0/stream/contents/user/-/state/com.google/reading-list?xt=user/-/state/com.google/read"
        )

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 1
      assert hd(items)["title"] == "Unread Entry"
    end

    test "returns empty list for stream with no entries", %{conn: conn, user: user} do
      # User has no subscriptions
      conn = get(conn, "/reader/api/0/stream/contents/user/-/state/com.google/reading-list")

      assert json = json_response(conn, 200)
      assert json["items"] == []
    end
  end

  describe "GET /reader/api/0/stream/items/ids" do
    test "returns only item IDs for stream", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)

      conn = get(conn, "/reader/api/0/stream/items/ids?s=user/-/state/com.google/reading-list")

      assert json = json_response(conn, 200)
      assert item_refs = json["itemRefs"]
      assert length(item_refs) == 2

      # Each item ref should have id and timestamp
      Enum.each(item_refs, fn ref ->
        assert is_binary(ref["id"])
        assert is_list(ref["directStreamIds"])
      end)
    end

    test "supports pagination for IDs", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)

      for _i <- 1..5 do
        entry_fixture(feed)
      end

      conn =
        get(conn, "/reader/api/0/stream/items/ids?s=user/-/state/com.google/reading-list&n=3")

      assert json = json_response(conn, 200)
      assert item_refs = json["itemRefs"]
      assert length(item_refs) == 3
    end
  end

  describe "POST /reader/api/0/stream/items/contents" do
    test "returns entries by item IDs", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry1 = entry_fixture(feed, %{title: "Entry 1"})
      entry2 = entry_fixture(feed, %{title: "Entry 2"})

      # Use decimal IDs
      conn =
        post(conn, "/reader/api/0/stream/items/contents", %{
          "i" => ["#{entry1.id}", "#{entry2.id}"]
        })

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 2
    end

    test "supports hex format IDs", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed, %{title: "Entry 1"})

      # Convert to hex
      hex_id = Integer.to_string(entry.id, 16) |> String.pad_leading(16, "0")

      conn =
        post(conn, "/reader/api/0/stream/items/contents", %{
          "i" => [hex_id]
        })

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 1
      assert hd(items)["title"] == "Entry 1"
    end

    test "supports long format IDs", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed, %{title: "Entry 1"})

      # Convert to long format
      hex_id = Integer.to_string(entry.id, 16) |> String.pad_leading(16, "0")
      long_id = "tag:google.com,2005:reader/item/#{hex_id}"

      conn =
        post(conn, "/reader/api/0/stream/items/contents", %{
          "i" => [long_id]
        })

      assert json = json_response(conn, 200)
      assert items = json["items"]
      assert length(items) == 1
      assert hd(items)["title"] == "Entry 1"
    end

    test "returns empty list for non-existent IDs", %{conn: conn, user: user} do
      conn =
        post(conn, "/reader/api/0/stream/items/contents", %{
          "i" => ["999999", "888888"]
        })

      assert json = json_response(conn, 200)
      assert json["items"] == []
    end
  end

  describe "GET /reader/api/0/unread-count" do
    test "returns unread counts for all subscriptions", %{conn: conn, user: user} do
      feed1 = feed_fixture(%{url: "https://example.com/feed1.xml"})
      feed2 = feed_fixture(%{url: "https://example.com/feed2.xml"})
      _sub1 = subscription_fixture(user, feed1)
      _sub2 = subscription_fixture(user, feed2)

      entry1 = entry_fixture(feed1)
      entry2 = entry_fixture(feed1)
      entry3 = entry_fixture(feed2)

      # Mark one as read
      Content.mark_as_read(user, entry1.id)

      conn = get(conn, "/reader/api/0/unread-count")

      assert json = json_response(conn, 200)
      assert unreadcounts = json["unreadcounts"]
      assert is_list(unreadcounts)

      # Should have counts for reading-list and both feeds
      reading_list =
        Enum.find(unreadcounts, &(&1["id"] == "user/#{user.id}/state/com.google/reading-list"))

      assert reading_list["count"] == 2

      feed1_count = Enum.find(unreadcounts, &(&1["id"] == "feed/https://example.com/feed1.xml"))
      assert feed1_count["count"] == 1

      feed2_count = Enum.find(unreadcounts, &(&1["id"] == "feed/https://example.com/feed2.xml"))
      assert feed2_count["count"] == 1
    end

    test "includes folder unread counts", %{conn: conn, user: user} do
      folder = folder_fixture(user, %{name: "Tech"})
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed, %{folder_id: folder.id})

      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)

      conn = get(conn, "/reader/api/0/unread-count")

      assert json = json_response(conn, 200)
      assert unreadcounts = json["unreadcounts"]

      folder_count = Enum.find(unreadcounts, &(&1["id"] == "user/#{user.id}/label/Tech"))
      assert folder_count["count"] == 2
    end

    test "returns zero counts when all entries are read", %{conn: conn, user: user} do
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      Content.mark_as_read(user, entry.id)

      conn = get(conn, "/reader/api/0/unread-count")

      assert json = json_response(conn, 200)
      assert unreadcounts = json["unreadcounts"]

      reading_list =
        Enum.find(unreadcounts, &(&1["id"] == "user/#{user.id}/state/com.google/reading-list"))

      assert reading_list["count"] == 0
    end
  end
end
