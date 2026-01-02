defmodule FuzzyRss.Repo.Migrations.CreateFolders do
  use Ecto.Migration

  def change do
    create table(:folders) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :parent_id, references(:folders, on_delete: :delete_all)
      add :position, :integer, default: 0
      timestamps()
    end

    create index(:folders, [:user_id])
    create unique_index(:folders, [:user_id, :slug])
  end
end
