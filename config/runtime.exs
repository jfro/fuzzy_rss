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
    :test ->
      "priv/fuzzy_rss_test#{System.get_env("MIX_TEST_PARTITION")}.db"

    _ ->
      System.get_env("SQLITE_DATABASE_URL") || System.get_env("DATABASE_URL") ||
        "priv/fuzzy_rss_dev.db"
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
    System.get_env("DATABASE_URL") ||
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
    System.get_env("DATABASE_URL") ||
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

# Set ecto_repos to the selected repo for migrations and other tasks
config :fuzzy_rss, ecto_repos: [repo_module]

# Store the selected repo module for use throughout the app
config :fuzzy_rss, :repo_module, repo_module

# Configure Oban with database-appropriate engine
oban_engine =
  case db_adapter do
    :sqlite -> Oban.Engines.Lite
    :mysql -> Oban.Engines.Dolphin
    :postgresql -> Oban.Engines.Basic
  end

config :fuzzy_rss, Oban, repo: repo_module, engine: oban_engine

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

  # URL configuration for generating absolute URLs
  # When behind a TLS-terminating proxy (nginx, Caddy, Traefik, etc.):
  # - The proxy handles HTTPS on port 443
  # - The proxy forwards to this app on HTTP (PORT, typically 4000)
  # - Set PHX_HOST to your domain
  # - PHX_URL_SCHEME defaults to "https"
  # - PHX_URL_PORT defaults to 443 (standard HTTPS port, omitted in URLs)
  url_scheme = System.get_env("PHX_URL_SCHEME", "https")
  url_port = String.to_integer(System.get_env("PHX_URL_PORT", "443"))

  # Check origin configuration for WebSocket connections
  # Set to false to allow any origin (use with caution)
  # Or set CHECK_ORIGIN to a comma-separated list of allowed origins
  check_origin =
    case System.get_env("CHECK_ORIGIN") do
      "false" -> false
      nil -> ["//#{host}"]
      origins -> String.split(origins, ",") |> Enum.map(&String.trim/1)
    end

  config :fuzzy_rss, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :fuzzy_rss, FuzzyRssWeb.Endpoint,
    url: [host: host, port: url_port, scheme: url_scheme],
    check_origin: check_origin,
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
  # Swoosh can be configured via environment variables for different mail providers.
  mailer_adapter = System.get_env("MAIL_ADAPTER", "local") |> String.downcase()

  mailer_config =
    case mailer_adapter do
      "smtp" ->
        # SMTP Configuration
        # Required: MAIL_SMTP_RELAY, MAIL_SMTP_USERNAME, MAIL_SMTP_PASSWORD
        # Optional: MAIL_SMTP_PORT (default: 587), MAIL_SMTP_TLS (default: always)
        base_smtp_config = [
          adapter: Swoosh.Adapters.SMTP,
          relay:
            System.get_env("MAIL_SMTP_RELAY") ||
              raise("MAIL_SMTP_RELAY is required for SMTP adapter"),
          username:
            System.get_env("MAIL_SMTP_USERNAME") ||
              raise("MAIL_SMTP_USERNAME is required for SMTP adapter"),
          password:
            System.get_env("MAIL_SMTP_PASSWORD") ||
              raise("MAIL_SMTP_PASSWORD is required for SMTP adapter"),
          port: String.to_integer(System.get_env("MAIL_SMTP_PORT", "587")),
          tls: String.to_existing_atom(System.get_env("MAIL_SMTP_TLS", "always")),
          retries: String.to_integer(System.get_env("MAIL_SMTP_RETRIES", "1")),
          no_mx_lookups: System.get_env("MAIL_SMTP_NO_MX_LOOKUPS", "false") == "true"
        ]

        # Add optional SSL setting
        smtp_config_with_ssl =
          case System.get_env("MAIL_SMTP_SSL") do
            "true" -> Keyword.put(base_smtp_config, :ssl, true)
            "false" -> Keyword.put(base_smtp_config, :ssl, false)
            _ -> base_smtp_config
          end

        # Add optional auth setting
        case System.get_env("MAIL_SMTP_AUTH") do
          nil ->
            smtp_config_with_ssl

          auth when auth in ["always", "never", "if_available"] ->
            Keyword.put(smtp_config_with_ssl, :auth, String.to_existing_atom(auth))

          _ ->
            smtp_config_with_ssl
        end

      "mailgun" ->
        # Mailgun Configuration
        # Required: MAIL_MAILGUN_API_KEY, MAIL_MAILGUN_DOMAIN
        # Optional: MAIL_MAILGUN_BASE_URL (for EU region)
        base_mailgun_config = [
          adapter: Swoosh.Adapters.Mailgun,
          api_key:
            System.get_env("MAIL_MAILGUN_API_KEY") ||
              raise("MAIL_MAILGUN_API_KEY is required for Mailgun adapter"),
          domain:
            System.get_env("MAIL_MAILGUN_DOMAIN") ||
              raise("MAIL_MAILGUN_DOMAIN is required for Mailgun adapter")
        ]

        # Add optional base URL for EU region
        case System.get_env("MAIL_MAILGUN_BASE_URL") do
          nil -> base_mailgun_config
          url -> Keyword.put(base_mailgun_config, :base_url, url)
        end

      "sendgrid" ->
        # SendGrid Configuration
        # Required: MAIL_SENDGRID_API_KEY
        [
          adapter: Swoosh.Adapters.Sendgrid,
          api_key:
            System.get_env("MAIL_SENDGRID_API_KEY") ||
              raise("MAIL_SENDGRID_API_KEY is required for SendGrid adapter")
        ]

      "postmark" ->
        # Postmark Configuration
        # Required: MAIL_POSTMARK_API_KEY
        [
          adapter: Swoosh.Adapters.Postmark,
          api_key:
            System.get_env("MAIL_POSTMARK_API_KEY") ||
              raise("MAIL_POSTMARK_API_KEY is required for Postmark adapter")
        ]

      "gmail" ->
        # Gmail API Configuration
        # Required: MAIL_GMAIL_ACCESS_TOKEN
        # Note: This uses Gmail API, not SMTP. For SMTP, use the "smtp" adapter.
        [
          adapter: Swoosh.Adapters.Gmail,
          access_token:
            System.get_env("MAIL_GMAIL_ACCESS_TOKEN") ||
              raise("MAIL_GMAIL_ACCESS_TOKEN is required for Gmail adapter")
        ]

      "local" ->
        # Local adapter for development (emails visible at /dev/mailbox)
        [adapter: Swoosh.Adapters.Local]

      other ->
        raise """
        Invalid MAIL_ADAPTER: #{inspect(other)}

        Supported values are: smtp, mailgun, sendgrid, postmark, gmail, local

        Set the MAIL_ADAPTER environment variable to one of the supported values.
        Examples:
          MAIL_ADAPTER=smtp MAIL_SMTP_RELAY=smtp.example.com ...
          MAIL_ADAPTER=sendgrid MAIL_SENDGRID_API_KEY=SG.xxxxx ...
          MAIL_ADAPTER=postmark MAIL_POSTMARK_API_KEY=xxxxx ...
          MAIL_ADAPTER=gmail MAIL_GMAIL_ACCESS_TOKEN=xxxxx ...
        """
    end

  config :fuzzy_rss, FuzzyRss.Mailer, mailer_config

  # Configure Swoosh API client for non-SMTP adapters (uses Req by default)
  if mailer_adapter in ["mailgun", "sendgrid", "postmark", "gmail"] do
    config :swoosh, :api_client, Swoosh.ApiClient.Req
  end
end

# Authentication configuration (read at runtime from environment variables)
# DISABLE_MAGIC_LINK: Set to "true" to disable magic link auth and require password-based auth
# SIGNUP_ENABLED: Set to "true" to allow unlimited signups (default),
#                 "false" to allow only the first user to signup (one-time registration)
config :fuzzy_rss, :auth,
  disable_magic_link: System.get_env("DISABLE_MAGIC_LINK", "false") == "true",
  signup_enabled: System.get_env("SIGNUP_ENABLED", "true") != "false"

# OIDC configuration (optional)
oidc_enabled = System.get_env("OIDC_ENABLED", "false") == "true"
config :fuzzy_rss, :oidc_enabled, oidc_enabled

if oidc_enabled do
  config :fuzzy_rss, :oidc,
    client_id:
      System.get_env("OIDC_CLIENT_ID") || raise("OIDC_CLIENT_ID is required when OIDC is enabled"),
    client_secret:
      System.get_env("OIDC_CLIENT_SECRET") ||
        raise("OIDC_CLIENT_SECRET is required when OIDC is enabled"),
    base_url:
      System.get_env("OIDC_BASE_URL") || raise("OIDC_BASE_URL is required when OIDC is enabled"),
    redirect_uri:
      System.get_env("OIDC_REDIRECT_URI") ||
        raise("OIDC_REDIRECT_URI is required when OIDC is enabled"),
    authorization_params: [scope: System.get_env("OIDC_SCOPE", "openid profile email")]
end
