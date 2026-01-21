defmodule FuzzyRss.Api.GReaderTest do
  use FuzzyRss.DataCase

  import FuzzyRss.AccountsFixtures
  import FuzzyRss.ContentFixtures

  alias FuzzyRss.Api.GReader
  alias FuzzyRss.Content

  describe "format_subscription/3" do
    test "formats subscription with folder" do
      user = user_fixture()
      feed = feed_fixture()
      folder = folder_fixture(user, %{name: "Tech"})
      subscription = subscription_fixture(user, feed, %{folder_id: folder.id})
      subscription = Content.get_subscription!(subscription.id) |> repo().preload([:feed, :folder])

      result = GReader.format_subscription(subscription, subscription.folder, user.id)

      assert result.id == "feed/#{feed.url}"
      assert result.title == feed.title
      assert result.url == feed.url
      assert result.htmlUrl == feed.site_url || feed.url
      assert [category] = result.categories
      assert category.id == "user/#{user.id}/label/Tech"
      assert category.label == "Tech"
    end

    test "formats subscription without folder" do
      user = user_fixture()
      feed = feed_fixture()
      sub = subscription_fixture(user, feed)
      subscription = Content.get_subscription!(sub.id) |> repo().preload([:feed, :folder])

      result = GReader.format_subscription(subscription, nil, user.id)

      assert result.id == "feed/#{feed.url}"
      assert result.categories == []
    end

    test "includes feed metadata" do
      user = user_fixture()
      feed = feed_fixture(%{title: "My Blog", site_url: "https://example.com"})
      sub = subscription_fixture(user, feed)
      subscription = Content.get_subscription!(sub.id) |> repo().preload([:feed, :folder])

      result = GReader.format_subscription(subscription, nil, user.id)

      assert result.title == "My Blog"
      assert result.htmlUrl == "https://example.com"
      assert result.iconUrl == ""
      assert is_integer(result.firstitemmsec)
    end
  end

  describe "format_item/2" do
    test "formats entry with read state" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)
      entry = entry_fixture(feed)
      Content.mark_as_read(user, entry.id)

      entry = Content.get_entry!(entry.id) |> repo().preload([:feed, :user_entry_states])

      result = GReader.format_item(entry, user)

      assert String.starts_with?(result.id, "tag:google.com,2005:reader/item/")
      assert result.title == entry.title
      assert result.author == entry.author
      assert result.published == DateTime.to_unix(entry.published_at || entry.inserted_at)

      # Check state tags
      assert "user/#{user.id}/state/com.google/reading-list" in result.categories
      assert "user/#{user.id}/state/com.google/read" in result.categories
      refute "user/#{user.id}/state/com.google/starred" in result.categories
    end

    test "formats entry with starred state" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)
      entry = entry_fixture(feed)
      Content.toggle_starred(user, entry.id)

      entry = Content.get_entry!(entry.id) |> repo().preload([:feed, :user_entry_states])

      result = GReader.format_item(entry, user)

      assert "user/#{user.id}/state/com.google/starred" in result.categories
    end

    test "formats entry with both read and starred" do
      user = user_fixture()
      feed = feed_fixture()
      _subscription = subscription_fixture(user, feed)
      entry = entry_fixture(feed)
      Content.mark_as_read(user, entry.id)
      Content.toggle_starred(user, entry.id)

      entry = Content.get_entry!(entry.id) |> repo().preload([:feed, :user_entry_states])

      result = GReader.format_item(entry, user)

      assert "user/#{user.id}/state/com.google/read" in result.categories
      assert "user/#{user.id}/state/com.google/starred" in result.categories
    end

    test "includes all required fields" do
      user = user_fixture()
      feed = feed_fixture(%{site_url: "https://example.com"})
      _subscription = subscription_fixture(user, feed)
      entry = entry_fixture(feed, %{
        title: "Test Entry",
        author: "John Doe",
        url: "https://example.com/entry1",
        content: "Entry content here",
        summary: "Entry summary"
      })

      entry = Content.get_entry!(entry.id) |> repo().preload([:feed, :user_entry_states])

      result = GReader.format_item(entry, user)

      assert is_binary(result.id)
      assert is_integer(result.crawlTimeMsec)
      assert is_integer(result.timestampUsec)
      assert result.title == "Test Entry"
      assert result.author == "John Doe"
      assert result.summary.content =~ "Entry content"
      assert result.summary.direction == "ltr"
      assert [canonical] = result.canonical
      assert canonical.href == "https://example.com/entry1"
      assert [alternate] = result.alternate
      assert alternate.href == "https://example.com/entry1"
      assert result.origin.streamId == "feed/#{feed.url}"
      assert result.origin.title == feed.title
    end
  end

  describe "format_unread_count/3" do
    test "formats unread count structure" do
      result = GReader.format_unread_count("feed/https://example.com", 5, 1234567890)

      assert result.id == "feed/https://example.com"
      assert result.count == 5
      assert result.newestItemTimestampUsec == 1234567890
    end
  end

  describe "format_tag_list/2" do
    test "returns default state tags" do
      user = user_fixture()
      folders = []

      result = GReader.format_tag_list(folders, user.id)

      assert length(result) == 3

      reading_list = Enum.find(result, &(&1.id == "user/#{user.id}/state/com.google/reading-list"))
      assert reading_list.sortid == "01"

      starred = Enum.find(result, &(&1.id == "user/#{user.id}/state/com.google/starred"))
      assert starred.sortid == "02"

      read = Enum.find(result, &(&1.id == "user/#{user.id}/state/com.google/read"))
      assert read.sortid == "03"
    end

    test "includes user folders as label tags" do
      user = user_fixture()
      folder1 = folder_fixture(user, %{name: "Tech"})
      folder2 = folder_fixture(user, %{name: "News"})
      folders = [folder1, folder2]

      result = GReader.format_tag_list(folders, user.id)

      assert length(result) == 5

      tech_tag = Enum.find(result, &(&1.id == "user/#{user.id}/label/Tech"))
      assert tech_tag
      assert String.starts_with?(tech_tag.sortid, "A")

      news_tag = Enum.find(result, &(&1.id == "user/#{user.id}/label/News"))
      assert news_tag
    end
  end
end
