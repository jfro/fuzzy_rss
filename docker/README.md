# Docker Compose Configurations

Quick-start Docker Compose files for different database backends.

## Quick Start

Choose your database and run:

```bash
# PostgreSQL (recommended)
docker compose -f docker/postgres.yml up

# MariaDB
docker compose -f docker/mariadb.yml up

# SQLite (single file database)
docker compose -f docker/sqlite.yml up
```

The app will be available at `http://localhost:4000`

## Configuring Mail

By default, the app uses the local mail adapter which shows a warning banner on the login page. To configure a real mail provider:

### Option 1: Using a .env file (Recommended)

1. Copy the example environment file:
   ```bash
   cp .env.docker.example .env
   ```

2. Edit `.env` and set your mail configuration:
   ```bash
   # Example: Using Mailgun
   MAIL_ADAPTER=mailgun
   MAIL_MAILGUN_API_KEY=key-your-api-key
   MAIL_MAILGUN_DOMAIN=mg.yourdomain.com
   ```

3. Run docker compose (it will automatically load `.env`):
   ```bash
   docker compose -f docker/postgres.yml up
   ```

### Option 2: Using environment variables

Set environment variables before running docker compose:

```bash
export MAIL_ADAPTER=mailgun
export MAIL_MAILGUN_API_KEY=key-your-api-key
export MAIL_MAILGUN_DOMAIN=mg.yourdomain.com

docker compose -f docker/postgres.yml up
```

### Supported Mail Adapters

- **local** - Development only (shows warning banner)
- **smtp** - Any SMTP provider (Gmail, SendGrid via SMTP, etc.)
- **mailgun** - Mailgun HTTP API
- **sendgrid** - SendGrid HTTP API
- **postmark** - Postmark HTTP API
- **gmail** - Gmail OAuth2 API

See `.env.docker.example` for all configuration options.

## Environment Variables

All docker compose files support these environment variables via `.env` file:

```bash
# Server
PHX_HOST=localhost              # Your domain name
PHX_URL_SCHEME=http            # "http" for local, "https" for production
PHX_URL_PORT=4000              # "4000" for local, "443" for production
PORT=4000                       # Internal port the app listens on

# Mail (see .env.docker.example for all options)
MAIL_ADAPTER=mailgun
MAIL_FROM_EMAIL=noreply@yourdomain.com
MAIL_MAILGUN_API_KEY=key-xxx
MAIL_MAILGUN_DOMAIN=mg.example.com
```

### URL Configuration

The URL settings control how links are generated in emails and redirects:

**Local development (default):**
```bash
PHX_HOST=localhost
PHX_URL_SCHEME=http
PHX_URL_PORT=4000
```
Generates URLs like: `http://localhost:4000/users/log-in/abc123`

**Production behind TLS proxy:**
```bash
PHX_HOST=rss.yourdomain.com
PHX_URL_SCHEME=https
PHX_URL_PORT=443
```
Generates URLs like: `https://rss.yourdomain.com/users/log-in/abc123`

## Notes

- Database credentials are hardcoded for development convenience
- Change `SECRET_KEY_BASE` for production (generate with `mix phx.gen.secret`)
- The `.env` file is automatically loaded by `docker compose`
- Don't commit `.env` to version control (it's in `.gitignore`)
- If you set env vars in your shell before running `docker compose up`, they will override values in `.env`
