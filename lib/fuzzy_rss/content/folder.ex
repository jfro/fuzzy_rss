defmodule FuzzyRss.Content.Folder do
  use Ecto.Schema
  import Ecto.Changeset

  schema "folders" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0

    belongs_to :user, FuzzyRss.Accounts.User
    belongs_to :parent, FuzzyRss.Content.Folder

    has_many :children, FuzzyRss.Content.Folder, foreign_key: :parent_id
    has_many :subscriptions, FuzzyRss.Content.Subscription

    timestamps()
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :slug, :position, :user_id, :parent_id])
    |> validate_required([:name, :user_id])
    |> unique_constraint([:user_id, :slug])
  end
end
