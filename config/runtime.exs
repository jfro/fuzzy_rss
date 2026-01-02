import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# Database adapter selection
# Defaults to SQLite for simplicity and ease of self-hosting
db_adapter = System.get_env("DATABASE_ADAPTER", "sqlite") |> String.to_atom()

IO.puts(
  "DEBUG: DATABASE_ADAPTER env var = #{inspect(System.get_env("DATABASE_ADAPTER"))}, parsed = #{inspect(db_adapter)}"
)

# Map adapter to repo module (handle both "postgres" and "postgresql")
repo_module =
  case db_adapter do
    :sqlite ->
      FuzzyRss.RepoSQLite

    :mysql ->
      FuzzyRss.RepoMySQL

    :postgresql ->
      FuzzyRss.RepoPostgres

    invalid ->
      raise """
      Invalid DATABASE_ADAPTER: #{inspect(invalid)}

      Supported values are: sqlite, mysql, postgresql, postgres

      Set the DATABASE_ADAPTER environment variable to one of the supported values.
      Example: DATABASE_ADAPTER=postgresql mix phx.server
      """
  end

# SQLite configuration (always available)
sqlite_db_name =
  case config_env() do
    :test -> "priv/fuzzy_rss_test#{System.get_env("MIX_TEST_PARTITION")}.db"
    _ -> System.get_env("SQLITE_DATABASE_URL") || "priv/fuzzy_rss_dev.db"
  end

sqlite_config = [
  adapter: Ecto.Adapters.SQLite3,
  database: sqlite_db_name,
  priv: "priv/repo"
]

# MySQL configuration (always available)
mysql_db_suffix =
  case config_env() do
    :test -> "fuzzy_rss_test#{System.get_env("MIX_TEST_PARTITION")}"
    _ -> "fuzzy_rss_dev"
  end

mysql_url =
  System.get_env("MYSQL_DATABASE_URL") ||
    "mysql://root:mysql@localhost/#{mysql_db_suffix}"

mysql_config = [
  adapter: Ecto.Adapters.MyXQL,
  url: mysql_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: String.to_existing_atom(System.get_env("DATABASE_SSL", "false")),
  priv: "priv/repo"
]

# PostgreSQL configuration (always available)
postgres_db_suffix =
  case config_env() do
    :test -> "fuzzy_rss_test#{System.get_env("MIX_TEST_PARTITION")}"
    _ -> "fuzzy_rss_dev"
  end

postgres_url =
  System.get_env("POSTGRES_DATABASE_URL") ||
    "ecto://postgres:postgres@localhost/#{postgres_db_suffix}"

postgres_config = [
  adapter: Ecto.Adapters.Postgres,
  url: postgres_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: String.to_existing_atom(System.get_env("DATABASE_SSL", "false")),
  priv: "priv/repo"
]

# Configure only the selected repo
case repo_module do
  FuzzyRss.RepoSQLite -> config :fuzzy_rss, FuzzyRss.RepoSQLite, sqlite_config
  FuzzyRss.RepoMySQL -> config :fuzzy_rss, FuzzyRss.RepoMySQL, mysql_config
  FuzzyRss.RepoPostgres -> config :fuzzy_rss, FuzzyRss.RepoPostgres, postgres_config
end

# Store the selected repo module for use throughout the app
config :fuzzy_rss, :repo_module, repo_module

# Configure Oban repo based on selected database adapter
config :fuzzy_rss, Oban, repo: repo_module

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/fuzzy_rss start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :fuzzy_rss, FuzzyRssWeb.Endpoint, server: true
end

if config_env() == :prod do
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :fuzzy_rss, FuzzyRss.Repo,
    # ssl: true,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :fuzzy_rss, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :fuzzy_rss, FuzzyRssWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :fuzzy_rss, FuzzyRssWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :fuzzy_rss, FuzzyRssWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :fuzzy_rss, FuzzyRss.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
