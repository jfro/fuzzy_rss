defmodule FuzzyRss.RepoPostgres.Migrations.RenameFeverApiKeyToApiPassword do
  use Ecto.Migration

  def change do
    rename table(:users), :fever_api_key, to: :api_password
  end
end
