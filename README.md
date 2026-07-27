# BMA Digital Project Infrastructure

This directory is the canonical Docker workflow for the BMA Digital Project.

The application and database run in separate Compose stacks:

```text
Application stack                 Database stack
------------------                --------------
Nginx                             PostgreSQL
Frontend
Backend
```

The legacy files `frontend/docker-compose.yml` and `backend/docker-compose.yml`
are temporarily retained for rollback and transition purposes. They are
deprecated, excluded from CI, and must not be used for production deployment.

## Prerequisites

- Docker Desktop on Windows/macOS, or Docker Engine with Compose on Linux.
- The Docker daemon is running.
- Commands below are run from this directory:

```bash
cd infrastructure
```

Never commit real environment files, passwords, tokens, TLS keys, or database
backups. Do not use `docker compose down -v` unless deleting local data is
intentional.

## PowerShell Copy/Paste Commands

Use this section when running Docker on Windows PowerShell. Every command is a
single line, so it can be copied and pasted directly. Do not copy the `\`
characters from the Linux/macOS examples into PowerShell; `\` is a Bash line
continuation character and is not valid PowerShell syntax.

Run from the `infrastructure` directory:

```powershell
Set-Location D:\test-fullstack\bangkok\infrastructure
```

### First-time local development

```powershell
Copy-Item .env.db.dev.example .env.db.dev
Copy-Item .env.app.dev.example .env.app.dev
docker compose --env-file .env.db.dev -f compose.db.dev.yml config --quiet
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml config --quiet
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.db.dev -f compose.db.dev.yml ps
docker compose --env-file .env.db.dev -f compose.db.dev.yml exec postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml run --rm backend bun run db:migrate
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml run --rm backend bun run db:seed:required
```

### Start existing local data

```powershell
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d
```

Use `--build` when source code or a Dockerfile changed:

```powershell
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
```

### Stop without deleting data

```powershell
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml down
docker compose --env-file .env.db.dev -f compose.db.dev.yml down
```

### Local production-like staging test

```powershell
Copy-Item env/app.staging.example env/app.staging.local
Copy-Item env/db.staging.example env/db.staging.local
docker compose --env-file env/db.staging.local -f compose.db.staging.yml config --quiet
docker compose --env-file env/app.staging.local -f compose.app.staging.yml -f compose.staging-local.override.yml config --quiet
docker compose --env-file env/db.staging.local -f compose.db.staging.yml up -d
docker compose --env-file env/app.staging.local -f compose.app.staging.yml -f compose.staging-local.override.yml up -d
Invoke-WebRequest http://localhost:8088/health/live -UseBasicParsing
Invoke-WebRequest http://localhost:8088/health/ready -UseBasicParsing
```

The staging-local files are ignored by Git and must contain disposable local
values only.

## 1. Local Development with Docker Desktop

This is the normal development workflow for Windows and macOS. PostgreSQL is
published only on the local machine at port `55432`; the backend connects to it
through `host.docker.internal`.

### First-time setup

Create local environment files:

PowerShell:

```powershell
Copy-Item .env.db.dev.example .env.db.dev
Copy-Item .env.app.dev.example .env.app.dev
```

Linux/macOS:

```bash
cp .env.db.dev.example .env.db.dev
cp .env.app.dev.example .env.app.dev
chmod 600 .env.db.dev .env.app.dev
```

Update both files:

1. Set `POSTGRES_PASSWORD` in `.env.db.dev`.
2. Use the same password in `.env.app.dev` inside `DATABASE_URL`.
3. Set `JWT_SECRET` to at least 32 characters.
4. Keep `APP_HTTP_PORT=8080`, or change it to an unused port such as `8088`.
5. If the port changes, update `PUBLIC_API_URL` to match it.

Example local URLs:

```env
APP_HTTP_PORT=8080
PUBLIC_API_URL=http://localhost:8080/api/v1
DATABASE_URL=postgresql://bma_app:PASSWORD@host.docker.internal:55432/bma_db
```

### Validate and start the database

Every database command must explicitly load `.env.db.dev`:

```bash
docker compose \
  --env-file .env.db.dev \
  -f compose.db.dev.yml \
  config --quiet

docker compose \
  --env-file .env.db.dev \
  -f compose.db.dev.yml \
  up -d

docker compose \
  --env-file .env.db.dev \
  -f compose.db.dev.yml \
  ps

docker compose \
  --env-file .env.db.dev \
  -f compose.db.dev.yml \
  exec postgres \
  sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

### Start the application

```bash
docker compose \
  --env-file .env.app.dev \
  -f compose.app.dev.yml \
  -f compose.desktop.override.yml \
  up -d --build
```

Open:

```text
http://localhost:8080
```

If `APP_HTTP_PORT=8088`, open `http://localhost:8088` instead.

### First-time migration and required seed

The application container does not migrate or seed automatically. Run these
commands once for a new database:

```bash
docker compose \
  --env-file .env.app.dev \
  -f compose.app.dev.yml \
  -f compose.desktop.override.yml \
  run --rm backend bun run db:migrate

docker compose \
  --env-file .env.app.dev \
  -f compose.app.dev.yml \
  -f compose.desktop.override.yml \
  run --rm backend bun run db:seed:required
```

For a disposable development database only, add demo data:

```bash
docker compose \
  --env-file .env.app.dev \
  -f compose.app.dev.yml \
  -f compose.desktop.override.yml \
  run --rm backend bun run db:seed:demo
```

Do not run the demo seed against data that must be preserved.

## 2. Restart an Existing Development Environment

Use this when `.env.db.dev`, `.env.app.dev`, and Docker volumes already exist.

Start PostgreSQL:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
```

Start the application without rebuilding:

```bash
docker compose \
  --env-file .env.app.dev \
  -f compose.app.dev.yml \
  -f compose.desktop.override.yml \
  up -d
```

Rebuild after source or Dockerfile changes:

```bash
docker compose \
  --env-file .env.app.dev \
  -f compose.app.dev.yml \
  -f compose.desktop.override.yml \
  up -d --build
```

Run `db:migrate` only when new migration files exist. Do not run migrations on
every normal restart.

## 3. Local Linux Docker Profile

Native Linux should use the shared Docker network instead of assuming that
`host.docker.internal` exists:

```bash
docker network create bma_private 2>/dev/null || true
```

Create the Linux application environment:

```bash
cp .env.app.dev.linux.example .env.app.dev.linux
```

Ensure its `DATABASE_URL` uses the PostgreSQL service name:

```env
DATABASE_URL=postgresql://bma_app:PASSWORD@postgres:5432/bma_db
```

Start the two stacks:

```bash
docker compose \
  --env-file .env.db.dev \
  -f compose.db.dev.yml \
  -f compose.db.linux.override.yml \
  up -d

docker compose \
  --env-file .env.app.dev.linux \
  -f compose.app.dev.yml \
  -f compose.linux.override.yml \
  up -d --build
```

Run migration and required seed using the Linux application configuration:

```bash
docker compose \
  --env-file .env.app.dev.linux \
  -f compose.app.dev.yml \
  -f compose.linux.override.yml \
  run --rm backend bun run db:migrate

docker compose \
  --env-file .env.app.dev.linux \
  -f compose.app.dev.yml \
  -f compose.linux.override.yml \
  run --rm backend bun run db:seed:required
```

## 4. Local Production-like Staging Test

This uses production-style images and configuration, but remains local and
disposable. It is not a real staging or production deployment.

Create ignored local files:

```powershell
Copy-Item env/app.staging.example env/app.staging.local
Copy-Item env/db.staging.example env/db.staging.local
```

Use fake local credentials and local image names/tags in those files. Validate:

```bash
docker compose \
  --env-file env/db.staging.local \
  -f compose.db.staging.yml \
  config --quiet

docker compose \
  --env-file env/app.staging.local \
  -f compose.app.staging.yml \
  -f compose.staging-local.override.yml \
  config --quiet
```

Start the database first:

```bash
docker compose \
  --env-file env/db.staging.local \
  -f compose.db.staging.yml \
  up -d
```

Start the application stack:

```bash
docker compose \
  --env-file env/app.staging.local \
  -f compose.app.staging.yml \
  -f compose.staging-local.override.yml \
  up -d
```

The local staging override normally uses `http://localhost:8088`.

Run migration and required seed only against disposable local data:

```bash
docker compose \
  --env-file env/app.staging.local \
  -f compose.app.staging.yml \
  -f compose.staging-local.override.yml \
  run --rm backend bun run db:migrate

docker compose \
  --env-file env/app.staging.local \
  -f compose.app.staging.yml \
  -f compose.staging-local.override.yml \
  run --rm backend bun run db:seed:required
```

Check the local staging stack:

```powershell
Invoke-WebRequest http://localhost:8088/health/live -UseBasicParsing
Invoke-WebRequest http://localhost:8088/health/ready -UseBasicParsing
Invoke-WebRequest http://localhost:8088/openapi-v1.json -UseBasicParsing
```

For the complete local validation procedure, see
[`docs/local-runtime-validation.md`](docs/local-runtime-validation.md).

## 5. Real Staging or Production Deployment

The real deployment uses two VMs:

```text
Application VM: Nginx, Frontend, Backend
Database VM:    PostgreSQL
```

The database stack must be deployed separately on the Database VM. The
application stack must never include PostgreSQL.

### Database VM

Copy `env/db.vm2.staging.example` or `env/db.staging.example` to a protected
environment file on the Database VM. Replace all placeholders with real
staging values. Set `DATABASE_BIND_ADDRESS` to the Database VM private IP and
allow port 5432 only from the Application VM firewall address.

Validate and start PostgreSQL:

```bash
docker compose \
  --env-file /opt/bma/env/db.staging \
  -f /opt/bma/infrastructure/compose.db.staging.yml \
  config --quiet

docker compose \
  --env-file /opt/bma/env/db.staging \
  -f /opt/bma/infrastructure/compose.db.staging.yml \
  up -d

docker compose \
  --env-file /opt/bma/env/db.staging \
  -f /opt/bma/infrastructure/compose.db.staging.yml \
  ps
```

Create the dedicated backup role and run it twice to verify idempotency:

```bash
node /opt/bma/infrastructure/ensure-backup-role.mjs \
  --env-file /opt/bma/env/db.staging \
  --compose-file /opt/bma/infrastructure/compose.db.staging.yml
```

### Application VM

Install the protected `env/app.staging` file. It must use the Database VM
private address in `DATABASE_URL`, for example:

```env
DATABASE_URL=postgresql://bma_app:PASSWORD@192.168.1.249:5432/bma_db
PUBLIC_API_URL=https://staging.example.com/api/v1
COOKIE_SECURE=true
```

Pull immutable image versions and validate the Compose configuration:

```bash
docker compose \
  --env-file /opt/bma/env/app.staging \
  -f /opt/bma/infrastructure/compose.app.staging.yml \
  config --quiet

docker compose \
  --env-file /opt/bma/env/app.staging \
  -f /opt/bma/infrastructure/compose.app.staging.yml \
  pull
```

Before starting the new application version, create a database backup. Then
run the migration as a one-off Backend container:

```bash
docker compose \
  --env-file /opt/bma/env/app.staging \
  -f /opt/bma/infrastructure/compose.app.staging.yml \
  run --rm backend bun run db:migrate
```

Run `db:seed:required` only when the release adds required reference data.
Never run `db:seed:demo` on staging or production.

Start the application:

```bash
docker compose \
  --env-file /opt/bma/env/app.staging \
  -f /opt/bma/infrastructure/compose.app.staging.yml \
  up -d
```

Verify `/health/live`, `/health/ready`, `/openapi-v1.json`, `/docs/`, and the
browser application before declaring the deployment successful. See
[`docs/staging-runbook.md`](docs/staging-runbook.md) for the full staging gate.

Production deployment must use approved secret storage, TLS, firewall rules,
immutable image versions, external backups, and a reviewed rollback plan.

## 6. Health Checks and Useful Commands

Local development URLs are usually:

```text
Application: http://localhost:8080
Live:        http://localhost:8080/health/live
Ready:       http://localhost:8080/health/ready
OpenAPI:     http://localhost:8080/openapi-v1.json
Docs:        http://localhost:8080/docs/
```

Replace `8080` with `8088` when using the local staging override.

View application logs:

```bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml logs -f backend
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml logs -f frontend
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml logs -f nginx
```

View database logs:

```bash
docker compose \
  --env-file .env.db.dev \
  -f compose.db.dev.yml \
  logs -f postgres
```

Check the database from inside its container:

```bash
docker compose \
  --env-file .env.db.dev \
  -f compose.db.dev.yml \
  exec postgres \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT current_database(), current_user;"'
```

## 7. Stop, Restart, and Remove Containers

Stop services while preserving containers and volumes:

```bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml stop
docker compose --env-file .env.db.dev -f compose.db.dev.yml stop
```

Start them again:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml start
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml start
```

Remove containers and networks while preserving volumes:

```bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml down
docker compose --env-file .env.db.dev -f compose.db.dev.yml down
```

Start again later with:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
```

Do not use `down -v` on a database or upload stack unless the data is
disposable and deletion is intentional.

## 8. Backups

A Docker volume is persistence, not a backup. Back up PostgreSQL and uploaded
files separately.

Local database backup:

```bash
node scripts/backup-db.mjs
```

The script explicitly loads `.env.db.dev` and writes a custom-format dump to
`backups/`. Do not commit that directory.

Real staging backup:

```bash
node /opt/bma/infrastructure/backup-staging-db.mjs \
  --env-file /opt/bma/env/db.staging \
  --compose-file /opt/bma/infrastructure/compose.db.staging.yml \
  --output-dir /opt/bma/backups/database
```

Copy backups outside the Database VM and test restores in a disposable
database. Upload backups require the separate upload backup script.

## 9. Troubleshooting

### Backend is unhealthy

Check the backend logs. A common cause is a short JWT secret. Set
`JWT_SECRET` to at least 32 characters and recreate the application stack:

```bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
```

### Port 8080 is already in use

Set this in `.env.app.dev`:

```env
APP_HTTP_PORT=8088
PUBLIC_API_URL=http://localhost:8088/api/v1
```

Then recreate Nginx:

```bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --force-recreate nginx
```

### Database commands fail with “no configuration file provided”

Always provide both the environment file and Compose file:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml ps
```

### Backend cannot connect to PostgreSQL on Docker Desktop

Confirm that PostgreSQL is healthy and that the backend uses:

```text
postgresql://USER:PASSWORD@host.docker.internal:55432/DATABASE
```

On native Linux, use the Linux network override and the `postgres` service name
instead. Do not assume Docker Desktop networking works identically on Linux.

### Next.js Server Actions report a forwarded-host mismatch

Use one public origin consistently, such as `http://localhost:8088`. Ensure
Nginx forwards the incoming host and port:

```nginx
proxy_set_header Host $http_host;
proxy_set_header X-Forwarded-Host $http_host;
```

After changing Nginx configuration, recreate only Nginx and retry the request.

## Canonical Workflow Summary

For normal local development with existing data:

```bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
```

For production-like deployment:

1. Start and verify PostgreSQL on the separate Database VM.
2. Create a pre-migration backup.
3. Pull immutable application images on the Application VM.
4. Run `db:migrate` as a one-off Backend container.
5. Run required seed only when needed.
6. Start Backend, Frontend, and Nginx.
7. Verify health, authentication, uploads, and application smoke tests.

Do not run `db:generate` during deployment, do not run demo seed in production,
and do not assume application rollback reverses a database migration.
