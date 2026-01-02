defmodule FuzzyRss.Repo.Migrations.CreateUserEntryStates do
  use Ecto.Migration

  def change do
    create table(:user_entry_states) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :entry_id, references(:entries, on_delete: :delete_all), null: false
      add :read, :boolean, default: false
      add :starred, :boolean, default: false
      add :read_at, :utc_datetime
      add :starred_at, :utc_datetime
      timestamps()
    end

    create unique_index(:user_entry_states, [:user_id, :entry_id])
    create index(:user_entry_states, [:user_id, :read, :starred])
  end
end
