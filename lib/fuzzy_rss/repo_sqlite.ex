defmodule FuzzyRss.RepoSQLite do
  use Ecto.Repo,
    otp_app: :fuzzy_rss,
    adapter: Ecto.Adapters.SQLite3
end
