defmodule FuzzyRss.Api.GReader.IdConverterTest do
  use FuzzyRss.DataCase

  alias FuzzyRss.Api.GReader.IdConverter

  describe "parse_item_id/1" do
    test "parses long hex format" do
      assert {:ok, 31} = IdConverter.parse_item_id("tag:google.com,2005:reader/item/000000000000001F")
    end

    test "parses short hex format" do
      assert {:ok, 31} = IdConverter.parse_item_id("000000000000001F")
    end

    test "parses decimal format" do
      assert {:ok, 31} = IdConverter.parse_item_id("31")
    end

    test "parses large numbers" do
      assert {:ok, 1234567890} = IdConverter.parse_item_id("499602D2")
      assert {:ok, 1234567890} = IdConverter.parse_item_id("1234567890")
    end

    test "returns error for invalid format" do
      assert {:error, _} = IdConverter.parse_item_id("invalid")
      assert {:error, _} = IdConverter.parse_item_id("")
      assert {:error, _} = IdConverter.parse_item_id(nil)
    end
  end

  describe "parse_stream_id/1" do
    test "parses reading-list stream" do
      assert {:ok, :all} = IdConverter.parse_stream_id("user/-/state/com.google/reading-list")
      assert {:ok, :all} = IdConverter.parse_stream_id("user/123/state/com.google/reading-list")
    end

    test "parses starred stream" do
      assert {:ok, :starred} = IdConverter.parse_stream_id("user/-/state/com.google/starred")
      assert {:ok, :starred} = IdConverter.parse_stream_id("user/456/state/com.google/starred")
    end

    test "parses read state stream" do
      assert {:ok, :read} = IdConverter.parse_stream_id("user/-/state/com.google/read")
      assert {:ok, :read} = IdConverter.parse_stream_id("user/789/state/com.google/read")
    end

    test "parses folder/label stream" do
      assert {:ok, {:folder, "Tech"}} = IdConverter.parse_stream_id("user/-/label/Tech")
      assert {:ok, {:folder, "News"}} = IdConverter.parse_stream_id("user/123/label/News")
      assert {:ok, {:folder, "My Folder"}} = IdConverter.parse_stream_id("user/-/label/My Folder")
    end

    test "parses feed stream" do
      assert {:ok, {:feed, "https://example.com/feed"}} =
        IdConverter.parse_stream_id("feed/https://example.com/feed")
      assert {:ok, {:feed, "http://test.com/rss"}} =
        IdConverter.parse_stream_id("feed/http://test.com/rss")
    end

    test "returns error for invalid stream ID" do
      assert {:error, _} = IdConverter.parse_stream_id("invalid")
      assert {:error, _} = IdConverter.parse_stream_id("")
      assert {:error, _} = IdConverter.parse_stream_id(nil)
    end
  end

  describe "to_long_item_id/1" do
    test "converts integer to long hex format" do
      assert "tag:google.com,2005:reader/item/000000000000001F" =
        IdConverter.to_long_item_id(31)
    end

    test "converts large integer to long hex format" do
      assert "tag:google.com,2005:reader/item/00000000499602D2" =
        IdConverter.to_long_item_id(1234567890)
    end

    test "pads with zeros to 16 characters" do
      result = IdConverter.to_long_item_id(1)
      assert String.ends_with?(result, "/0000000000000001")
    end
  end

  describe "to_stream_id/2" do
    test "converts :all to reading-list stream" do
      assert "user/123/state/com.google/reading-list" =
        IdConverter.to_stream_id(:all, 123)
    end

    test "converts :starred to starred stream" do
      assert "user/456/state/com.google/starred" =
        IdConverter.to_stream_id(:starred, 456)
    end

    test "converts :read to read stream" do
      assert "user/789/state/com.google/read" =
        IdConverter.to_stream_id(:read, 789)
    end

    test "converts {:folder, name} to label stream" do
      assert "user/123/label/Tech" =
        IdConverter.to_stream_id({:folder, "Tech"}, 123)
      assert "user/456/label/My Folder" =
        IdConverter.to_stream_id({:folder, "My Folder"}, 456)
    end

    test "converts {:feed, url} to feed stream" do
      assert "feed/https://example.com/feed" =
        IdConverter.to_stream_id({:feed, "https://example.com/feed"}, nil)
      assert "feed/http://test.com/rss" =
        IdConverter.to_stream_id({:feed, "http://test.com/rss"}, 123)
    end
  end
end
