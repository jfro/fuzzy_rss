defmodule FuzzyRss.Api.GReader.IdConverter do
  @moduledoc """
  Converts between Google Reader's 3 ID formats and internal integer IDs.

  Item ID Formats:
  1. Long hex: "tag:google.com,2005:reader/item/000000000000001F"
  2. Short hex: "000000000000001F"
  3. Decimal: "31"

  Stream ID Formats:
  - Reading list: "user/-/state/com.google/reading-list"
  - Starred: "user/-/state/com.google/starred"
  - Read: "user/-/state/com.google/read"
  - Folder: "user/-/label/FolderName"
  - Feed: "feed/https://example.com/feed"
  """

  @long_item_prefix "tag:google.com,2005:reader/item/"

  @doc """
  Parses any of the 3 item ID formats to integer.

  Returns `{:ok, integer}` on success, `{:error, reason}` on failure.

  ## Examples

      iex> parse_item_id("tag:google.com,2005:reader/item/000000000000001F")
      {:ok, 31}

      iex> parse_item_id("000000000000001F")
      {:ok, 31}

      iex> parse_item_id("31")
      {:ok, 31}

      iex> parse_item_id("invalid")
      {:error, :invalid_format}

  """
  def parse_item_id(id) when is_binary(id) do
    cond do
      # Long hex format
      String.starts_with?(id, @long_item_prefix) ->
        id
        |> String.replace_prefix(@long_item_prefix, "")
        |> parse_hex()

      # Short hex format with leading zeros (16 chars padded) or contains A-F
      String.match?(id, ~r/^0+[0-9A-Fa-f]+$/) or
          String.match?(id, ~r/^[0-9A-Fa-f]*[A-Fa-f][0-9A-Fa-f]*$/) ->
        parse_hex(id)

      # Decimal format (all digits, no leading zeros)
      String.match?(id, ~r/^\d+$/) ->
        parse_decimal(id)

      true ->
        {:error, :invalid_format}
    end
  end

  def parse_item_id(_), do: {:error, :invalid_format}

  @doc """
  Parses stream ID to internal representation.

  Returns `{:ok, atom | tuple}` or `{:error, reason}`.

  ## Examples

      iex> parse_stream_id("user/-/state/com.google/reading-list")
      {:ok, :all}

      iex> parse_stream_id("user/-/state/com.google/starred")
      {:ok, :starred}

      iex> parse_stream_id("user/-/label/Tech")
      {:ok, {:folder, "Tech"}}

      iex> parse_stream_id("feed/https://example.com/feed")
      {:ok, {:feed, "https://example.com/feed"}}

  """
  def parse_stream_id(stream_id) when is_binary(stream_id) do
    cond do
      # Reading list (all items)
      String.contains?(stream_id, "/state/com.google/reading-list") ->
        {:ok, :all}

      # Starred items
      String.contains?(stream_id, "/state/com.google/starred") ->
        {:ok, :starred}

      # Read state
      String.contains?(stream_id, "/state/com.google/read") ->
        {:ok, :read}

      # Folder/Label
      String.match?(stream_id, ~r|^user/[^/]+/label/(.+)$|) ->
        [_, label_name] = Regex.run(~r|^user/[^/]+/label/(.+)$|, stream_id)
        {:ok, {:folder, label_name}}

      # Feed URL
      String.starts_with?(stream_id, "feed/") ->
        feed_url = String.replace_prefix(stream_id, "feed/", "")
        {:ok, {:feed, feed_url}}

      true ->
        {:error, :invalid_stream_id}
    end
  end

  def parse_stream_id(_), do: {:error, :invalid_stream_id}

  @doc """
  Converts integer ID to long hex format.

  ## Examples

      iex> to_long_item_id(31)
      "tag:google.com,2005:reader/item/000000000000001F"

      iex> to_long_item_id(1234567890)
      "tag:google.com,2005:reader/item/00000000499602D2"

  """
  def to_long_item_id(int_id) when is_integer(int_id) do
    hex = Integer.to_string(int_id, 16) |> String.upcase()
    # Pad to 16 characters
    padded_hex = String.pad_leading(hex, 16, "0")
    @long_item_prefix <> padded_hex
  end

  @doc """
  Converts internal representation to stream ID string.

  ## Examples

      iex> to_stream_id(:all, 123)
      "user/123/state/com.google/reading-list"

      iex> to_stream_id(:starred, 456)
      "user/456/state/com.google/starred"

      iex> to_stream_id({:folder, "Tech"}, 123)
      "user/123/label/Tech"

      iex> to_stream_id({:feed, "https://example.com/feed"}, nil)
      "feed/https://example.com/feed"

  """
  def to_stream_id(:all, user_id), do: "user/#{user_id}/state/com.google/reading-list"
  def to_stream_id(:starred, user_id), do: "user/#{user_id}/state/com.google/starred"
  def to_stream_id(:read, user_id), do: "user/#{user_id}/state/com.google/read"
  def to_stream_id({:folder, name}, user_id), do: "user/#{user_id}/label/#{name}"
  def to_stream_id({:feed, url}, _user_id), do: "feed/#{url}"

  # Private helpers

  defp parse_hex(hex_string) do
    case Integer.parse(hex_string, 16) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_hex}
    end
  end

  defp parse_decimal(decimal_string) do
    case Integer.parse(decimal_string) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_decimal}
    end
  end
end
