defmodule FuzzyRss.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :feed_id, references(:feeds, on_delete: :delete_all), null: false
      add :folder_id, references(:folders, on_delete: :nilify_all)
      add :title_override, :string
      add :position, :integer, default: 0
      add :muted, :boolean, default: false
      timestamps()
    end

    create unique_index(:subscriptions, [:user_id, :feed_id])
    create index(:subscriptions, [:user_id, :folder_id])
  end
end
