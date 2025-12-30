# Multi-Database Docker Deployment

Guide for deploying FuzzyRSS with PostgreSQL, MySQL, or SQLite backends.

## Overview

A single Docker image supports all three databases. The adapter is selected at runtime via the `DATABASE_ADAPTER` environment variable.

## Docker Image

### Dockerfile

Create `Dockerfile` in project root:

```dockerfile
FROM hexpm/elixir:1.15.7-erlang-26.1.2-alpine-3.18.4

RUN apk add --no-cache build-base npm git curl

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN MIX_ENV=prod mix deps.compile

COPY assets assets
RUN npm --prefix ./assets ci --progress=false --no-audit --loglevel=error
RUN npm run --prefix ./assets deploy

COPY priv priv
COPY lib lib
COPY config config

RUN MIX_ENV=prod mix compile
RUN MIX_ENV=prod mix assets.deploy

COPY rel rel
RUN MIX_ENV=prod mix release

EXPOSE 4000

# Pass DATABASE_ADAPTER via ENV when running
CMD ["_build/prod/rel/fuzzy_rss/bin/fuzzy_rss", "start"]
```

### Build Image

```bash
docker build -t fuzzyrss:latest .
```

## Docker Compose Configurations

### PostgreSQL (Recommended)

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  db:
    image: postgres:16-alpine
    container_name: fuzzyrss-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: fuzzy_rss
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    build: .
    container_name: fuzzyrss-app
    ports:
      - "4000:4000"
    environment:
      DATABASE_ADAPTER: postgresql
      DATABASE_URL: ecto://postgres:postgres@db:5432/fuzzy_rss
      SECRET_KEY_BASE: changeme_please_generate_with_mix_phx_gen_secret
      PORT: 4000
      MIX_ENV: prod
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - ./:/app

volumes:
  postgres_data:
```

Run:

```bash
docker-compose up
```

### MySQL

Create `docker-compose.mysql.yml`:

```yaml
version: '3.8'

services:
  db:
    image: mysql:8-alpine
    container_name: fuzzyrss-mysql
    environment:
      MYSQL_ROOT_PASSWORD: password
      MYSQL_DATABASE: fuzzy_rss
      MYSQL_USER: fuzzy_rss
      MYSQL_PASSWORD: password
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    build: .
    container_name: fuzzyrss-app
    ports:
      - "4000:4000"
    environment:
      DATABASE_ADAPTER: mysql
      DATABASE_URL: mysql://fuzzy_rss:password@db:3306/fuzzy_rss
      SECRET_KEY_BASE: changeme_please_generate_with_mix_phx_gen_secret
      PORT: 4000
      MIX_ENV: prod
    depends_on:
      db:
        condition: service_healthy

volumes:
  mysql_data:
```

Run:

```bash
docker-compose -f docker-compose.mysql.yml up
```

### SQLite

Create `docker-compose.sqlite.yml`:

```yaml
version: '3.8'

services:
  app:
    build: .
    container_name: fuzzyrss-app
    ports:
      - "4000:4000"
    environment:
      DATABASE_ADAPTER: sqlite
      DATABASE_URL: sqlite3:/app/fuzzy_rss.db
      SECRET_KEY_BASE: changeme_please_generate_with_mix_phx_gen_secret
      PORT: 4000
      MIX_ENV: prod
    volumes:
      - ./:/app
      - app_data:/app/data
    command: |
      sh -c "
        mix ecto.create &&
        mix ecto.migrate &&
        _build/prod/rel/fuzzy_rss/bin/fuzzy_rss start
      "

volumes:
  app_data:
```

Run:

```bash
docker-compose -f docker-compose.sqlite.yml up
```

## Local Development

### PostgreSQL (Default)

```bash
DATABASE_ADAPTER=postgresql mix phx.server
```

### MySQL

```bash
DATABASE_ADAPTER=mysql mix phx.server
```

### SQLite

```bash
DATABASE_ADAPTER=sqlite mix phx.server
```

## Environment Variables

### Required

- `DATABASE_ADAPTER` - `postgresql`, `mysql`, or `sqlite` (default: `postgresql`)
- `SECRET_KEY_BASE` - Phoenix secret (generate with `mix phx.gen.secret`)
- `PORT` - Server port (default: `4000`)

### Optional

- `DATABASE_URL` - Database connection string (auto-generated if not provided)
- `POOL_SIZE` - Database connection pool size (default: `10`)
- `DATABASE_SSL` - Enable SSL for database (default: `false`)
- `HOST` - Application hostname for production
- `MIX_ENV` - Environment (`dev`, `test`, `prod`)

## Secrets Management

### Generate Secret Key

```bash
mix phx.gen.secret
```

Use the output for `SECRET_KEY_BASE` in environment variables.

### Secure Configuration

Production deployment:

```bash
export DATABASE_ADAPTER=postgresql
export DATABASE_URL=postgres://user:pass@host:5432/db
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export PORT=4000

docker-compose up
```

Or use `.env` file:

```bash
# .env (DO NOT COMMIT TO GIT!)
DATABASE_ADAPTER=postgresql
DATABASE_URL=postgres://user:pass@host:5432/db
SECRET_KEY_BASE=your_secret_here
PORT=4000
```

Load with:

```bash
docker-compose --env-file .env up
```

## Database-Specific Considerations

### PostgreSQL (Recommended for Production)

**Advantages:**
- Best full-text search support
- Excellent array field support
- JSONB for flexible data
- Best for clustering/replication
- Excellent performance at scale
- Great tooling ecosystem

**Recommended Settings:**
```yaml
environment:
  POSTGRES_INITDB_ARGS: "-c shared_buffers=256MB -c effective_cache_size=1GB"
  POSTGRES_HOST_AUTH_METHOD: "md5"
```

### MySQL

**Advantages:**
- Good FULLTEXT search
- Wide hosting support
- Good for moderate scale
- Familiar to many teams

**Limitations:**
- FULLTEXT limitations compared to PostgreSQL
- Array field emulation with JSON

**Recommended Settings:**
```yaml
environment:
  MYSQL_LOWER_CASE_TABLE_NAMES: "1"
  MYSQL_DEFAULT_STORAGE_ENGINE: "InnoDB"
```

### SQLite

**Advantages:**
- Perfect for single-user deployments
- No server needed
- File-based database
- Simple to backup

**Limitations:**
- Limited full-text search (basic LIKE queries)
- Array fields require JSON encoding
- Not ideal for high concurrency
- Cannot be accessed from multiple containers easily

**Best For:**
- Development/testing
- Small single-user instances
- Offline-first applications

## Production Deployment

### Fly.io

```bash
flyctl launch

# Set environment variables
flyctl secrets set \
  DATABASE_ADAPTER=postgresql \
  DATABASE_URL=postgres://... \
  SECRET_KEY_BASE=...

flyctl deploy
```

### AWS ECS

```bash
# Create ECR repository
aws ecr create-repository --repository-name fuzzyrss

# Build and push
docker tag fuzzyrss:latest ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/fuzzyrss:latest
docker push ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/fuzzyrss:latest

# Create ECS task definition (reference image)
# Create ECS service
# Configure RDS database
```

### Render

```bash
# Connect GitHub repo to Render
# Create Web Service
# Configure environment variables
# Deploy
```

## Monitoring & Logs

### View Logs

```bash
# Docker Compose
docker-compose logs -f app

# Kubernetes
kubectl logs -f deployment/fuzzyrss-app

# Fly.io
flyctl logs
```

### Health Check

```bash
curl http://localhost:4000/health
```

Expected response:

```json
{
  "status": "ok",
  "timestamp": "2025-12-29T12:00:00Z"
}
```

## Troubleshooting

### Database Connection Issues

```bash
# Test database connection
docker exec fuzzyrss-app mix ecto.dump

# Check environment variables
docker exec fuzzyrss-app env | grep DATABASE

# View logs
docker-compose logs db
docker-compose logs app
```

### Migration Errors

```bash
# Run migrations manually
docker exec fuzzyrss-app mix ecto.migrate

# Rollback if needed
docker exec fuzzyrss-app mix ecto.rollback
```

### Permission Issues (SQLite)

```bash
# Ensure volume permissions
docker exec fuzzyrss-app chmod 666 /app/fuzzy_rss.db
```

## Backup & Recovery

### PostgreSQL

```bash
# Backup
docker exec fuzzyrss-db pg_dump -U postgres fuzzy_rss > backup.sql

# Restore
docker exec -i fuzzyrss-db psql -U postgres fuzzy_rss < backup.sql
```

### MySQL

```bash
# Backup
docker exec fuzzyrss-db mysqldump -u fuzzy_rss -ppassword fuzzy_rss > backup.sql

# Restore
docker exec -i fuzzyrss-db mysql -u fuzzy_rss -ppassword fuzzy_rss < backup.sql
```

### SQLite

```bash
# Backup
docker exec fuzzyrss-app cp /app/fuzzy_rss.db /app/fuzzy_rss.db.backup

# Download from volume
docker cp fuzzyrss-app:/app/fuzzy_rss.db ./fuzzy_rss.db
```

## Performance Tuning

### Increase Connection Pool

```yaml
environment:
  POOL_SIZE: "20"
```

### Optimize Database

PostgreSQL:

```sql
VACUUM ANALYZE;
REINDEX DATABASE fuzzy_rss;
```

MySQL:

```sql
OPTIMIZE TABLE feeds, entries, subscriptions;
ANALYZE TABLE feeds, entries, subscriptions;
```

SQLite:

```sql
VACUUM;
ANALYZE;
PRAGMA optimize;
```

## Next Steps

- Monitor application performance
- Set up automated backups
- Configure log aggregation
- Set up alerts for errors
- Optimize queries based on metrics
