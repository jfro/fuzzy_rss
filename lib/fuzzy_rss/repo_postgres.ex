defmodule FuzzyRss.RepoPostgres do
  use Ecto.Repo,
    otp_app: :fuzzy_rss,
    adapter: Ecto.Adapters.Postgres
end
