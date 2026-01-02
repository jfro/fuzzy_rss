defmodule FuzzyRss.Content.Feed do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feeds" do
    field :url, :string
    field :title, :string
    field :description, :string
    field :site_url, :string
    field :feed_type, :string
    field :last_fetched_at, :utc_datetime
    field :last_successful_fetch_at, :utc_datetime
    field :last_error, :string
    field :fetch_interval, :integer, default: 60
    field :etag, :string
    field :last_modified, :string
    field :favicon_url, :string
    field :active, :boolean, default: true

    has_many :entries, FuzzyRss.Content.Entry
    has_many :subscriptions, FuzzyRss.Content.Subscription

    timestamps()
  end

  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [
      :url,
      :title,
      :description,
      :site_url,
      :feed_type,
      :fetch_interval,
      :active,
      :last_fetched_at,
      :last_successful_fetch_at,
      :last_error,
      :etag,
      :last_modified,
      :favicon_url
    ])
    |> validate_required([:url])
    |> unique_constraint(:url)
  end
end
