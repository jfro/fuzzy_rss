defmodule FuzzyRss.ContentTest do
  use FuzzyRss.DataCase

  import FuzzyRss.AccountsFixtures
  import FuzzyRss.ContentFixtures

  alias FuzzyRss.Content

  describe "list_fever_items/2" do
    setup do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)

      entries =
        for i <- 1..5 do
          entry_fixture(feed, %{
            "title" => "Entry #{i}",
            "published_at" => DateTime.add(DateTime.utc_now(), -i, :hour)
          })
        end

      %{user: user, feed: feed, entries: entries}
    end

    test "returns entries with since_id pagination", %{user: user, entries: entries} do
      [first, _second | _] = Enum.sort_by(entries, & &1.id)

      result = Content.list_fever_items(user, since_id: first.id)

      assert length(result) >= 1
      refute Enum.any?(result, &(&1.id == first.id))
    end

    test "returns entries with max_id pagination", %{user: user, entries: entries} do
      [_first, second, _third | _] = Enum.sort_by(entries, & &1.id)

      result = Content.list_fever_items(user, max_id: second.id)

      assert Enum.all?(result, &(&1.id <= second.id))
    end

    test "returns entries by specific IDs", %{user: user, entries: entries} do
      [first, _second, third | _] = Enum.sort_by(entries, & &1.id)

      result = Content.list_fever_items(user, with_ids: "#{first.id},#{third.id}")

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id == first.id))
      assert Enum.any?(result, &(&1.id == third.id))
    end

    test "limits results to 50 by default", %{user: user, feed: feed} do
      # Create 60 entries
      for i <- 6..65 do
        entry_fixture(feed, %{"title" => "Entry #{i}"})
      end

      result = Content.list_fever_items(user, [])

      assert length(result) <= 50
    end
  end

  describe "get_unread_item_ids/1" do
    test "returns comma-separated unread entry IDs" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)

      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)
      entry3 = entry_fixture(feed)

      Content.mark_as_read(user, entry2.id)

      result = Content.get_unread_item_ids(user)

      assert result =~ Integer.to_string(entry1.id)
      refute result =~ Integer.to_string(entry2.id)
      assert result =~ Integer.to_string(entry3.id)
    end

    test "returns empty string when all entries are read" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)

      entry = entry_fixture(feed)
      Content.mark_as_read(user, entry.id)

      result = Content.get_unread_item_ids(user)

      assert result == ""
    end
  end

  describe "get_saved_item_ids/1" do
    test "returns comma-separated starred entry IDs" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)

      entry1 = entry_fixture(feed)
      entry2 = entry_fixture(feed)

      Content.toggle_starred(user, entry1.id)

      result = Content.get_saved_item_ids(user)

      assert result =~ Integer.to_string(entry1.id)
      refute result =~ Integer.to_string(entry2.id)
    end

    test "returns empty string when no entries are starred" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)

      entry_fixture(feed)

      result = Content.get_saved_item_ids(user)

      assert result == ""
    end
  end

  describe "mark_feed_read_before/3" do
    test "marks all feed entries before timestamp as read" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)

      old_entry =
        entry_fixture(feed, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      new_entry = entry_fixture(feed, %{"published_at" => DateTime.utc_now()})

      before_timestamp = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.to_unix()

      {:ok, _count} = Content.mark_feed_read_before(user, feed.id, before_timestamp)

      old_state = Content.get_entry_state(user, old_entry.id)
      new_state = Content.get_entry_state(user, new_entry.id)

      assert old_state.read == true
      assert is_nil(new_state) or new_state.read == false
    end

    test "does not mark entries from other feeds" do
      user = user_fixture()
      feed1 = feed_fixture()
      feed2 = feed_fixture()
      _subscription1 = subscription_fixture(user, feed1)
      _subscription2 = subscription_fixture(user, feed2)

      entry1 =
        entry_fixture(feed1, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      entry2 =
        entry_fixture(feed2, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      before_timestamp = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.to_unix()

      {:ok, _count} = Content.mark_feed_read_before(user, feed1.id, before_timestamp)

      state1 = Content.get_entry_state(user, entry1.id)
      state2 = Content.get_entry_state(user, entry2.id)

      assert state1.read == true
      assert is_nil(state2) or state2.read == false
    end
  end

  describe "mark_folder_read_before/3" do
    test "marks all folder entries before timestamp as read" do
      user = user_fixture()
      {:ok, folder} = Content.create_folder(user, %{name: "Test", slug: "test"})

      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed, %{"folder_id" => folder.id})

      old_entry =
        entry_fixture(feed, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      new_entry = entry_fixture(feed, %{"published_at" => DateTime.utc_now()})

      before_timestamp = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.to_unix()

      {:ok, _count} = Content.mark_folder_read_before(user, folder.id, before_timestamp)

      old_state = Content.get_entry_state(user, old_entry.id)
      new_state = Content.get_entry_state(user, new_entry.id)

      assert old_state.read == true
      assert is_nil(new_state) or new_state.read == false
    end

    test "only marks entries in the specified folder" do
      user = user_fixture()
      {:ok, folder1} = Content.create_folder(user, %{name: "Folder 1", slug: "folder-1"})
      {:ok, folder2} = Content.create_folder(user, %{name: "Folder 2", slug: "folder-2"})

      feed1 = feed_fixture()
      feed2 = feed_fixture()
      _subscription1 = subscription_fixture(user, feed1, %{"folder_id" => folder1.id})
      _subscription2 = subscription_fixture(user, feed2, %{"folder_id" => folder2.id})

      entry1 =
        entry_fixture(feed1, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      entry2 =
        entry_fixture(feed2, %{"published_at" => DateTime.add(DateTime.utc_now(), -2, :day)})

      before_timestamp = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.to_unix()

      {:ok, _count} = Content.mark_folder_read_before(user, folder1.id, before_timestamp)

      state1 = Content.get_entry_state(user, entry1.id)
      state2 = Content.get_entry_state(user, entry2.id)

      assert state1.read == true
      assert is_nil(state2) or state2.read == false
    end
  end
end
