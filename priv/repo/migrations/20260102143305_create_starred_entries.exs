defmodule FuzzyRss.Repo.Migrations.CreateStarredEntries do
  use Ecto.Migration

  def change do
    create table(:starred_entries) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :guid, :string, null: false
      add :url, :string
      add :title, :string
      add :author, :string
      add :content, :text
      add :summary, :text
      add :published_at, :utc_datetime
      add :image_url, :string
      add :categories, {:array, :string}, default: []
      add :feed_title, :string
      add :feed_url, :string
      add :starred_at, :utc_datetime, null: false
      timestamps()
    end

    create index(:starred_entries, [:user_id])
    create index(:starred_entries, [:user_id, :starred_at])
    create unique_index(:starred_entries, [:user_id, :guid])
  end
end
