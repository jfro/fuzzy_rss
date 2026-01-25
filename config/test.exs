import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# Database configuration is handled by config/runtime.exs
# DATABASE_ADAPTER env var works for all environments there
# Test-specific Ecto settings for all repo modules:
config :fuzzy_rss, FuzzyRss.RepoSQLite, pool: Ecto.Adapters.SQL.Sandbox
config :fuzzy_rss, FuzzyRss.RepoMySQL, pool: Ecto.Adapters.SQL.Sandbox
config :fuzzy_rss, FuzzyRss.RepoPostgres, pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fuzzy_rss, FuzzyRssWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "st/QYv6HK+iXUJnNxqgMEuAvXY84xP0PTAm79vqMouTEMjrq3oDM8yXft5nPpFgW",
  server: false

# In test we don't send emails
config :fuzzy_rss, FuzzyRss.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable Oban queues and plugins during tests to avoid sandbox connection issues
config :fuzzy_rss, Oban, testing: :manual, queues: false, plugins: false
