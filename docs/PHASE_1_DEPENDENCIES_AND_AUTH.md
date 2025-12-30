# Phase 1: Dependencies & Authentication

**Duration:** Week 1 (2-3 days)
**Previous Phase:** None (start here)
**Next Phase:** [Phase 2: Database Schema](PHASE_2_DATABASE_SCHEMA.md)

## Overview

This phase sets up the project dependencies to support all three databases (PostgreSQL, MySQL, SQLite) and configures authentication. **SQLite is the default** for simplicity and ease of self-hosting. The database adapter is selected at runtime via environment variables, allowing a single build to support multiple backends.

**Authentication options:**
1. **Email/Password (Required)** - Using Phoenix's built-in `phx.gen.auth` scaffold with bcrypt hashing
2. **OIDC/OAuth (Optional)** - Support for external identity providers (Google, GitHub, Keycloak, etc.) using the Assent library

Both methods can coexist, allowing users to authenticate via email/password, OIDC, or both.

## 1.1: Update `mix.exs` for Multi-Database Support

Replace the current database adapter with all three included (needed for universal Docker image):

```elixir
defp deps do
  [
    {:phoenix, "~> 1.8.1"},
    {:phoenix_ecto, "~> 4.5"},
    {:ecto_sql, "~> 3.13"},

    # Include ALL database adapters (selected via ENV at runtime)
    # All three are compiled into the release so a single Docker image works
    {:myxql, ">= 0.0.0"},           # MySQL/MariaDB
    {:postgrex, ">= 0.0.0"},        # PostgreSQL
    {:exqlite, ">= 0.0.0"},         # SQLite

    {:phoenix_html, "~> 4.1"},
    {:phoenix_live_reload, "~> 1.2", only: :dev},
    {:phoenix_live_view, "~> 1.1.0"},
    {:lazy_html, ">= 0.1.0", only: :test},
    {:phoenix_live_dashboard, "~> 0.8.3"},
    {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
    {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
    {:heroicons, ...},
    {:swoosh, "~> 1.16"},
    {:req, "~> 0.5"},
    {:telemetry_metrics, "~> 1.0"},
    {:telemetry_poller, "~> 1.0"},
    {:gettext, "~> 0.26"},
    {:jason, "~> 1.2"},
    {:dns_cluster, "~> 0.2.0"},
    {:bandit, "~> 1.5"},

    # Authentication
    {:bcrypt_elixir, "~> 3.0"},      # Password hashing
    {:ueberauth, "~> 0.10"},         # OAuth/OIDC authentication
    {:ueberauth_oidc, "~> 0.3"},     # OIDC strategy for Ueberauth

    # RSS & Feed Processing
    {:feeder_ex, "~> 1.1"},          # RSS/Atom parsing
    {:oban, "~> 2.18"},              # Background jobs
    {:floki, "~> 0.36"},             # HTML parsing
    {:readability, "~> 0.12"},       # Article extraction
    {:saxy, "~> 1.5"},               # OPML/XML parsing
    {:joken, "~> 2.6"},              # JWT for API
    {:timex, "~> 3.7"},              # Date/time handling
    {:slugify, "~> 1.3"}             # URL-friendly slugs
  ]
end
```

**Note:** All three database adapters are included in production releases (not optional). The adapter is selected at runtime via `DATABASE_ADAPTER` env variable. This allows a single Docker image to support PostgreSQL, MySQL, and SQLite.

## 1.2: Configure Database Selection via ENV

**Update `config/config.exs`** to set the default database adapter:

```elixir
# Determine which database adapter to use based on ENV
# Defaults to :sqlite if not specified (simplest for self-hosting)
db_adapter =
  System.get_env("DATABASE_ADAPTER", "sqlite")
  |> String.to_atom()

# Configure Ecto to use the selected adapter
config :fuzzy_rss, FuzzyRss.Repo,
  adapter: Ecto.Adapters.Postgres,  # Will be overridden in runtime.exs
  database: "fuzzy_rss_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10

# This gets overridden in runtime.exs based on DATABASE_ADAPTER ENV var
```

**Create `config/runtime.exs`** (if not already present) with database adapter detection:

```elixir
import Config

# Database adapter selection
# Defaults to SQLite for simplicity and ease of self-hosting
db_adapter = System.get_env("DATABASE_ADAPTER", "sqlite") |> String.to_atom()

database_url =
  System.get_env("DATABASE_URL") ||
    case db_adapter do
      :mysql ->
        # MySQL connection string format
        "mysql://root:@localhost/fuzzy_rss_dev"

      :postgresql ->
        # PostgreSQL connection string format
        "ecto://postgres:postgres@localhost/fuzzy_rss_dev"

      _ ->
        # SQLite (default) - uses local file path
        "sqlite3:./fuzzy_rss_dev.db"
    end

# Configure Ecto Repos
config :fuzzy_rss, FuzzyRss.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: String.to_existing_atom(System.get_env("DATABASE_SSL", "false")),
  adapter: case db_adapter do
    :mysql -> Ecto.Adapters.MyXQL
    :postgresql -> Ecto.Adapters.Postgres
    _ -> Ecto.Adapters.SQLite3  # default
  end

# Configure Oban for the selected database
config :fuzzy_rss, Oban,
  repo: FuzzyRss.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
      crontab: [
        {"*/5 * * * *", FuzzyRss.Workers.FeedSchedulerWorker},
        {"0 2 * * *", FuzzyRss.Workers.CleanupWorker}
      ]
    }
  ],
  queues: [feed_fetcher: 10, extractor: 3, default: 5]
```

## 1.3: Update `mix.exs` Aliases for Multi-DB Setup

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
    "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
    "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
    "assets.build": ["compile", "tailwind fuzzy_rss", "esbuild fuzzy_rss"],
    "assets.deploy": [
      "tailwind fuzzy_rss --minify",
      "esbuild fuzzy_rss --minify",
      "phx.digest"
    ],
    precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
  ]
end
```

## 1.4: Run Setup & Generate Auth

```bash
# Install dependencies
mix deps.get

# For SQLite (default)
mix ecto.setup

# OR for PostgreSQL
DATABASE_ADAPTER=postgresql mix ecto.setup

# OR for MySQL
DATABASE_ADAPTER=mysql mix ecto.setup
```

Then generate auth scaffold:
```bash
mix phx.gen.auth Accounts User users
```

This creates:
- `lib/fuzzy_rss/accounts.ex` - User context
- `lib/fuzzy_rss/accounts/user.ex` - User schema
- `lib/fuzzy_rss_web/user_auth.ex` - Auth plugs
- LiveView pages for registration/login
- Migrations for users/tokens tables

## 1.5: Optional - Configure OIDC Authentication

OIDC allows users to authenticate with external providers (Google, GitHub, Keycloak, etc.). This is optional but recommended for corporate/multi-user deployments. We use Ueberauth with the OIDC strategy.

### Configure Ueberauth & OIDC

Add to `config/config.exs`:

```elixir
# Ueberauth configuration
config :ueberauth, Ueberauth,
  providers: [
    oidc: {Ueberauth.Strategy.OIDC, []}
  ]

# Ueberauth OIDC strategy configuration
config :ueberauth, Ueberauth.Strategy.OIDC.Google,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
  discovery_document_uri: "https://accounts.google.com/.well-known/openid-configuration"

config :ueberauth, Ueberauth.Strategy.OIDC.GitHub,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
  discovery_document_uri: "https://github.com/.well-known/openid-configuration"

# Keycloak / Generic OIDC
keycloak_realm_url = System.get_env("KEYCLOAK_REALM_URL", "")
config :ueberauth, Ueberauth.Strategy.OIDC.Keycloak,
  client_id: System.get_env("KEYCLOAK_CLIENT_ID"),
  client_secret: System.get_env("KEYCLOAK_CLIENT_SECRET"),
  discovery_document_uri: "#{keycloak_realm_url}/.well-known/openid-configuration"

# Endpoint configuration for Ueberauth
config :fuzzy_rss, FuzzyRssWeb.Endpoint,
  secret_key_base: System.get_env("SECRET_KEY_BASE") || "change_me",
  # ... other config ...

# Enable OIDC (optional, can be disabled)
config :fuzzy_rss, :oidc_enabled, System.get_env("OIDC_ENABLED", "false") == "true"
```

### Database Schema for OIDC Identities

In the user migration file, add a new migration to track OIDC identities:

```elixir
# priv/repo/migrations/*_create_user_identities.exs
create table(:user_identities) do
  add :user_id, references(:users, on_delete: :delete_all), null: false
  add :provider, :string, null: false  # "google", "github", "keycloak"
  add :provider_uid, :string, null: false  # User ID from provider
  add :email, :string  # Email from provider
  add :name, :string  # Name from provider
  add :avatar, :binary  # Avatar image stored as blob (avoids provider throttling)
  add :raw_data, :map  # Store full provider response

  timestamps()
end

create unique_index(:user_identities, [:provider, :provider_uid])
create index(:user_identities, [:user_id])
```

### User Schema Updates

Update `lib/fuzzy_rss/accounts/user.ex`:

```elixir
defmodule FuzzyRss.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime

    # New fields
    field :preferences, :map, default: %{}
    field :api_token, :binary
    field :timezone, :string, default: "UTC"

    # OIDC support
    has_many :identities, FuzzyRss.Accounts.UserIdentity, on_delete: :delete_all

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :timezone])
    |> validate_email()
    |> validate_password()
  end

  # ... other changesets ...
end
```

Create `lib/fuzzy_rss/accounts/user_identity.ex`:

```elixir
defmodule FuzzyRss.Accounts.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :provider_uid, :string
    field :email, :string
    field :name, :string
    field :avatar, :binary  # Avatar image blob
    field :raw_data, :map

    belongs_to :user, FuzzyRss.Accounts.User

    timestamps()
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_uid, :email, :name, :avatar, :raw_data])
    |> validate_required([:provider, :provider_uid])
    |> unique_constraint([:provider, :provider_uid])
  end
end
```

### OIDC Context Functions

Create `lib/fuzzy_rss/accounts/oidc.ex`:

```elixir
defmodule FuzzyRss.Accounts.OIDC do
  @moduledoc "OIDC/OAuth provider integration with Ueberauth"

  alias FuzzyRss.Accounts
  alias FuzzyRss.Repo

  def enabled?, do: Application.fetch_env!(:fuzzy_rss, :oidc_enabled)

  def find_or_create_user(provider, ueberauth_info) do
    # Extract info from Ueberauth callback
    extra = ueberauth_info.extra
    provider_uid = ueberauth_info.uid
    email = ueberauth_info.info.email
    name = ueberauth_info.info.name
    avatar_url = ueberauth_info.info.image

    # Download and store avatar as blob to avoid provider throttling
    avatar_blob =
      if avatar_url do
        download_avatar_blob(avatar_url)
      else
        nil
      end

    identity_attrs = %{
      provider: to_string(provider),
      provider_uid: to_string(provider_uid),
      email: email,
      name: name,
      avatar: avatar_blob,
      raw_data: Map.from_struct(ueberauth_info)
    }

    case Repo.get_by(Accounts.UserIdentity, provider: to_string(provider), provider_uid: to_string(provider_uid)) do
      nil ->
        # Create new user and identity
        create_user_with_identity(email, identity_attrs)

      identity ->
        # Return existing user
        {:ok, Repo.preload(identity, :user).user}
    end
  end

  defp download_avatar_blob(url) do
    case Req.get(url) do
      {:ok, response} ->
        response.body

      {:error, _reason} ->
        nil
    end
  rescue
    _ -> nil
  end

  defp create_user_with_identity(email, identity_attrs) do
    Repo.transaction(fn ->
      user = Repo.insert!(%Accounts.User{
        email: email,
        confirmed_at: DateTime.utc_now()
      })

      identity_attrs = Map.put(identity_attrs, :user_id, user.id)
      Repo.insert!(Accounts.UserIdentity.changeset(%Accounts.UserIdentity{}, identity_attrs))

      user
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### OIDC Controller

Create `lib/fuzzy_rss_web/controllers/auth_controller.ex`:

```elixir
defmodule FuzzyRssWeb.AuthController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.Accounts
  alias FuzzyRssWeb.UserAuth

  def request(conn, _params) do
    render(conn, "request.html")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: Routes.page_path(conn, :index))
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider}) do
    if Accounts.OIDC.enabled? do
      case Accounts.OIDC.find_or_create_user(provider, auth) do
        {:ok, user} ->
          conn
          |> put_flash(:info, "Successfully authenticated with #{provider}")
          |> UserAuth.log_in_user(user)

        {:error, reason} ->
          conn
          |> put_flash(:error, "Failed to authenticate: #{inspect(reason)}")
          |> redirect(to: Routes.page_path(conn, :index))
      end
    else
      conn
      |> put_flash(:error, "OIDC is not enabled")
      |> redirect(to: Routes.page_path(conn, :index))
    end
  end
end
```

Add to `lib/fuzzy_rss_web/views/auth_view.ex`:

```elixir
defmodule FuzzyRssWeb.AuthView do
  use FuzzyRssWeb, :view
end
```

### Router Configuration

Add to `lib/fuzzy_rss_web/router.ex`:

```elixir
scope "/auth", FuzzyRssWeb do
  pipe_through :browser

  # Email/password auth (from phx.gen.auth)
  post "/users/log_in", UserSessionController, :create
  delete "/users/log_out", UserSessionController, :delete

  # OIDC auth (optional) - Ueberauth routes
  if Application.fetch_env!(:fuzzy_rss, :oidc_enabled) do
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end
end

# Ueberauth plug configuration in pipeline
pipeline :ueberauth do
  plug Ueberauth
end
```

### Environment Variables

Add to `.env` (or your deployment configuration):

```bash
# Email/Password Auth (always available)
# (phx.gen.auth handles this)

# OIDC Configuration (optional)
OIDC_ENABLED=true

# Google OAuth
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret

# GitHub OAuth
GITHUB_CLIENT_ID=your-github-client-id
GITHUB_CLIENT_SECRET=your-github-client-secret

# Keycloak / Generic OIDC
KEYCLOAK_CLIENT_ID=your-keycloak-client-id
KEYCLOAK_CLIENT_SECRET=your-keycloak-client-secret
KEYCLOAK_REALM_URL=https://your-keycloak-instance.com/realms/your-realm
```

## 1.6: Customize After Generation

Add to user migration (in the newly created migration file):
- `add :preferences, :map` (JSON field for UI settings)
- `add :api_token, :binary` (for API auth)
- `add :timezone, :string, default: "UTC"`

Update `lib/fuzzy_rss/accounts/user.ex` schema with new fields:

```elixir
defmodule FuzzyRss.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime

    # New fields
    field :preferences, :map, default: %{}
    field :api_token, :binary
    field :timezone, :string, default: "UTC"

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :timezone])
    |> validate_email()
    |> validate_password()
  end

  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      changeset -> add_error(changeset, :email, "did not change")
    end
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password()
  end

  # ... validation functions ...
end
```

## Completion Checklist

### Required
- [ ] Updated `mix.exs` with all three database adapters
- [ ] Created/updated `config/config.exs` with default configuration
- [ ] Created `config/runtime.exs` with adapter selection logic
- [ ] Ran `mix deps.get` successfully
- [ ] Ran `mix phx.gen.auth Accounts User users`
- [ ] Added new fields to user migration
- [ ] Updated `lib/fuzzy_rss/accounts/user.ex` with new fields
- [ ] Verified migrations run: `mix ecto.setup` (or with DATABASE_ADAPTER env var)
- [ ] Can start server: `mix phx.server` (or with DATABASE_ADAPTER env var)

### Optional - OIDC Support (Ueberauth)
- [ ] Added `:ueberauth` and `:ueberauth_oidc` dependencies to `mix.exs`
- [ ] Configured Ueberauth and OIDC providers in `config/config.exs`
- [ ] Created `user_identities` migration
- [ ] Updated User schema with `:identities` relationship
- [ ] Created `lib/fuzzy_rss/accounts/user_identity.ex` schema
- [ ] Created `lib/fuzzy_rss/accounts/oidc.ex` context module
- [ ] Created `lib/fuzzy_rss_web/controllers/auth_controller.ex`
- [ ] Created `lib/fuzzy_rss_web/views/auth_view.ex`
- [ ] Added Ueberauth routes to router
- [ ] Set OIDC environment variables (or keep OIDC_ENABLED=false to skip)
- [ ] Tested OIDC login with configured provider

## Testing the Setup

```bash
# Start development server with default (SQLite)
mix phx.server

# Visit http://localhost:4000 and create an account

# To use a different database in development:
# PostgreSQL: DATABASE_ADAPTER=postgresql mix phx.server
# MySQL: DATABASE_ADAPTER=mysql mix phx.server
```

## Next Steps

Proceed to [Phase 2: Database Schema](PHASE_2_DATABASE_SCHEMA.md) to create the core data model for feeds, entries, folders, and subscriptions.
