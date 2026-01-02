defmodule FuzzyRss.Repo.Migrations.CreateEntries do
  use Ecto.Migration

  def change do
    create table(:entries) do
      add :feed_id, references(:feeds, on_delete: :delete_all), null: false
      add :guid, :string, null: false
      add :url, :string
      add :title, :string
      add :author, :string
      add :content, :text
      add :summary, :text
      add :published_at, :utc_datetime
      add :extracted_content, :text
      add :extracted_at, :utc_datetime
      add :image_url, :string
      add :categories, {:array, :string}, default: []
      timestamps()
    end

    create unique_index(:entries, [:feed_id, :guid])
    create index(:entries, [:feed_id, :published_at])
  end
end
