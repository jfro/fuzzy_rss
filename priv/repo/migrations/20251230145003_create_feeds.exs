defmodule FuzzyRss.Repo.Migrations.CreateFeeds do
  use Ecto.Migration

  def change do
    create table(:feeds) do
      add :url, :string, null: false
      add :title, :string
      add :description, :text
      add :site_url, :string
      add :feed_type, :string
      add :last_fetched_at, :utc_datetime
      add :last_successful_fetch_at, :utc_datetime
      add :last_error, :text
      add :fetch_interval, :integer, default: 60
      add :etag, :string
      add :last_modified, :string
      add :favicon_url, :string
      add :active, :boolean, default: true
      timestamps()
    end

    create unique_index(:feeds, [:url])
    create index(:feeds, [:last_fetched_at])
  end
end
