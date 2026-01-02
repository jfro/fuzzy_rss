defmodule FuzzyRss.Content.StarredEntry do
  @moduledoc "An archived entry that was starred by a user"
  use Ecto.Schema
  import Ecto.Changeset

  schema "starred_entries" do
    field :guid, :string
    field :url, :string
    field :title, :string
    field :author, :string
    field :content, :string
    field :summary, :string
    field :published_at, :utc_datetime
    field :image_url, :string
    field :categories, FuzzyRss.Ecto.JSONArray, default: []
    field :feed_title, :string
    field :feed_url, :string
    field :starred_at, :utc_datetime

    belongs_to :user, FuzzyRss.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(starred_entry, attrs) do
    starred_entry
    |> cast(attrs, [
      :user_id,
      :guid,
      :url,
      :title,
      :author,
      :content,
      :summary,
      :published_at,
      :image_url,
      :categories,
      :feed_title,
      :feed_url,
      :starred_at
    ])
    |> validate_required([:user_id, :guid, :starred_at])
  end
end
