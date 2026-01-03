# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fuzzy_rss, :scopes,
  user: [
    default: true,
    module: FuzzyRss.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: FuzzyRss.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

# Determine which repo to use based on DATABASE_ADAPTER env var
ecto_repos =
  case System.get_env("DATABASE_ADAPTER", "sqlite") |> String.to_atom() do
    :sqlite -> [FuzzyRss.RepoSQLite]
    :mysql -> [FuzzyRss.RepoMySQL]
    :postgresql -> [FuzzyRss.RepoPostgres]
    _ -> [FuzzyRss.RepoSQLite]
  end

config :fuzzy_rss,
  ecto_repos: ecto_repos,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :fuzzy_rss, FuzzyRssWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FuzzyRssWeb.ErrorHTML, json: FuzzyRssWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FuzzyRss.PubSub,
  live_view: [signing_salt: "NzmrwJKR"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fuzzy_rss, FuzzyRss.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fuzzy_rss: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  fuzzy_rss: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Ueberauth configuration
config :ueberauth, Ueberauth,
  providers: [
    oidc: {Ueberauth.Strategy.OIDC, []}
  ]

# Ueberauth OIDC strategy configuration (can be overridden per environment)
config :ueberauth, Ueberauth.Strategy.OIDC,
  client_id: System.get_env("OIDC_CLIENT_ID"),
  client_secret: System.get_env("OIDC_CLIENT_SECRET"),
  discovery_document_uri: System.get_env("OIDC_DISCOVERY_URL")

# Enable OIDC (optional, can be disabled)
config :fuzzy_rss, :oidc_enabled, System.get_env("OIDC_ENABLED", "false") == "true"

# Authentication configuration
# DISABLE_MAGIC_LINK: Set to "true" to disable magic link auth and require password-based auth
# SIGNUP_ENABLED: Set to "true" to allow unlimited signups (default),
#                 "false" to allow only the first user to signup (one-time registration)
config :fuzzy_rss, :auth,
  disable_magic_link: System.get_env("DISABLE_MAGIC_LINK", "false") == "true",
  signup_enabled: System.get_env("SIGNUP_ENABLED", "true") != "false"

# Configure Oban for background job processing
# Note: The repo and engine are configured in runtime.exs based on DATABASE_ADAPTER
config :fuzzy_rss, Oban,
  queues: [feed_fetcher: 10, extractor: 3, default: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"*/5 * * * *", FuzzyRss.Workers.FeedSchedulerWorker},
       {"0 2 * * *", FuzzyRss.Workers.CleanupWorker}
     ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
