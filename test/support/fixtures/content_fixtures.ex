defmodule FuzzyRss.ContentFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FuzzyRss.Content` context.
  """

  alias FuzzyRss.Repo
  alias FuzzyRss.Content.{Feed, Entry, Subscription}

  def unique_feed_url, do: "https://example.com/feed-#{System.unique_integer()}.xml"

  def feed_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        "url" => unique_feed_url(),
        "title" => "Test Feed",
        "description" => "Test Description"
      })

    {:ok, feed} =
      %Feed{}
      |> Feed.changeset(attrs)
      |> Repo.insert()

    feed
  end

  def subscription_fixture(user, feed \\ nil, attrs \\ %{}) do
    feed = feed || feed_fixture()

    attrs =
      attrs
      |> Enum.into(%{
        "user_id" => user.id,
        "feed_id" => feed.id
      })

    {:ok, subscription} =
      %Subscription{}
      |> Subscription.changeset(attrs)
      |> Repo.insert()

    subscription
  end

  def entry_fixture(feed, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        "feed_id" => feed.id,
        "guid" => "entry-#{System.unique_integer()}",
        "title" => "Test Entry",
        "url" => "https://example.com/entry-#{System.unique_integer()}",
        "summary" => "Test summary",
        "content" => "Test content",
        "published_at" => DateTime.utc_now(),
        "categories" => []
      })

    {:ok, entry} =
      %Entry{}
      |> Entry.changeset(attrs)
      |> Repo.insert()

    entry
  end
end
