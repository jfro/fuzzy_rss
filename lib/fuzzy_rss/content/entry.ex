defmodule FuzzyRss.Content.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "entries" do
    field :guid, :string
    field :url, :string
    field :title, :string
    field :author, :string
    field :content, :string
    field :summary, :string
    field :published_at, :utc_datetime
    field :extracted_content, :string
    field :extracted_at, :utc_datetime
    field :image_url, :string
    field :categories, {:array, :string}, default: []

    belongs_to :feed, FuzzyRss.Content.Feed

    has_many :user_entry_states, FuzzyRss.Content.UserEntryState

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :feed_id,
      :guid,
      :url,
      :title,
      :author,
      :content,
      :summary,
      :published_at,
      :image_url,
      :categories
    ])
    |> validate_required([:feed_id, :guid])
    |> unique_constraint([:feed_id, :guid])
  end
end
