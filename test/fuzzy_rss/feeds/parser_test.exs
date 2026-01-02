defmodule FuzzyRss.Feeds.ParserTest do
  use FuzzyRss.DataCase, async: true
  alias FuzzyRss.Feeds.Parser

  @rss_feed """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0">
    <channel>
      <title>Test Feed</title>
      <link>https://example.com</link>
      <description>A test RSS feed</description>
      <image>
        <url>https://example.com/favicon.png</url>
        <title>Test Feed</title>
        <link>https://example.com</link>
      </image>
      <item>
        <title>Test Item</title>
        <link>https://example.com/item</link>
        <guid>https://example.com/item</guid>
        <pubDate>Fri, 02 Jan 2026 00:00:00 +0000</pubDate>
        <description>Test description</description>
      </item>
    </channel>
  </rss>
  """

  @atom_feed """
  <?xml version="1.0" encoding="utf-8"?>
  <feed xmlns="http://www.w3.org/2005/Atom">
    <title>Test Atom Feed</title>
    <link href="https://example.com"/>
    <icon>https://example.com/atom-icon.png</icon>
    <entry>
      <title>Test Atom Item</title>
      <link href="https://example.com/atom-item"/>
      <id>https://example.com/atom-item</id>
      <updated>2026-01-02T00:00:00Z</updated>
      <summary>Test atom description</summary>
    </entry>
  </feed>
  """

  describe "parse/1" do
    test "extracts favicon from RSS feed" do
      assert {:ok, %{feed: feed}} = Parser.parse(@rss_feed)
      assert feed.favicon_url == "https://example.com/favicon.png"
    end

    test "extracts favicon from Atom feed" do
      assert {:ok, %{feed: feed}} = Parser.parse(@atom_feed)
      assert feed.favicon_url == "https://example.com/atom-icon.png"
    end
  end
end
