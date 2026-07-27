# Staging Deployment Runbook

This runbook is for the two-VM staging topology only.

~~~text
Application VM
├── Nginx
├── Frontend
└── Backend

Database VM
└── PostgreSQL
~~~

Production is still blocked until the complete staging and production-readiness gates pass.

## Safety Rules

- Use staging or disposable data only.
- Do not run destructive failure tests against production.
- Do not use \`down -v\` on a database that contains data to preserve.
- Do not run the demo seed on staging unless the environment is explicitly disposable.
- Keep actual environment files outside Git.
- Do not print secrets in shell output or CI logs.
- Database backups must use the dedicated \`bma_backup\` role, not \`bma_app\`.

## Prerequisites

- A private IP for the Application VM.
- A private IP for the Database VM.
- DNS for the staging hostname.
- TLS certificate and private key.
- Registry pull credentials.
- Docker Engine and Compose on both VMs.
- Firewall access from Application VM to Database VM port 5432.

Create the actual environment files:

~~~bash
cp env/app.staging.example env/app.staging
cp env/db.staging.example env/db.staging
chmod 600 env/app.staging env/db.staging
~~~

Replace all placeholder values before starting.

The PostgreSQL password inside \`DATABASE_URL\` must be URL-encoded if it contains reserved URL characters.

## Database VM

Validate the Database Compose configuration:

~~~bash
docker compose --env-file env/db.staging -f compose.db.staging.yml config
~~~

Start PostgreSQL:

~~~bash
docker compose --env-file env/db.staging -f compose.db.staging.yml up -d
docker compose --env-file env/db.staging -f compose.db.staging.yml ps
~~~

The database port is bound to \`DATABASE_BIND_ADDRESS:5432\`. The host firewall must allow that port only from the Application VM private IP.

Create or update the dedicated read-only backup role:

~~~bash
node scripts/ensure-backup-role.mjs --env-file env/db.staging --compose-file compose.db.staging.yml
~~~

Verify the role permissions using a privileged administrative session:

~~~sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolinherit
FROM pg_roles
WHERE rolname IN ('bma_app', 'bma_backup');
~~~

Expected for \`bma_backup\`:

~~~text
rolsuper      = false
rolcreatedb   = false
rolcreaterole = false
rolinherit    = true
~~~

The backup role receives PostgreSQL's \`pg_read_all_data\` role and must not be used by the application.

## Application VM

Place the TLS files in:

~~~text
infrastructure/certs/fullchain.pem
infrastructure/certs/privkey.pem
~~~

Protect the private key:

~~~bash
chmod 600 certs/privkey.pem
~~~

Validate the Application Compose configuration:

~~~bash
docker compose --env-file env/app.staging -f compose.app.staging.yml config
~~~

Pull and start the application stack:

~~~bash
docker compose --env-file env/app.staging -f compose.app.staging.yml pull
docker compose --env-file env/app.staging -f compose.app.staging.yml up -d
~~~

The staging stack contains only Nginx, Frontend, and Backend.

## Migration and Required Seed

Run migrations as an explicit one-off Backend container:

~~~bash
docker compose --env-file env/app.staging -f compose.app.staging.yml run --rm backend bun run db:migrate
~~~

Run required seed only when needed:

~~~bash
docker compose --env-file env/app.staging -f compose.app.staging.yml run --rm backend bun run db:seed:required
~~~

Run the required seed twice during initial staging validation and verify that no duplicates are created.

Never run \`db:generate\` on the staging or production server.

Never run \`db:seed:demo\` automatically.

## Expected Smoke-Test Responses

Run from the Application VM or an approved test host.

Linux/macOS:

~~~bash
STAGING_BASE_URL=https://staging.example.com node scripts/smoke-test-staging.mjs
~~~

PowerShell:

~~~powershell
$env:STAGING_BASE_URL = "https://staging.example.com"
node scripts/smoke-test-staging.mjs
~~~

Expected results:

| Endpoint | Expected status | Expected content |
|---|---:|---|
| \`/\` | 200 | \`text/html\` |
| \`/health/live\` | 200 | \`application/json\` |
| \`/health/ready\` | 200 | \`application/json\` |
| \`/openapi-v1.json\` | 200 | \`application/json\` |
| \`/docs/\` | 200 | \`text/html\` |

The smoke test also downloads Next.js script assets and fails if browser bundles contain:

- \`host.docker.internal\`
- PostgreSQL URLs
- Port \`5432\`
- Backend port \`8081\`
- RFC1918 private IPv4 addresses

## Forwarded Host and Port Verification

The staging Nginx configuration must use:

~~~nginx
proxy_set_header Host $http_host;
proxy_set_header X-Forwarded-Host $http_host;
proxy_set_header X-Forwarded-Proto $scheme;
~~~

Verify the loaded configuration:

~~~bash
docker compose --env-file env/app.staging -f compose.app.staging.yml exec nginx nginx -T
~~~

Then test a real Server Action through the staging origin, for example login or registration.

Expected result:

- The request succeeds.
- No \`Invalid Server Actions request\` error appears.
- No mismatch occurs between \`Origin: staging.example.com\` and \`X-Forwarded-Host\`.

Use one canonical origin consistently during the test. Do not switch between a hostname and a private IP in the same browser session.

## Backup and Restore

Create a staging database backup only after the dedicated role exists:

~~~bash
node scripts/backup-staging-db.mjs
~~~

The command uses the dedicated role:

~~~text
bma_backup
~~~

and never uses \`bma_app\`.

Copy the dump outside the Database VM, record its checksum, and test restore into a clean PostgreSQL instance. A Docker volume is persistence, not a backup.

Back up uploads separately from PostgreSQL:

- Record file count.
- Record checksums.
- Copy the backup outside the Application VM.
- Restore into a clean upload volume.
- Verify attachment metadata, preview, and download behavior.

## Failure Tests

Run destructive tests only against an explicitly disposable environment:

~~~env
DISPOSABLE_ENVIRONMENT=true
~~~

Before every destructive test, record the environment name and backup identifier.

Required tests:

1. Stop PostgreSQL and verify liveness remains 200 while readiness becomes 503.
2. Restart PostgreSQL and verify readiness recovers.
3. Restart Backend and verify no migration or seed runs.
4. Restart the Application VM and verify all services recover.
5. Restart the Database VM and verify data persists.
6. Simulate a failed image pull and verify deployment stops safely.
7. Simulate a failed migration against a disposable database only.
8. Verify backup failure and disk-space alerts.

Never perform these tests against production.

## Staging Exit Checklist

- [ ] Database is reachable only from the Application VM private IP.
- [ ] Application stack contains no PostgreSQL service.
- [ ] Immutable images are used.
- [ ] HTTPS and Nginx routes work.
- [ ] Server Actions work through the staging hostname.
- [ ] Browser bundle private-IP check passes.
- [ ] Migration succeeds.
- [ ] Required seed is idempotent.
- [ ] Dedicated backup role is verified.
- [ ] Database backup is stored externally.
- [ ] Database restore succeeds.
- [ ] Upload restore succeeds.
- [ ] Failure tests are completed only in disposable environments.
- [ ] Smoke-test evidence is recorded.
- [ ] Production remains marked NOT READY until PRs 1–7 and final review pass.
