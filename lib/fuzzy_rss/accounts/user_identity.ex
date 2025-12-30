defmodule FuzzyRss.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :provider_uid, :string
    field :email, :string
    field :name, :string
    # Avatar image blob
    field :avatar, :binary
    field :raw_data, :map

    belongs_to :user, FuzzyRss.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_uid, :email, :name, :avatar, :raw_data])
    |> validate_required([:provider, :provider_uid])
    |> unique_constraint([:provider, :provider_uid])
  end
end
