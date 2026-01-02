defmodule FuzzyRss.Content.UserEntryState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_entry_states" do
    field :read, :boolean, default: false
    field :starred, :boolean, default: false
    field :read_at, :utc_datetime
    field :starred_at, :utc_datetime

    belongs_to :user, FuzzyRss.Accounts.User
    belongs_to :entry, FuzzyRss.Content.Entry

    timestamps()
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:user_id, :entry_id, :read, :starred, :read_at, :starred_at])
    |> validate_required([:user_id, :entry_id])
    |> unique_constraint([:user_id, :entry_id])
  end
end
