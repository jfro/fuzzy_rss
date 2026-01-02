defmodule FuzzyRss.Feeds.Parser do
  @moduledoc "Parse RSS/Atom feeds into normalized entries"

  require Logger

  def parse(xml_string) do
    Logger.info("Parser: Parsing XML (#{byte_size(xml_string)} bytes)")

    case FastRSS.parse(xml_string) do
      {:ok, feed_data} ->
        Logger.info("Parser: FastRSS returned keys: #{inspect(Map.keys(feed_data))}")
        Logger.info("Parser: FastRSS structure: #{inspect(feed_data, limit: 2)}")

        try do
          normalized = normalize_feed(feed_data)

          Logger.info(
            "Parser: Successfully parsed feed with #{length(normalized.entries)} entries"
          )

          {:ok, normalized}
        rescue
          e ->
            Logger.error("Parser: Error normalizing feed: #{Exception.message(e)}")
            Logger.debug("Parser: Feed data structure: #{inspect(feed_data)}")
            {:error, Exception.message(e)}
        end

      {:error, reason} ->
        Logger.info("Parser: FastRSS failed (#{inspect(reason)}), trying Atom parser")
        parse_atom(xml_string)
    end
  end

  defp parse_atom(xml_string) do
    try do
      # Write to temp file and parse from file - xmerl handles file encoding better
      temp_file = System.tmp_dir!() <> "/feed_#{System.monotonic_time()}.xml"
      File.write!(temp_file, xml_string)

      opts = [
        {:quiet, true}
      ]

      {doc, _} = :xmerl_scan.file(String.to_charlist(temp_file), opts)
      File.rm(temp_file)

      normalized = extract_atom_feed(doc)

      Logger.info(
        "Parser: Successfully parsed Atom feed with #{length(normalized.entries)} entries"
      )

      {:ok, normalized}
    rescue
      e ->
        Logger.error("Parser: Failed to parse Atom feed: #{Exception.message(e)}")
        Logger.debug("Parser: Error details: #{Exception.format(:error, e)}")
        {:error, "Unable to parse feed"}
    catch
      :exit, reason ->
        Logger.error("Parser: XML parse error: #{inspect(reason)}")
        {:error, "Invalid XML"}
    end
  end

  defp normalize_feed(feed_data) do
    items = Map.get(feed_data, "items", [])

    %{
      feed: %{
        title: Map.get(feed_data, "title") || "Untitled",
        description: Map.get(feed_data, "description"),
        site_url: Map.get(feed_data, "link"),
        feed_type: "rss"
      },
      entries: Enum.map(items, &normalize_entry/1)
    }
  end

  defp normalize_entry(item) do
    guid =
      case Map.get(item, "guid") do
        %{"value" => value} -> value
        value when is_binary(value) -> value
        _ -> Map.get(item, "link") || generate_guid(item)
      end

    %{
      guid: guid,
      url: Map.get(item, "link"),
      title: Map.get(item, "title") || "Untitled",
      author: Map.get(item, "author"),
      summary: Map.get(item, "description"),
      content: Map.get(item, "content") || Map.get(item, "description"),
      published_at: parse_date(Map.get(item, "pub_date")),
      image_url: extract_image(item),
      categories: normalize_categories(Map.get(item, "categories", []))
    }
  end

  defp normalize_categories(nil), do: []
  defp normalize_categories([]), do: []

  defp normalize_categories(categories) when is_list(categories) do
    categories
    |> Enum.map(fn
      cat when is_binary(cat) -> cat
      %{"value" => value} when is_binary(value) -> value
      %{"_text" => value} when is_binary(value) -> value
      cat when is_map(cat) -> Map.get(cat, "value") || Map.get(cat, "_text") || ""
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_categories(categories) when is_binary(categories), do: [categories]
  defp normalize_categories(_), do: []

  defp generate_guid(item) do
    # Fallback GUID generation using title and pub_date
    title = Map.get(item, "title", "")
    pub_date = Map.get(item, "pub_date", "")
    :crypto.hash(:md5, "#{title}#{pub_date}") |> Base.encode16(case: :lower)
  end

  defp parse_date(nil), do: DateTime.utc_now()

  defp parse_date(date_string) when is_binary(date_string) do
    date_string = String.trim(date_string)

    # Try ISO8601 first
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} ->
        dt

      _ ->
        # Try RFC2822 format (common in RSS feeds)
        case parse_rfc2822_with_timex(date_string) do
          {:ok, dt} -> dt
          :error -> DateTime.utc_now()
        end
    end
  end

  defp parse_date(%DateTime{} = dt), do: dt
  defp parse_date(_), do: DateTime.utc_now()

  defp parse_rfc2822_with_timex(date_string) do
    # RFC2822 format: "Thu, 25 Jul 2024 23:59:20 +0100"
    case Timex.parse(date_string, "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}") do
      {:ok, dt} -> {:ok, dt}
      :error -> try_alternate_rfc2822_formats(date_string)
    end
  end

  defp try_alternate_rfc2822_formats(date_string) do
    # Try without day of week: "25 Jul 2024 23:59:20 +0100"
    case Timex.parse(date_string, "{D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}") do
      {:ok, dt} -> {:ok, dt}
      :error -> try_rfc2822_with_tz_name(date_string)
    end
  end

  defp try_rfc2822_with_tz_name(date_string) do
    # Try with timezone name: "Thu, 25 Jul 2024 23:59:20 GMT"
    case Timex.parse(date_string, "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} {Zname}") do
      {:ok, dt} -> {:ok, dt}
      :error -> :error
    end
  end

  defp extract_atom_feed(doc) when is_tuple(doc) and elem(doc, 0) == :xmlElement do
    # xmerl returns xmlElement as a 12-tuple
    # Content is at position 8
    content = elem(doc, 8)
    extract_atom_from_content(content)
  end

  defp extract_atom_feed(doc) do
    Logger.error("Parser: Unexpected xmerl structure: #{inspect(doc, limit: 3)}")
    %{feed: %{title: "Untitled", description: nil, site_url: nil, feed_type: "atom"}, entries: []}
  end

  defp extract_atom_from_content(content) when is_list(content) do
    # Filter to only xmlElement nodes (skip text nodes, namespaces, etc)
    elements =
      Enum.filter(content, fn
        {:xmlElement, _, _, _, _, _, _, _, _, _, _, _} -> true
        _ -> false
      end)

    feed_title = extract_text_from_element_list(elements, :title) || "Untitled"
    feed_description = extract_text_from_element_list(elements, :subtitle)
    feed_link = extract_link_from_element_list(elements, :alternate)

    # Extract entries
    entries =
      elements
      |> Enum.filter(fn
        {:xmlElement, name, _, _, _, _, _, _, _, _, _, _} -> name == :entry
        _ -> false
      end)
      |> Enum.map(&extract_atom_entry/1)
      |> Enum.reject(&is_nil/1)

    %{
      feed: %{
        title: feed_title,
        description: feed_description,
        site_url: feed_link,
        feed_type: "atom"
      },
      entries: entries
    }
  end

  defp extract_atom_from_content(_) do
    %{feed: %{title: "Untitled", description: nil, site_url: nil, feed_type: "atom"}, entries: []}
  end

  defp extract_atom_entry(element) when is_tuple(element) do
    # Content is at position 8
    content = elem(element, 8)

    %{
      guid:
        extract_text_from_element_list(content, :id) ||
          extract_link_from_element_list(content, :alternate),
      url: extract_link_from_element_list(content, :alternate),
      title: extract_text_from_element_list(content, :title) || "Untitled",
      author: extract_author_from_content(content),
      summary: extract_text_from_element_list(content, :summary),
      content:
        extract_text_from_element_list(content, :content) ||
          extract_text_from_element_list(content, :summary),
      published_at: parse_iso8601_date(extract_text_from_element_list(content, :published)),
      image_url: nil,
      categories: extract_categories_from_content(content)
    }
  end

  defp extract_atom_entry(_), do: nil

  # Helper to extract text from an element list by tag
  defp extract_text_from_element_list(children, tag) when is_list(children) do
    Enum.find_value(children, fn item ->
      case item do
        {:xmlElement, ^tag, _, _, _, _, _, _, _, _, _, _} ->
          # Content is at position 8, not 4
          content = elem(item, 8)
          extract_text_from_content(content)

        _ ->
          nil
      end
    end)
  end

  defp extract_text_from_element_list(_, _), do: nil

  # Extract text from xmerl content
  defp extract_text_from_content(content) when is_list(content) do
    Enum.find_value(content, fn
      # xmlText is a 6-tuple: {:xmlText, parents, pos, language, text, type}
      {:xmlText, _parents, _pos, _language, text, _type} when is_list(text) ->
        text |> List.to_string()

      {:xmlText, _parents, _pos, _language, text, _type} when is_binary(text) ->
        text

      # Also handle old format if needed (5-tuple without type)
      {:xmlText, _parents, _pos, _language, text} when is_list(text) ->
        text |> List.to_string()

      {:xmlText, _parents, _pos, _language, text} when is_binary(text) ->
        text

      text when is_binary(text) ->
        text

      _ ->
        nil
    end)
  end

  defp extract_text_from_content(text) when is_binary(text), do: text
  defp extract_text_from_content(text) when is_list(text), do: List.to_string(text)
  defp extract_text_from_content(_), do: nil

  # Extract link from element list by rel attribute
  defp extract_link_from_element_list(children, _rel_type) when not is_list(children), do: nil

  defp extract_link_from_element_list(children, rel_type) when is_list(children) do
    # Convert atom rel_type to string for comparison
    rel_type_str = if is_atom(rel_type), do: Atom.to_string(rel_type), else: rel_type

    link =
      Enum.find_value(children, fn item ->
        case item do
          {:xmlElement, :link, _, _, _, _, _, _, _, _, _, _} ->
            # attrs are at position 7
            attrs = elem(item, 7)

            has_rel =
              case Enum.find(attrs, fn attr -> get_attr_name(attr) == :rel end) do
                attr when attr != nil -> get_attr_value(attr) == rel_type_str
                _ -> false
              end

            if has_rel do
              Enum.find_value(attrs, fn attr ->
                if get_attr_name(attr) == :href do
                  get_attr_value(attr)
                else
                  nil
                end
              end)
            else
              nil
            end

          _ ->
            nil
        end
      end)

    case link do
      href when is_list(href) -> href |> List.to_string()
      href when is_binary(href) -> href
      _ -> nil
    end
  end

  defp get_attr_name({:xmlAttribute, name, _, _, _, _, _, _, _, _}), do: name
  defp get_attr_name(_), do: nil

  defp get_attr_value({:xmlAttribute, _, _, _, _, _, _, _, value, _}) when is_list(value) do
    value |> List.to_string()
  end

  defp get_attr_value({:xmlAttribute, _, _, _, _, _, _, _, value, _}) when is_binary(value) do
    value
  end

  defp get_attr_value(_), do: nil

  # Extract author name from content
  defp extract_author_from_content(children) when is_list(children) do
    Enum.find_value(children, fn
      {:xmlElement, :author, _, _, author_content, _, _, _, _, _, _, _} ->
        extract_text_from_element_list(author_content, :name)

      _ ->
        nil
    end)
  end

  defp extract_author_from_content(_), do: nil

  # Extract categories from content
  defp extract_categories_from_content(children) when is_list(children) do
    children
    |> Enum.filter(fn
      {:xmlElement, :category, _, _, _, _, _, _, _, _, _, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:xmlElement, :category, _, _, _content, attrs, _, _, _, _, _, _} ->
      Enum.find_value(attrs, fn attr ->
        if get_attr_name(attr) == :term do
          get_attr_value(attr)
        else
          nil
        end
      end)
    end)
    |> Enum.filter(& &1)
    |> Enum.map(fn
      term when is_list(term) -> term |> List.to_string()
      term when is_binary(term) -> term
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_categories_from_content(_), do: []

  defp parse_iso8601_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_iso8601_date(_), do: DateTime.utc_now()

  defp extract_image(_item) do
    # Try to find image in media content or HTML
    # TODO: Implement image extraction from enclosures or content
    nil
  end
end
