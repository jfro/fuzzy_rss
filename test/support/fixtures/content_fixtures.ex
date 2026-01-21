defmodule FuzzyRss.ContentFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FuzzyRss.Content` context.
  """

  alias FuzzyRss.Repo
  alias FuzzyRss.Content.{Feed, Entry, Subscription, Folder}

  def unique_feed_url, do: "https://example.com/feed-#{System.unique_integer()}.xml"

  def feed_fixture(attrs \\ %{}) do
    default_attrs = %{
      "url" => unique_feed_url(),
      "title" => "Test Feed",
      "description" => "Test Description"
    }

    # Convert atom keys to string keys if present
    attrs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.into(%{})

    final_attrs = Map.merge(default_attrs, attrs)

    {:ok, feed} =
      %Feed{}
      |> Feed.changeset(final_attrs)
      |> Repo.insert()

    feed
  end

  def subscription_fixture(user, feed \\ nil, attrs \\ %{}) do
    feed = feed || feed_fixture()

    default_attrs = %{
      "user_id" => user.id,
      "feed_id" => feed.id
    }

    # Convert atom keys to string keys if present
    attrs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.into(%{})

    final_attrs = Map.merge(default_attrs, attrs)

    {:ok, subscription} =
      %Subscription{}
      |> Subscription.changeset(final_attrs)
      |> Repo.insert()

    subscription
  end

  def entry_fixture(feed, attrs \\ %{}) do
    default_attrs = %{
      "feed_id" => feed.id,
      "guid" => "entry-#{System.unique_integer()}",
      "title" => "Test Entry",
      "url" => "https://example.com/entry-#{System.unique_integer()}",
      "summary" => "Test summary",
      "content" => "Test content",
      "published_at" => DateTime.utc_now(),
      "categories" => []
    }

    # Convert atom keys to string keys if present
    attrs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.into(%{})

    final_attrs = Map.merge(default_attrs, attrs)

    {:ok, entry} =
      %Entry{}
      |> Entry.changeset(final_attrs)
      |> Repo.insert()

    entry
  end

  def folder_fixture(user, attrs \\ %{}) do
    default_attrs = %{
      "user_id" => user.id,
      "name" => "Test Folder #{System.unique_integer()}",
      "slug" => "test-folder-#{System.unique_integer()}"
    }

    # Convert atom keys to string keys if present
    attrs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.into(%{})

    final_attrs = Map.merge(default_attrs, attrs)

    {:ok, folder} =
      %Folder{}
      |> Folder.changeset(final_attrs)
      |> Repo.insert()

    folder
  end
end
