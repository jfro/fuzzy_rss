# FuzzyRss

My attempt at an RSS aggregator more in line with what I'd like to see in one.

![FuzzyRss Screenshot](docs/main_screenshot.png)

## Features

- Lightweight, fast, and easy to use
- Import/export feeds (OPML) & starred articles (JSON)
- Dual reader layout options, vertical or 3 pane horizontal
- MySQL/MariaDB, PostgreSQL, & SQLite support for DB

## Getting Started

Docker image coming soon. Otherwise requires Elixir 1.19 & Erlang OTP 28 installed.

## Configuration

All configuration is done via environment variables. See `.env.example` for a complete list.

### Server

```bash
PHX_HOST=example.com               # Hostname for URLs (required for production)
PORT=4000                          # Internal port to listen on (default: 4000)
SECRET_KEY_BASE=...                # Secret key (generate with: mix phx.gen.secret)

# Optional (for TLS-terminating proxy setups)
PHX_URL_SCHEME=https               # URL scheme (default: https)
PHX_URL_PORT=443                   # External port (default: 443)
CHECK_ORIGIN=                      # WebSocket origin check (default: matches PHX_HOST)
```

### Database

```bash
DATABASE_ADAPTER=sqlite            # sqlite, postgresql, or mysql (default: sqlite)

# SQLite (default)
SQLITE_DATABASE_URL=/path/to/db.db

# PostgreSQL
POSTGRES_DATABASE_URL=ecto://user:pass@host/dbname
# or use DATABASE_URL for auto-detection
DATABASE_URL=ecto://user:pass@host/dbname

# MySQL
MYSQL_DATABASE_URL=mysql://user:pass@host/dbname
# or use DATABASE_URL for auto-detection
DATABASE_URL=mysql://user:pass@host/dbname

# Optional
POOL_SIZE=10                       # Connection pool size (default: 10)
DATABASE_SSL=false                 # Enable SSL for database (default: false)
```

### Mail

```bash
MAIL_ADAPTER=local                 # local, smtp, mailgun, sendgrid, postmark, gmail

# SMTP (any SMTP provider)
MAIL_SMTP_RELAY=smtp.example.com
MAIL_SMTP_USERNAME=username
MAIL_SMTP_PASSWORD=password
MAIL_SMTP_PORT=587                 # Optional (default: 587)
MAIL_SMTP_TLS=always              # Optional: always, never, if_available
MAIL_SMTP_SSL=false               # Optional: use SSL instead of TLS
MAIL_SMTP_AUTH=always             # Optional: always, never, if_available
MAIL_SMTP_RETRIES=1               # Optional (default: 1)

# Mailgun
MAIL_MAILGUN_API_KEY=key-xxx
MAIL_MAILGUN_DOMAIN=mg.example.com
MAIL_MAILGUN_BASE_URL=...         # Optional: for EU region

# SendGrid
MAIL_SENDGRID_API_KEY=SG.xxx

# Postmark
MAIL_POSTMARK_API_KEY=xxx

# Gmail API (OAuth2)
MAIL_GMAIL_ACCESS_TOKEN=ya29.xxx
```

### Authentication

```bash
DISABLE_MAGIC_LINK=false           # Disable magic link auth (default: false)
SIGNUP_ENABLED=true                # Allow signups (default: true, false = one-time signup)

# OIDC (optional)
OIDC_ENABLED=false
OIDC_CLIENT_ID=...
OIDC_CLIENT_SECRET=...
OIDC_DISCOVERY_URL=...
``` 

## TODO

- OIDC support
- APIs
- Mobile/PWA support
