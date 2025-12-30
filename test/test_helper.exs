ExUnit.start()

repo = Application.fetch_env!(:fuzzy_rss, :repo_module)
Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
