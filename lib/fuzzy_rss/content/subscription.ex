defmodule FuzzyRss.Content.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :title_override, :string
    field :position, :integer, default: 0
    field :muted, :boolean, default: false

    belongs_to :user, FuzzyRss.Accounts.User
    belongs_to :feed, FuzzyRss.Content.Feed
    belongs_to :folder, FuzzyRss.Content.Folder

    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:user_id, :feed_id, :folder_id, :title_override, :position, :muted])
    |> validate_required([:user_id, :feed_id])
    |> unique_constraint([:user_id, :feed_id])
  end
end
