# BMA Infrastructure Workflow

`infrastructure/` is the canonical local deployment workflow. The existing
frontend and backend Compose files are deprecated transition paths and are not
used by CI or production deployments.

## Docker Desktop

Start PostgreSQL:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
```

Validate the database Compose configuration:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml config
```

Every database-stack operation must keep the same explicit environment file:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml ps
docker compose --env-file .env.db.dev -f compose.db.dev.yml logs
docker compose --env-file .env.db.dev -f compose.db.dev.yml stop
docker compose --env-file .env.db.dev -f compose.db.dev.yml start
docker compose --env-file .env.db.dev -f compose.db.dev.yml restart
docker compose --env-file .env.db.dev -f compose.db.dev.yml down
docker compose --env-file .env.db.dev -f compose.db.dev.yml exec postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

Start the application stack:

```bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
```

The application is available at `http://localhost:8080`.

## Native Linux

Create the shared private network once:

```bash
docker network create bma_private
```

Use `.env.app.dev.linux` with `DATABASE_URL` pointing to `postgres:5432`, then
start both stacks with their Linux overrides:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml -f compose.db.linux.override.yml up -d
docker compose --env-file .env.app.dev.linux -f compose.app.dev.yml -f compose.linux.override.yml up -d --build
```

## Cross-platform helper scripts

The Node.js helpers pass the required Compose environment file explicitly and
work from PowerShell, Command Prompt, and POSIX shells:

```bash
node scripts/compose-db.mjs up -d
node scripts/compose-app.mjs up -d --build
node scripts/backup-db.mjs
node scripts/restore-db.mjs backups/example.dump
```

Add `--linux` to the compose helpers when using the native Linux profile.

## Health and API endpoints

```text
http://localhost:8080/health/live
http://localhost:8080/health/ready
http://localhost:8080/openapi-v1.json
http://localhost:8080/docs/
```

Migrations and required seeds are explicit operations. Application startup does
not run either operation automatically.

Run migrations as a one-off Backend container after the Database stack is ready:

```bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml run --rm backend bun run db:migrate
docker compose --env-file .env.app.dev -f compose.app.dev.yml run --rm backend bun run db:seed:required
```

For native Linux, use the Linux environment and private-network override for
the same one-off commands:

```bash
docker compose --env-file .env.app.dev.linux -f compose.app.dev.yml -f compose.linux.override.yml run --rm backend bun run db:migrate
docker compose --env-file .env.app.dev.linux -f compose.app.dev.yml -f compose.linux.override.yml run --rm backend bun run db:seed:required
```

`db:seed:demo` is development-only and is never part of deployment startup.
