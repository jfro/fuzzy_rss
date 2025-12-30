defmodule FuzzyRss.RepoMySQL do
  use Ecto.Repo,
    otp_app: :fuzzy_rss,
    adapter: Ecto.Adapters.MyXQL
end
