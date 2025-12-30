defmodule FuzzyRss.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # "google", "github", "keycloak"
      add :provider, :string, null: false
      # User ID from provider
      add :provider_uid, :string, null: false
      # Email from provider
      add :email, :string
      # Name from provider
      add :name, :string
      # Avatar image stored as blob (avoids provider throttling)
      add :avatar, :binary
      # Store full provider response
      add :raw_data, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_identities, [:provider, :provider_uid])
    create index(:user_identities, [:user_id])
  end
end
