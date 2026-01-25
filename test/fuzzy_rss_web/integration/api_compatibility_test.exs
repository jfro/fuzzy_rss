defmodule FuzzyRssWeb.Integration.ApiCompatibilityTest do
  use FuzzyRssWeb.ConnCase

  import FuzzyRss.AccountsFixtures
  import FuzzyRss.ContentFixtures
  alias FuzzyRss.{Accounts, Content}

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, user} = Accounts.set_api_password(user, "testpass")

    # API keys for both APIs (they use the same password)
    api_key = :crypto.hash(:md5, "#{user.email}:testpass") |> Base.encode16(case: :lower)

    # Fever auth setup
    fever_conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    # GReader auth setup
    greader_conn =
      conn
      |> put_req_header("authorization", "GoogleLogin auth=#{api_key}")

    %{
      conn: conn,
      user: user,
      api_key: api_key,
      fever_conn: fever_conn,
      greader_conn: greader_conn
    }
  end

  defp auth_conn(conn, api_key) do
    put_req_header(conn, "authorization", "GoogleLogin auth=#{api_key}")
  end

  describe "Cross-API Feed Management" do
    test "feed added via GReader appears in Fever API", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Get GReader session token
      greader_conn = get(greader_conn, "/reader/api/0/token")
      session_token = text_response(greader_conn, 200)
      greader_conn = recycle(greader_conn) |> auth_conn(api_key)

      # Add feed via GReader
      feed_url = "https://example.com/crossapi-feed.xml"

      greader_conn =
        post(greader_conn, "/reader/api/0/subscription/quickadd", %{
          "quickadd" => feed_url,
          "T" => session_token
        })

      assert json_response(greader_conn, 200)

      # Verify feed appears in Fever API
      fever_conn = post(fever_conn, "/fever/?api&feeds", %{api_key: api_key})
      fever_json = json_response(fever_conn, 200)

      feeds = fever_json["feeds"]
      assert Enum.any?(feeds, fn feed -> feed["url"] == feed_url end)
    end

    test "feed added via Fever appears in GReader API", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Add feed via Fever (done through Content context)
      feed_url = "https://example.com/fever-feed.xml"
      Content.subscribe_to_feed(user, feed_url)

      # Verify feed appears in GReader API
      greader_conn = get(greader_conn, "/reader/api/0/subscription/list")
      greader_json = json_response(greader_conn, 200)

      subscriptions = greader_json["subscriptions"]
      assert Enum.any?(subscriptions, fn sub -> sub["id"] == "feed/#{feed_url}" end)
    end
  end

  describe "Cross-API Read State" do
    test "entry marked read in Fever syncs to GReader", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Setup: Create feed, subscription, and entry
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Mark as read via Fever
      fever_conn =
        post(fever_conn, "/fever/?api&mark=item&as=read&id=#{entry.id}", %{
          api_key: api_key
        })

      assert json_response(fever_conn, 200)

      # Verify read state in GReader
      greader_conn =
        get(greader_conn, "/reader/api/0/stream/contents/user/-/state/com.google/reading-list")

      greader_json = json_response(greader_conn, 200)

      items = greader_json["items"]

      item =
        Enum.find(items, fn i -> String.contains?(i["id"], Integer.to_string(entry.id, 16)) end)

      assert item
      assert "user/#{user.id}/state/com.google/read" in item["categories"]
    end

    test "entry marked read in GReader syncs to Fever", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Setup: Create feed, subscription, and entry
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Get GReader session token
      greader_conn = get(greader_conn, "/reader/api/0/token")
      session_token = text_response(greader_conn, 200)
      greader_conn = recycle(greader_conn) |> auth_conn(api_key)

      # Mark as read via GReader
      greader_conn =
        post(greader_conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "a" => "user/-/state/com.google/read",
          "T" => session_token
        })

      assert text_response(greader_conn, 200) == "OK"

      # Verify read state in Fever
      fever_conn = post(fever_conn, "/fever/?api&unread_item_ids", %{api_key: api_key})
      fever_json = json_response(fever_conn, 200)

      # Entry should NOT be in unread list
      unread_ids_str = fever_json["unread_item_ids"] || ""
      unread_ids = if unread_ids_str == "", do: [], else: String.split(unread_ids_str, ",")
      refute Enum.member?(unread_ids, "#{entry.id}")
    end

    test "entry marked unread in Fever syncs to GReader", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Setup: Create feed, subscription, entry, and mark as read first
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)
      Content.mark_as_read(user, entry.id)

      # Mark as unread via Fever
      fever_conn =
        post(fever_conn, "/fever/?api&mark=item&as=unread&id=#{entry.id}", %{
          api_key: api_key
        })

      assert json_response(fever_conn, 200)

      # Verify unread state in GReader
      greader_conn =
        get(greader_conn, "/reader/api/0/stream/contents/user/-/state/com.google/reading-list")

      greader_json = json_response(greader_conn, 200)

      items = greader_json["items"]

      item =
        Enum.find(items, fn i -> String.contains?(i["id"], Integer.to_string(entry.id, 16)) end)

      assert item
      refute "user/#{user.id}/state/com.google/read" in item["categories"]
    end
  end

  describe "Cross-API Starred State" do
    test "entry starred in Fever syncs to GReader", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Setup: Create feed, subscription, and entry
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Star via Fever
      fever_conn =
        post(fever_conn, "/fever/?api&mark=item&as=saved&id=#{entry.id}", %{
          api_key: api_key
        })

      assert json_response(fever_conn, 200)

      # Verify starred in GReader
      greader_conn =
        get(greader_conn, "/reader/api/0/stream/contents/user/-/state/com.google/starred")

      greader_json = json_response(greader_conn, 200)

      items = greader_json["items"]
      assert length(items) == 1
      assert "user/#{user.id}/state/com.google/starred" in hd(items)["categories"]
    end

    test "entry starred in GReader syncs to Fever", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Setup: Create feed, subscription, and entry
      feed = feed_fixture()
      _sub = subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # Get GReader session token
      greader_conn = get(greader_conn, "/reader/api/0/token")
      session_token = text_response(greader_conn, 200)
      greader_conn = recycle(greader_conn) |> auth_conn(api_key)

      # Star via GReader
      greader_conn =
        post(greader_conn, "/reader/api/0/edit-tag", %{
          "i" => "#{entry.id}",
          "a" => "user/-/state/com.google/starred",
          "T" => session_token
        })

      assert text_response(greader_conn, 200) == "OK"

      # Verify starred in Fever
      fever_conn = post(fever_conn, "/fever/?api&saved_item_ids", %{api_key: api_key})
      fever_json = json_response(fever_conn, 200)

      saved_ids_str = fever_json["saved_item_ids"] || ""
      saved_ids = if saved_ids_str == "", do: [], else: String.split(saved_ids_str, ",")
      assert Enum.member?(saved_ids, "#{entry.id}")
    end
  end

  describe "Cross-API Folder/Group Management" do
    test "folder created in Fever appears as label in GReader", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user
    } do
      # Create folder via Content context (Fever uses Content directly)
      folder = folder_fixture(user, %{name: "Tech News"})

      # Verify appears in GReader
      greader_conn = get(greader_conn, "/reader/api/0/tag/list")
      greader_json = json_response(greader_conn, 200)

      tags = greader_json["tags"]
      assert Enum.any?(tags, fn tag -> tag["id"] == "user/#{user.id}/label/Tech News" end)
    end

    test "label/folder in GReader appears as group in Fever", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Create folder via Content context
      folder = folder_fixture(user, %{name: "Science"})

      # Verify appears in Fever (Fever groups are folders)
      fever_conn = post(fever_conn, "/fever/?api&groups", %{api_key: api_key})
      fever_json = json_response(fever_conn, 200)

      groups = fever_json["groups"]
      assert Enum.any?(groups, fn group -> group["title"] == "Science" end)
    end

    test "feed in folder syncs between APIs", %{
      fever_conn: fever_conn,
      greader_conn: greader_conn,
      user: user,
      api_key: api_key
    } do
      # Create folder and feed subscription in that folder
      folder = folder_fixture(user, %{name: "Programming"})
      feed = feed_fixture(%{url: "https://example.com/prog.xml"})
      _sub = subscription_fixture(user, feed, %{folder_id: folder.id})

      # Verify in GReader
      greader_conn = get(greader_conn, "/reader/api/0/subscription/list")
      greader_json = json_response(greader_conn, 200)

      subscriptions = greader_json["subscriptions"]
      sub = Enum.find(subscriptions, fn s -> s["id"] == "feed/#{feed.url}" end)
      assert sub
      assert [category] = sub["categories"]
      assert category["label"] == "Programming"

      # Verify in Fever
      fever_conn = post(fever_conn, "/fever/?api&groups", %{api_key: api_key})
      fever_json = json_response(fever_conn, 200)

      groups = fever_json["groups"]
      group = Enum.find(groups, fn g -> g["title"] == "Programming" end)
      assert group

      fever_conn = post(fever_conn, "/fever/?api&feeds", %{api_key: api_key})
      fever_json = json_response(fever_conn, 200)

      feeds_groups = fever_json["feeds_groups"]
      assert feeds_groups, "feeds_groups should be present in response"

      assert Enum.any?(feeds_groups, fn fg ->
               fg["group_id"] == group["id"] && fg["feed_ids"] =~ Integer.to_string(feed.id)
             end)
    end
  end
end
