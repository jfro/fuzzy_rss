defmodule FuzzyRss.Feeds.OPML do
  @moduledoc "OPML import/export for subscription lists"

  require Logger
  import Ecto.Query
  alias FuzzyRss.Content
  alias FuzzyRss.Content.Subscription

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  def export(user) do
    subscriptions = list_user_subscriptions(user)
    folders = Content.list_user_folders(user)

    xml = build_opml_xml(user, subscriptions, folders)
    {:ok, xml}
  end

  def import(xml_string, user) do
    Logger.debug("OPML: Starting import, input size: #{byte_size(xml_string)}")

    with {:ok, document} <- parse_opml(xml_string),
         outlines <- extract_outlines(document) do
      Logger.debug("OPML: Found #{Enum.count(outlines)} root outlines")
      results = process_outlines(outlines, user, nil)

      Logger.info(
        "OPML: Import complete - #{results.created_feeds} feeds, #{results.created_folders} folders, #{Enum.count(results.errors)} errors"
      )

      Logger.debug("OPML: Errors: #{inspect(results.errors)}")
      {:ok, results}
    else
      {:error, reason} ->
        Logger.error("OPML: Import failed - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp list_user_subscriptions(user) do
    from(s in Subscription,
      where: s.user_id == ^user.id,
      preload: :feed
    )
    |> repo().all()
  end

  defp build_opml_xml(user, subscriptions, folders) do
    subs_by_folder = Enum.group_by(subscriptions, & &1.folder_id)

    body = build_body(subs_by_folder, folders)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>FuzzyRSS</title>
        <dateCreated>#{DateTime.utc_now()}</dateCreated>
        <ownerName>#{user.email}</ownerName>
      </head>
      <body>
        #{body}
      </body>
    </opml>
    """
    |> String.trim()
  end

  defp build_body(subs_by_folder, folders) do
    # Root feeds (no folder)
    root_subs = subs_by_folder[nil] || []
    root_xml = Enum.map_join(root_subs, "\n", &feed_outline/1)

    # Folders with nested feeds
    folder_xml =
      Enum.map_join(folders, "\n", fn folder ->
        folder_subs = subs_by_folder[folder.id] || []
        feeds_xml = Enum.map_join(folder_subs, "\n", &feed_outline/1)

        ~s[<outline type="folder" text="#{escape_xml(folder.name)}">
        #{feeds_xml}
      </outline>]
      end)

    "#{root_xml}\n#{folder_xml}"
  end

  defp feed_outline(subscription) do
    feed = subscription.feed
    title = subscription.title_override || feed.title || "Untitled"
    ~s[<outline type="rss" text="#{escape_xml(title)}" xmlUrl="#{escape_xml(feed.url)}" />]
  end

  defp escape_xml(nil), do: ""

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp parse_opml(xml_string) do
    case Floki.parse_document(xml_string) do
      {:ok, document} -> {:ok, document}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_outlines(document) do
    Floki.find(document, "body > outline")
  end

  defp process_outlines(outlines, user, parent_folder_id) do
    results = %{created_feeds: 0, created_folders: 0, errors: []}

    Enum.reduce(outlines, results, fn outline, acc ->
      type = Floki.attribute(outline, "type") |> List.first()
      text = Floki.attribute(outline, "text") |> List.first()
      xml_url = Floki.attribute(outline, "xmlurl") |> List.first()
      children = Floki.find(outline, "> outline")
      has_children = Enum.count(children) > 0

      # Infer type based on actual content:
      # - If it has xmlUrl, it's definitely a feed
      # - If it has children (regardless of explicit type), treat as folder
      # - Otherwise use the explicit type if provided
      inferred_type =
        cond do
          xml_url -> "rss"
          has_children -> "folder"
          type in ["folder", "rss"] -> type
          true -> nil
        end

      Logger.debug(
        "OPML: Processing outline - type: #{inspect(inferred_type)}, text: #{inspect(text)}, has_children: #{has_children}, xmlUrl: #{inspect(xml_url)}"
      )

      case inferred_type do
        "folder" ->
          process_folder(outline, user, parent_folder_id, acc)

        "rss" ->
          process_feed(outline, user, parent_folder_id, acc)

        _ ->
          Logger.debug("OPML: Skipping outline with no type: #{inspect(text)}")
          acc
      end
    end)
  end

  defp process_folder(outline, user, _parent_id, acc) do
    name = Floki.attribute(outline, "text") |> List.first()
    children = Floki.find(outline, "> outline")

    # Special case: skip creating a folder for "Uncategorized" and import feeds at top level
    if is_uncategorized?(name) do
      Logger.debug("OPML: Skipping Uncategorized folder, importing feeds at top level")
      child_results = process_outlines(children, user, nil)

      %{
        acc
        | created_feeds: acc.created_feeds + child_results.created_feeds,
          created_folders: acc.created_folders + child_results.created_folders
      }
    else
      case create_folder(user, name) do
        {:ok, folder} ->
          child_results = process_outlines(children, user, folder.id)

          %{
            acc
            | created_feeds: acc.created_feeds + child_results.created_feeds,
              created_folders: acc.created_folders + child_results.created_folders + 1
          }

        {:error, reason} ->
          Map.update(acc, :errors, [reason], &[reason | &1])
      end
    end
  end

  defp process_feed(outline, user, folder_id, acc) do
    feed_url = Floki.attribute(outline, "xmlurl") |> List.first()

    if feed_url && String.length(feed_url) > 0 do
      case Content.subscribe_to_feed(user, feed_url, folder_id: folder_id) do
        {:ok, _subscription} ->
          %{acc | created_feeds: acc.created_feeds + 1}

        {:error, reason} ->
          Map.update(acc, :errors, [reason], &[reason | &1])
      end
    else
      Map.update(acc, :errors, ["Feed missing xmlUrl"], &[&1 | &1])
    end
  end

  defp create_folder(user, name) do
    Content.create_folder(user, %{
      name: name,
      slug: slugify(name)
    })
  end

  defp is_uncategorized?(name) do
    name && String.downcase(name) == "uncategorized"
  end

  defp slugify(nil), do: "untitled"

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/[-\s]+/, "-")
    |> String.trim("-")
  end
end
