# BMA Digital Project — Dev Run Guide

The `infrastructure/` directory is the canonical workflow for running the application in a production-like development environment. It uses two separate Compose stacks:

~~~text
Database stack
└── PostgreSQL

Application stack
├── Nginx
├── Frontend
└── Backend
~~~

The `frontend/docker-compose.yml` and `backend/docker-compose.yml` files are temporary legacy transition paths. They are not the primary workflow and must not be used for production.

## Before You Start

You need Docker Desktop on Windows/macOS, or Docker Engine with the Compose plugin on Linux. The Docker daemon must be running.

Open a terminal in the `infrastructure` directory:

~~~powershell
Set-Location D:\test-fullstack\bangkok\infrastructure
~~~

Important:

- Do not commit `.env.db.dev`, `.env.app.dev`, `.env.app.dev.linux`, or real backup files.
- Database Compose commands must always specify `--env-file .env.db.dev`.
- Do not use `down -v` if you need to preserve PostgreSQL or uploaded files.

## Case 1: Start a New Dev Environment

Use this flow when the environment files do not exist and this machine has not been configured yet.

### 1. Create the environment files

PowerShell:

~~~powershell
Copy-Item .env.db.dev.example .env.db.dev
Copy-Item .env.app.dev.example .env.app.dev
~~~

Linux/macOS:

~~~bash
cp .env.db.dev.example .env.db.dev
cp .env.app.dev.example .env.app.dev
~~~

Update the files as follows:

1. Set `POSTGRES_PASSWORD` in `.env.db.dev`.
2. Use the same password in the `DATABASE_URL` inside `.env.app.dev`.
3. Set `JWT_SECRET` to at least 32 characters.
4. The default `APP_HTTP_PORT` is 8080. Change it to 8088 if port 8080 is already in use.
5. If you change the port, update `PUBLIC_API_URL` as well, for example `http://localhost:8088/api/v1`.

Generate a random JWT secret in PowerShell:

~~~powershell
$bytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
[Convert]::ToHexString($bytes).ToLower()
~~~

Or on Linux/macOS:

~~~bash
openssl rand -hex 32
~~~

Copy the generated value into `JWT_SECRET` without quotation marks.

### 2. Validate the Compose configuration

~~~bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml config
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml config
~~~

### 3. Start PostgreSQL

~~~bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.db.dev -f compose.db.dev.yml ps
docker compose --env-file .env.db.dev -f compose.db.dev.yml exec postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
~~~

Wait until the PostgreSQL service shows `healthy`.

### 4. Start the Application stack

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
~~~

This starts Nginx, Frontend, and Backend. It does not start PostgreSQL and does not run migrations or seeds automatically.

### 5. Run the migration and required seed for the first setup

Run these commands after the Database stack is ready:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml run --rm backend bun run db:migrate
docker compose --env-file .env.app.dev -f compose.app.dev.yml run --rm backend bun run db:seed:required
~~~

The demo seed contains test data only:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml run --rm backend bun run db:seed:demo
~~~

Do not run the demo seed when working with data that must be preserved.

## Case 2: Start with Existing Environment Values and Data

Use this flow when the environment files and named Docker volumes already exist.

### 1. Do not overwrite existing environment files

Do not run the copy commands from Case 1.

Check that the existing files are present:

~~~powershell
Get-ChildItem .env.*
~~~

List only environment variable names without displaying secret values:

~~~powershell
Get-Content .env.db.dev | ForEach-Object { if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=') { $matches[1] } }
Get-Content .env.app.dev | ForEach-Object { if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=') { $matches[1] } }
~~~

Verify that the user, password, and database in `DATABASE_URL` match `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB`.

### 2. Start the existing Database stack

~~~bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.db.dev -f compose.db.dev.yml ps
docker compose --env-file .env.db.dev -f compose.db.dev.yml logs --tail=100 postgres
~~~

The existing named volume, such as `infrastructure_bma_dev_pg_data`, will be reused and existing data will not be deleted.

### 3. Start the existing Application stack

Use this command when the Dockerfile or source code needs to be rebuilt:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
~~~

If no rebuild is needed:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d
~~~

Recreating the Application stack does not delete the PostgreSQL volume and does not change the database schema automatically.

### 4. Run migrations only when new migrations exist

When the release or database schema has changed, run:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml run --rm backend bun run db:migrate
~~~

You do not need to run migrations every time the application starts. You also do not need to run the required seed every time unless new required reference data has been added.

## URLs for Checking the Application

The default value is `APP_HTTP_PORT=8080`:

~~~text
Application: http://localhost:8080
Live health: http://localhost:8080/health/live
Ready health: http://localhost:8080/health/ready
OpenAPI:     http://localhost:8080/openapi-v1.json
Docs:        http://localhost:8080/docs/
API:         http://localhost:8080/api/v1/
~~~

If you use port 8088, replace 8080 with 8088 in all URLs.

PowerShell:

~~~powershell
Invoke-WebRequest http://localhost:8080/health/live
Invoke-WebRequest http://localhost:8080/health/ready
~~~

## Server Actions Behind Nginx

Nginx must preserve the host and port when forwarding requests to Next.js. The
canonical configuration uses the incoming host header:

~~~nginx
proxy_set_header Host $http_host;
proxy_set_header X-Forwarded-Host $http_host;
~~~

This prevents errors such as an origin of `localhost:8088` being compared with
an `x-forwarded-host` value of `localhost`.

Use one public origin consistently during a session, such as:

~~~text
http://localhost:8088
~~~

After changing `nginx/default.conf`, a full Compose shutdown is not required.
Recreate only the Nginx container:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --force-recreate nginx
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml exec nginx nginx -t
~~~

Then hard-refresh the browser before retrying login or registration. A frontend
image rebuild is not required for an Nginx-only configuration change.

## Staging Deployment

The staging artifacts use the production-like two-VM topology and immutable
registry images:

~~~text
Application VM: Nginx, Frontend, Backend
Database VM:    PostgreSQL
~~~

Files:

- `compose.app.staging.yml`
- `compose.db.staging.yml`
- `env/app.staging.example`
- `env/db.staging.example`
- `compose.staging-local.override.yml`
- `env/app.staging.local` (ignored)
- `env/db.staging.local` (ignored)
- `docs/staging-runbook.md`

Follow the complete staging procedure in
[`docs/staging-runbook.md`](docs/staging-runbook.md). The runbook includes
dedicated backup-role setup, expected smoke-test responses, browser private-IP
leakage checks, disposable-environment failure-test rules, and forwarded
host/port verification for Next.js Server Actions.

For local-only validation on Docker Desktop, create the ignored local files
from the examples and use the local override:

~~~powershell
Copy-Item env/app.staging.example env/app.staging.local
Copy-Item env/db.staging.example env/db.staging.local
docker compose --env-file env/db.staging.local -f compose.db.staging.yml config
docker compose --env-file env/app.staging.local -f compose.app.staging.yml -f compose.staging-local.override.yml config
~~~

The local override uses HTTP on `http://localhost:8080` and PostgreSQL on
`127.0.0.1:55432`. It is not a staging or production deployment file.

## Native Linux

Create the private Docker network once:

~~~bash
docker network create bma_private
~~~

Create the Linux environment file:

~~~bash
cp .env.app.dev.linux.example .env.app.dev.linux
~~~

Ensure that `DATABASE_URL` points to `postgres:5432`, then start both stacks:

~~~bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml -f compose.db.linux.override.yml up -d
docker compose --env-file .env.app.dev.linux -f compose.app.dev.yml -f compose.linux.override.yml up -d --build
~~~

Run the migration and required seed:

~~~bash
docker compose --env-file .env.app.dev.linux -f compose.app.dev.yml -f compose.linux.override.yml run --rm backend bun run db:migrate
docker compose --env-file .env.app.dev.linux -f compose.app.dev.yml -f compose.linux.override.yml run --rm backend bun run db:seed:required
~~~

## Stop and Start Again

Stop the services while preserving containers and volumes:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml stop
docker compose --env-file .env.db.dev -f compose.db.dev.yml stop
~~~

Start the existing containers again:

~~~bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml start
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml start
~~~

Remove containers and networks while preserving volumes:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml down
docker compose --env-file .env.db.dev -f compose.db.dev.yml down
~~~

Start the stacks again with a fresh application build:

~~~bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
~~~

Do not use `down -v` unless you have confirmed that the development data can be deleted. This command may remove PostgreSQL and upload volumes.

## Helper Scripts

The helper scripts pass the correct `--env-file` to Docker Compose and work in PowerShell, Command Prompt, and POSIX shells:

~~~bash
node scripts/compose-db.mjs up -d
node scripts/compose-app.mjs up -d --build
node scripts/backup-db.mjs
node scripts/restore-db.mjs backups/example.dump
~~~

For Native Linux, add `--linux`:

~~~bash
node scripts/compose-db.mjs --linux up -d
node scripts/compose-app.mjs --linux up -d --build
~~~

## Troubleshooting

### Backend is unhealthy because of JWT_SECRET

Update `JWT_SECRET` in `.env.app.dev` to at least 32 characters, then recreate the Application stack:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
~~~

### Port 8080 is already in use

Set these values in `.env.app.dev`:

~~~env
APP_HTTP_PORT=8088
PUBLIC_API_URL=http://localhost:8088/api/v1
~~~

Then run:

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d
~~~

### View logs

~~~bash
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml logs -f backend
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml logs -f frontend
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml logs -f nginx
docker compose --env-file .env.db.dev -f compose.db.dev.yml logs -f postgres
~~~

### Backend cannot connect to PostgreSQL on Docker Desktop

Confirm that the Database stack is healthy and that `DATABASE_URL` uses this format:

~~~text
postgresql://USER:PASSWORD@host.docker.internal:55432/DATABASE
~~~

Check the port from PowerShell:

~~~powershell
Test-NetConnection localhost -Port 55432
~~~

## Daily Start Summary

Once the environment files and volumes already exist, run:

~~~bash
docker compose --env-file .env.db.dev -f compose.db.dev.yml up -d
docker compose --env-file .env.app.dev -f compose.app.dev.yml -f compose.desktop.override.yml up -d --build
~~~

Then open `http://localhost:8080`, or the port configured in `APP_HTTP_PORT`.
