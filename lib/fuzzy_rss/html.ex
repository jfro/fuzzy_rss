defmodule FuzzyRss.Html do
  @moduledoc """
  Utilities for handling HTML content in feeds.
  """

  @allowed_summary_tags ~w(b i em strong span)
  @allowed_content_tags ~w(p br b i em strong span a ul ol li blockquote code pre h1 h2 h3 h4 h5 h6 img div figure figcaption)
  @allowed_attrs %{
    "a" => ["href", "title", "target"],
    "img" => ["src", "alt", "title", "width", "height"],
    "code" => ["class"],
    "pre" => ["class"]
  }

  @doc """
  Sanitizes a summary for display in lists.
  Strips most tags but keeps basic formatting like bold and italic.
  Removes all attributes to prevent XSS.
  """
  def sanitize_summary(nil), do: ""

  def sanitize_summary(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} ->
        nodes
        |> sanitize_nodes(@allowed_summary_tags)
        |> Floki.raw_html()

      _ ->
        html |> String.replace(~r/<[^>]*>/, "")
    end
  end

  @doc """
  Sanitizes full content for display in the article view.
  Allows more tags but still strips dangerous ones and attributes.
  """
  def sanitize_content(nil), do: ""

  def sanitize_content(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} ->
        nodes
        |> sanitize_nodes(@allowed_content_tags, true)
        |> Floki.raw_html()

      _ ->
        # Fallback to simple stripping if parsing fails
        html
        |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
        |> String.replace(~r/<[^>]*>/, "")
    end
  end

  defp sanitize_nodes(nodes, allowed_tags, allow_attrs \\ false) when is_list(nodes) do
    nodes
    |> Enum.map(&sanitize_node(&1, allowed_tags, allow_attrs))
    |> List.flatten()
  end

  defp sanitize_node({tag, attrs, children}, allowed_tags, allow_attrs) do
    if tag in allowed_tags do
      clean_attrs = if allow_attrs, do: filter_attrs(tag, attrs), else: []
      [{tag, clean_attrs, sanitize_nodes(children, allowed_tags, allow_attrs)}]
    else
      sanitize_nodes(children, allowed_tags, allow_attrs)
    end
  end

  defp sanitize_node(text, _allowed_tags, _allow_attrs) when is_binary(text), do: [text]
  defp sanitize_node(_, _allowed_tags, _allow_attrs), do: []

  defp filter_attrs(tag, attrs) do
    allowed = Map.get(@allowed_attrs, tag, [])

    attrs
    |> Enum.filter(fn {name, _value} -> name in allowed end)
    |> Enum.map(fn {name, value} ->
      case name do
        "href" -> {name, sanitize_url(value)}
        "src" -> {name, sanitize_url(value)}
        _ -> {name, value}
      end
    end)
  end

  defp sanitize_url(url) do
    if String.starts_with?(url, ["http://", "https://", "mailto:", "/", "data:image/"]) do
      url
    else
      "#"
    end
  end

  @doc """
  Completely strips all HTML tags from a string, returning plain text.
  """
  def strip_tags(nil), do: ""

  def strip_tags(html) when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> Floki.text(nodes)
      _ -> html |> String.replace(~r/<[^>]*>/, "")
    end
  end
end
