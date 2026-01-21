defmodule FuzzyRssWeb.Api.FeverControllerTest do
  use FuzzyRssWeb.ConnCase

  import FuzzyRss.AccountsFixtures
  import FuzzyRss.ContentFixtures

  alias FuzzyRss.{Accounts, Content}

  setup do
    user = user_fixture()
    {:ok, user} = Accounts.set_fever_api_key(user, "testpass")
    api_key = :crypto.hash(:md5, "#{user.email}:testpass") |> Base.encode16(case: :lower)
    %{user: user, api_key: api_key}
  end

  describe "GET /fever/?api - auth check" do
    test "returns auth: 1 with valid API key", %{conn: conn, api_key: api_key} do
      conn = get(conn, ~p"/fever/?api", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["api_version"] == 3
      assert json["auth"] == 1
    end

    test "returns auth: 0 with invalid API key", %{conn: conn} do
      conn = get(conn, ~p"/fever/?api", api_key: "invalid")

      assert json = json_response(conn, 401)
      assert json["api_version"] == 3
      assert json["auth"] == 0
    end

    test "works with POST request", %{conn: conn, api_key: api_key} do
      conn = post(conn, ~p"/fever/?api", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["auth"] == 1
    end
  end

  describe "GET /fever/?api&groups" do
    test "returns folders as Fever groups", %{conn: conn, api_key: api_key, user: user} do
      {:ok, folder1} = Content.create_folder(user, %{name: "Tech", slug: "tech"})
      {:ok, folder2} = Content.create_folder(user, %{name: "News", slug: "news"})

      conn = get(conn, ~p"/fever/?api&groups", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["auth"] == 1
      assert length(json["groups"]) == 2
      assert Enum.any?(json["groups"], &(&1["id"] == folder1.id && &1["title"] == "Tech"))
      assert Enum.any?(json["groups"], &(&1["id"] == folder2.id && &1["title"] == "News"))
    end

    test "returns empty groups when no folders exist", %{conn: conn, api_key: api_key} do
      conn = get(conn, ~p"/fever/?api&groups", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["groups"] == []
    end
  end

  describe "GET /fever/?api&feeds" do
    test "returns feeds with feeds_groups mapping", %{conn: conn, api_key: api_key, user: user} do
      {:ok, folder} = Content.create_folder(user, %{name: "Tech", slug: "tech"})

      feed1 = feed_fixture(%{"title" => "Feed 1", "site_url" => "https://example.com"})
      feed2 = feed_fixture(%{"title" => "Feed 2"})

      subscription_fixture(user, feed1, %{"folder_id" => folder.id})
      subscription_fixture(user, feed2)

      conn = get(conn, ~p"/fever/?api&feeds", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["auth"] == 1
      assert length(json["feeds"]) == 2

      feed1_data = Enum.find(json["feeds"], &(&1["id"] == feed1.id))
      assert feed1_data["title"] == "Feed 1"
      assert feed1_data["url"] == feed1.url
      assert feed1_data["site_url"] == "https://example.com"
      assert feed1_data["is_spark"] == 0
      assert is_integer(feed1_data["last_updated_on_time"])

      # feeds_groups should have one entry for the folder
      assert length(json["feeds_groups"]) == 1
      assert hd(json["feeds_groups"])["group_id"] == folder.id
      assert hd(json["feeds_groups"])["feed_ids"] =~ Integer.to_string(feed1.id)
    end

    test "returns empty feeds when no subscriptions", %{conn: conn, api_key: api_key} do
      conn = get(conn, ~p"/fever/?api&feeds", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["feeds"] == []
      assert json["feeds_groups"] == []
    end
  end

  describe "GET /fever/?api&items" do
    test "returns items with default pagination", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry1 = entry_fixture(feed, %{"title" => "Entry 1"})
      _entry2 = entry_fixture(feed, %{"title" => "Entry 2"})

      conn = get(conn, ~p"/fever/?api&items", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["auth"] == 1
      assert length(json["items"]) == 2
      assert json["total_items"] == 2

      item1 = Enum.find(json["items"], &(&1["id"] == entry1.id))
      assert item1["feed_id"] == feed.id
      assert item1["title"] == "Entry 1"
      assert item1["is_read"] == 0
      assert item1["is_saved"] == 0
    end

    test "supports since_id pagination", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry1 = entry_fixture(feed, %{"title" => "Entry 1"})
      _entry2 = entry_fixture(feed, %{"title" => "Entry 2"})

      conn = get(conn, ~p"/fever/?api&items&since_id=#{entry1.id}", api_key: api_key)

      assert json = json_response(conn, 200)
      assert Enum.all?(json["items"], &(&1["id"] > entry1.id))
    end

    test "supports max_id pagination", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry1 = entry_fixture(feed, %{"title" => "Entry 1"})
      _entry2 = entry_fixture(feed, %{"title" => "Entry 2"})

      conn = get(conn, ~p"/fever/?api&items&max_id=#{entry1.id}", api_key: api_key)

      assert json = json_response(conn, 200)
      assert Enum.all?(json["items"], &(&1["id"] <= entry1.id))
    end

    test "supports with_ids parameter", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry1 = entry_fixture(feed, %{"title" => "Entry 1"})
      entry2 = entry_fixture(feed, %{"title" => "Entry 2"})
      entry3 = entry_fixture(feed, %{"title" => "Entry 3"})

      ids = "#{entry1.id},#{entry3.id}"
      conn = get(conn, ~p"/fever/?api&items&with_ids=#{ids}", api_key: api_key)

      assert json = json_response(conn, 200)
      assert length(json["items"]) == 2
      assert Enum.any?(json["items"], &(&1["id"] == entry1.id))
      assert Enum.any?(json["items"], &(&1["id"] == entry3.id))
      refute Enum.any?(json["items"], &(&1["id"] == entry2.id))
    end

    test "reflects read and starred state", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry = entry_fixture(feed, %{"title" => "Entry 1"})

      Content.mark_as_read(user, entry.id)
      Content.toggle_starred(user, entry.id)

      conn = get(conn, ~p"/fever/?api&items", api_key: api_key)

      assert json = json_response(conn, 200)
      item = Enum.find(json["items"], &(&1["id"] == entry.id))
      assert item["is_read"] == 1
      assert item["is_saved"] == 1
    end
  end

  describe "GET /fever/?api&unread_item_ids" do
    test "returns comma-separated unread entry IDs", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)
      entry3 = entry_fixture(feed)

      Content.mark_as_read(user, entry2.id)

      conn = get(conn, ~p"/fever/?api&unread_item_ids", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["auth"] == 1
      assert is_binary(json["unread_item_ids"])
      assert json["unread_item_ids"] =~ Integer.to_string(entry1.id)
      refute json["unread_item_ids"] =~ Integer.to_string(entry2.id)
      assert json["unread_item_ids"] =~ Integer.to_string(entry3.id)
    end

    test "returns empty string when all read", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry = entry_fixture(feed)
      Content.mark_as_read(user, entry.id)

      conn = get(conn, ~p"/fever/?api&unread_item_ids", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["unread_item_ids"] == ""
    end
  end

  describe "GET /fever/?api&saved_item_ids" do
    test "returns comma-separated starred entry IDs", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)

      Content.toggle_starred(user, entry1.id)

      conn = get(conn, ~p"/fever/?api&saved_item_ids", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["auth"] == 1
      assert is_binary(json["saved_item_ids"])
      assert json["saved_item_ids"] =~ Integer.to_string(entry1.id)
      refute json["saved_item_ids"] =~ Integer.to_string(entry2.id)
    end

    test "returns empty string when nothing starred", %{conn: conn, api_key: api_key} do
      conn = get(conn, ~p"/fever/?api&saved_item_ids", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["saved_item_ids"] == ""
    end
  end

  describe "GET /fever/?api&favicons" do
    test "returns empty favicons array", %{conn: conn, api_key: api_key} do
      conn = get(conn, ~p"/fever/?api&favicons", api_key: api_key)

      assert json = json_response(conn, 200)
      assert json["auth"] == 1
      assert json["favicons"] == []
    end
  end

  describe "POST /fever/ - mark item as read" do
    test "marks an entry as read", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      conn =
        post(conn, ~p"/fever/?api", %{
          "api_key" => api_key,
          "mark" => "item",
          "as" => "read",
          "id" => entry.id
        })

      assert json = json_response(conn, 200)
      assert json["auth"] == 1

      # Verify entry is marked as read
      state = Content.get_entry_state(user, entry.id)
      assert state.read == true
    end
  end

  describe "POST /fever/ - mark item as saved" do
    test "stars an entry", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      conn =
        post(conn, ~p"/fever/?api", %{
          "api_key" => api_key,
          "mark" => "item",
          "as" => "saved",
          "id" => entry.id
        })

      assert json = json_response(conn, 200)
      assert json["auth"] == 1

      # Verify entry is starred
      state = Content.get_entry_state(user, entry.id)
      assert state.starred == true
    end
  end

  describe "POST /fever/ - mark item as unsaved" do
    test "unstars an entry", %{conn: conn, api_key: api_key, user: user} do
      feed = feed_fixture()
      subscription_fixture(user, feed)
      entry = entry_fixture(feed)

      # First star it
      Content.toggle_starred(user, entry.id)

      conn =
        post(conn, ~p"/fever/?api", %{
          "api_key" => api_key,
          "mark" => "item",
          "as" => "unsaved",
          "id" => entry.id
        })

      assert json = json_response(conn, 200)
      assert json["auth"] == 1

      # Verify entry is not starred
      state = Content.get_entry_state(user, entry.id)
      assert state.starred == false
    end
  end

  describe "POST /fever/ - mark feed as read" do
    test "marks all feed entries before timestamp as read", %{
      conn: conn,
      api_key: api_key,
      user: user
    } do
      feed = feed_fixture()
      subscription_fixture(user, feed)

      old_entry =
        entry_fixture(feed, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      new_entry = entry_fixture(feed, %{"published_at" => DateTime.utc_now()})

      # Mark entries before 1 day ago
      before_timestamp = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.to_unix()

      conn =
        post(conn, ~p"/fever/?api", %{
          "api_key" => api_key,
          "mark" => "feed",
          "as" => "read",
          "id" => feed.id,
          "before" => before_timestamp
        })

      assert json = json_response(conn, 200)
      assert json["auth"] == 1

      # Old entry should be marked read
      old_state = Content.get_entry_state(user, old_entry.id)
      assert old_state.read == true

      # New entry should not be marked read
      new_state = Content.get_entry_state(user, new_entry.id)
      assert is_nil(new_state) or new_state.read == false
    end
  end

  describe "POST /fever/ - mark group as read" do
    test "marks all folder entries before timestamp as read", %{
      conn: conn,
      api_key: api_key,
      user: user
    } do
      {:ok, folder} = Content.create_folder(user, %{name: "Tech", slug: "tech"})

      feed = feed_fixture()
      subscription_fixture(user, feed, %{"folder_id" => folder.id})

      old_entry =
        entry_fixture(feed, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      new_entry = entry_fixture(feed, %{"published_at" => DateTime.utc_now()})

      # Mark entries before 1 day ago
      before_timestamp = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.to_unix()

      conn =
        post(conn, ~p"/fever/?api", %{
          "api_key" => api_key,
          "mark" => "group",
          "as" => "read",
          "id" => folder.id,
          "before" => before_timestamp
        })

      assert json = json_response(conn, 200)
      assert json["auth"] == 1

      # Old entry should be marked read
      old_state = Content.get_entry_state(user, old_entry.id)
      assert old_state.read == true

      # New entry should not be marked read
      new_state = Content.get_entry_state(user, new_entry.id)
      assert is_nil(new_state) or new_state.read == false
    end
  end
end
