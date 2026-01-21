defmodule FuzzyRss.Repo.Migrations.AddFeverApiKeyToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :fever_api_key, :string
    end

    create index(:users, [:fever_api_key])
  end
end
