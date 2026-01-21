defmodule FuzzyRss.Api.FeverTest do
  use FuzzyRss.DataCase

  import FuzzyRss.AccountsFixtures
  import FuzzyRss.ContentFixtures

  alias FuzzyRss.Api.Fever
  alias FuzzyRss.Content

  describe "format_groups/1" do
    test "formats folders as Fever groups" do
      user = user_fixture()
      {:ok, folder1} = Content.create_folder(user, %{name: "Tech", slug: "tech"})
      {:ok, folder2} = Content.create_folder(user, %{name: "News", slug: "news"})

      folders = [folder1, folder2]
      result = Fever.format_groups(folders)

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id == folder1.id && &1.title == "Tech"))
      assert Enum.any?(result, &(&1.id == folder2.id && &1.title == "News"))
    end

    test "returns empty list for no folders" do
      result = Fever.format_groups([])
      assert result == []
    end
  end

  describe "format_feeds/2" do
    test "formats feeds with subscription info" do
      user = user_fixture()
      feed1 = feed_fixture(%{"title" => "Feed 1", "site_url" => "https://example.com"})
      feed2 = feed_fixture(%{"title" => "Feed 2", "site_url" => "https://example2.com"})

      subscription_fixture(user, feed1)
      subscription_fixture(user, feed2)

      subscriptions = Content.list_subscriptions(user)
      result = Fever.format_feeds(subscriptions)

      assert length(result) == 2

      first_feed = Enum.find(result, &(&1.id == feed1.id))
      assert first_feed.title == "Feed 1"
      assert first_feed.url == feed1.url
      assert first_feed.site_url == "https://example.com"
      assert first_feed.is_spark == 0
      assert is_integer(first_feed.last_updated_on_time)
    end

    test "sets favicon_id to feed id" do
      user = user_fixture()
      feed = feed_fixture()
      subscription_fixture(user, feed)

      subscriptions = Content.list_subscriptions(user)
      result = Fever.format_feeds(subscriptions)

      assert hd(result).favicon_id == feed.id
    end

    test "returns empty list for no subscriptions" do
      result = Fever.format_feeds([])
      assert result == []
    end
  end

  describe "format_items/2" do
    test "formats entries with read/starred state" do
      user = user_fixture()
      feed = feed_fixture()
      subscription_fixture(user, feed)

      entry1 =
        entry_fixture(feed, %{
          "title" => "Entry 1",
          "url" => "https://example.com/1",
          "content" => "<p>Content 1</p>",
          "author" => "Author 1"
        })

      entry2 =
        entry_fixture(feed, %{
          "title" => "Entry 2",
          "url" => "https://example.com/2"
        })

      # Mark entry1 as read and starred
      Content.mark_as_read(user, entry1.id)
      Content.toggle_starred(user, entry1.id)

      entries = Content.list_fever_items(user, [])
      result = Fever.format_items(entries, user)

      assert length(result) == 2

      item1 = Enum.find(result, &(&1.id == entry1.id))
      assert item1.feed_id == feed.id
      assert item1.title == "Entry 1"
      assert item1.author == "Author 1"
      assert item1.html == "<p>Content 1</p>"
      assert item1.url == "https://example.com/1"
      assert item1.is_read == 1
      assert item1.is_saved == 1
      assert is_integer(item1.created_on_time)

      item2 = Enum.find(result, &(&1.id == entry2.id))
      assert item2.is_read == 0
      assert item2.is_saved == 0
    end

    test "handles entries with no author" do
      user = user_fixture()
      feed = feed_fixture()
      subscription_fixture(user, feed)

      _entry = entry_fixture(feed, %{"author" => nil})
      entries = Content.list_fever_items(user, [])
      result = Fever.format_items(entries, user)

      assert hd(result).author == ""
    end

    test "returns empty list for no entries" do
      user = user_fixture()
      result = Fever.format_items([], user)
      assert result == []
    end
  end

  describe "format_feeds_groups/1" do
    test "creates feed-to-folder mappings" do
      user = user_fixture()
      {:ok, folder1} = Content.create_folder(user, %{name: "Tech", slug: "tech"})
      {:ok, folder2} = Content.create_folder(user, %{name: "News", slug: "news"})

      feed1 = feed_fixture()
      feed2 = feed_fixture()
      feed3 = feed_fixture()

      subscription_fixture(user, feed1, %{"folder_id" => folder1.id})
      subscription_fixture(user, feed2, %{"folder_id" => folder1.id})
      subscription_fixture(user, feed3, %{"folder_id" => folder2.id})

      subscriptions = Content.list_subscriptions(user)
      result = Fever.format_feeds_groups(subscriptions)

      assert length(result) == 2

      group1 = Enum.find(result, &(&1.group_id == folder1.id))
      assert group1.feed_ids =~ Integer.to_string(feed1.id)
      assert group1.feed_ids =~ Integer.to_string(feed2.id)

      group2 = Enum.find(result, &(&1.group_id == folder2.id))
      assert group2.feed_ids == Integer.to_string(feed3.id)
    end

    test "excludes subscriptions without folder" do
      user = user_fixture()
      {:ok, folder} = Content.create_folder(user, %{name: "Tech", slug: "tech"})

      feed1 = feed_fixture()
      feed2 = feed_fixture()

      subscription_fixture(user, feed1, %{"folder_id" => folder.id})
      # No folder
      subscription_fixture(user, feed2)

      subscriptions = Content.list_subscriptions(user)
      result = Fever.format_feeds_groups(subscriptions)

      assert length(result) == 1
      assert hd(result).group_id == folder.id
    end

    test "returns empty list when no folders exist" do
      user = user_fixture()
      feed = feed_fixture()
      subscription_fixture(user, feed)

      subscriptions = Content.list_subscriptions(user)
      result = Fever.format_feeds_groups(subscriptions)

      assert result == []
    end
  end
end
