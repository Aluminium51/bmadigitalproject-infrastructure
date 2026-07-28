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
- Do not use `down -v` on a database that contains data to preserve.
- Do not run the demo seed on staging unless the environment is explicitly disposable.
- Keep actual environment files outside Git.
- Do not print secrets in shell output or CI logs.
- Database backups must use the dedicated `bma_backup` role, not `bma_app`.
- Stop if VM1 or VM2 has a missing, duplicate, or unapproved private IP.
- Stop if PostgreSQL binds to a wildcard address or an unknown process owns port 5432.
- Do not continue when SSH, sudo, or console recovery access is unavailable.

## Prerequisites

- A private IP for the Application VM.
- A private IP for the Database VM.
- DNS for the staging hostname.
- TLS certificate and private key.
- Registry pull credentials.
- Docker Engine and Compose on both VMs.
- Firewall access from Application VM to Database VM port 5432.

Before remote execution, confirm the final VM addresses. The previous
observations showed addresses that did not match the original plan and a
duplicate `172.27.219.33` on both VMs. Do not use that duplicate address. Keep
the following values as placeholders until the network owner approves them:

```text
Application VM private IP: <APP_VM_PRIVATE_IP>
Database VM private IP:    <DB_VM_PRIVATE_IP>
```

Create the actual environment files:

~~~bash
cp env/app.staging.example env/app.staging
cp env/db.staging.example env/db.staging
chmod 600 env/app.staging env/db.staging
~~~

Replace all placeholder values before starting.

The PostgreSQL password inside `DATABASE_URL` must be URL-encoded if it contains reserved URL characters.

## Database VM

Validate the Database Compose configuration:

~~~bash
docker compose --env-file env/db.staging -f compose.db.staging.yml config
~~~

Start PostgreSQL through the guarded deployment wrapper:

~~~bash
DB_ENV_FILE=/opt/bma/env/db.staging \
DB_COMPOSE_FILE=/opt/bma/infrastructure/compose.db.staging.yml \
EXPECTED_BIND_ADDRESS=<DB_VM_PRIVATE_IP> \
EXPECTED_BIND_PORT=5432 \
bash /opt/bma/infrastructure/scripts/deploy-db-vm2.sh
~~~

The database port is bound to `DATABASE_BIND_ADDRESS:5432`. The host firewall
must allow that port only from the approved Application VM private IP. The
wrapper waits for PostgreSQL readiness and prints recent logs if the bounded
wait fails.

Create or update the dedicated read-only backup role:

~~~bash
node /opt/bma/infrastructure/scripts/ensure-backup-role.mjs --env-file /opt/bma/env/db.staging --compose-file /opt/bma/infrastructure/compose.db.staging.yml
~~~

Verify the role permissions using a privileged administrative session:

~~~sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolinherit
FROM pg_roles
WHERE rolname IN ('bma_app', 'bma_backup');
~~~

Expected for `bma_backup`:

~~~text
rolsuper      = false
rolcreatedb   = false
rolcreaterole = false
rolinherit    = true
~~~

The backup role receives PostgreSQL's `pg_read_all_data` role and must not be used by the application.

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

Never run `db:generate` on the staging or production server.

Never run `db:seed:demo` automatically.

## Expected Smoke-Test Responses

Run from the Application VM or an approved test host.

Linux/macOS:

~~~bash
STAGING_BASE_URL=https://staging.example.com node /opt/bma/infrastructure/scripts/smoke-test-staging.mjs
~~~

PowerShell:

~~~powershell
$env:STAGING_BASE_URL = "https://staging.example.com"
node /opt/bma/infrastructure/scripts/smoke-test-staging.mjs
~~~

Expected results:

| Endpoint | Expected status | Expected content |
|---|---:|---|
| `/` | 200 | `text/html` |
| `/health/live` | 200 | `application/json` |
| `/health/ready` | 200 | `application/json` |
| `/openapi-v1.json` | 200 | `application/json` |
| `/docs/` | 200 | `text/html` |

The smoke test also downloads Next.js script assets and fails if browser bundles contain:

- `host.docker.internal`
- PostgreSQL URLs
- Port `5432`
- Backend port `8081`
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
- No `Invalid Server Actions request` error appears.
- No mismatch occurs between `Origin: staging.example.com` and `X-Forwarded-Host`.

Use one canonical origin consistently during the test. Do not switch between a hostname and a private IP in the same browser session.

## Backup and Restore

Create a staging database backup only after the dedicated role exists:

~~~bash
node /opt/bma/infrastructure/scripts/backup-staging-db.mjs --env-file /opt/bma/env/db.staging --compose-file /opt/bma/infrastructure/compose.db.staging.yml --output-dir /opt/bma/backups/database
~~~

The command uses the dedicated role:

~~~text
bma_backup
~~~

and never uses `bma_app`.

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

## Local-Only Validation

This section is for Docker Desktop on the developer machine. It does not configure either real VM.

Create ignored local files from the examples:

~~~powershell
Copy-Item env/app.staging.example env/app.staging.local
Copy-Item env/db.staging.example env/db.staging.local
~~~

Replace the local files with fake values from the repository's local examples. Do not use real VM passwords, TLS keys, or production credentials.

Validate the local Database stack:

~~~bash
docker compose --env-file env/db.staging.local -f compose.db.staging.yml config
~~~

Validate the local Application stack:

~~~bash
docker compose --env-file env/app.staging.local -f compose.app.staging.yml -f compose.staging-local.override.yml config
~~~

The local override:

- Publishes Nginx on `http://localhost:8080`.
- Uses HTTP instead of TLS.
- Publishes PostgreSQL only on `127.0.0.1:55432`.
- Does not alter the canonical staging Compose files.

The canonical staging files do not build source code. If the `local-test` image tags do not exist locally, local runtime testing is blocked until temporary local tags are created or approved registry images are available. Do not add `build:` to the canonical staging files.

Local start sequence:

~~~bash
docker compose --env-file env/db.staging.local -f compose.db.staging.yml up -d
docker compose --env-file env/app.staging.local -f compose.app.staging.yml -f compose.staging-local.override.yml up -d
~~~

Run local migration and required seed only against disposable local data:

~~~bash
docker compose --env-file env/app.staging.local -f compose.app.staging.yml -f compose.staging-local.override.yml run --rm backend bun run db:migrate
docker compose --env-file env/app.staging.local -f compose.app.staging.yml -f compose.staging-local.override.yml run --rm backend bun run db:seed:required
~~~

Local expected URLs:

~~~text
http://localhost:8080/
http://localhost:8080/health/live
http://localhost:8080/health/ready
http://localhost:8080/openapi-v1.json
http://localhost:8080/api/v1/projects
~~~

The unauthenticated projects request is expected to return `401` with JSON.

## Environment Contract Matrix

| Variable | Consumer | Local value | Real staging value | Secret | Required |
|---|---|---|---|---:|---:|
| `DATABASE_URL` | Backend and migration/seed scripts | Yes | Yes | Yes | Yes |
| `POSTGRES_USER` | PostgreSQL | Yes | Yes | No | Yes |
| `POSTGRES_PASSWORD` | PostgreSQL | Fake only | Yes | Yes | Yes |
| `POSTGRES_DB` | PostgreSQL | Yes | Yes | No | Yes |
| `POSTGRES_BACKUP_USER` | Backup role/script | Fake only | Yes | No | Yes |
| `POSTGRES_BACKUP_PASSWORD` | Backup role/script | Fake only | Yes | Yes | Yes |
| `DATABASE_BIND_ADDRESS` | Database Compose | `127.0.0.1` | DB VM private IP | No | Yes |
| `DATABASE_HOST_PORT` | Database Compose | `55432` | `5432` | No | Yes |
| `BACKEND_IMAGE` | Application Compose | Placeholder/local tag | Registry repository | No | Yes |
| `FRONTEND_IMAGE` | Application Compose | Placeholder/local tag | Registry repository | No | Yes |
| `BACKEND_VERSION` | Application Compose | `local-test` | Commit SHA | No | Yes |
| `FRONTEND_VERSION` | Application Compose | `local-test` | Commit SHA | No | Yes |
| `JWT_SECRET` | Backend runtime | Fake only | Unique staging secret | Yes | Yes |
| `PUBLIC_API_URL` | Backend runtime | `http://localhost:8080/api/v1` | Staging HTTPS URL | No | Yes |
| `CORS_ORIGINS` | Backend runtime | `http://localhost:8080` | Staging HTTPS origin | No | Yes |
| `COOKIE_SECURE` | Backend/Frontend | `false` | `true` | No | Yes |
| `COOKIE_SAME_SITE` | Backend/Frontend | `lax` | `lax` | No | Yes |
| `UPLOAD_STORAGE_DIR` | Backend runtime | `/app/uploads` | `/app/uploads` | No | Yes |

Rules:

- Passwords in `DATABASE_URL` must be URL-encoded.
- No `NEXT_PUBLIC_*` value may contain a private Backend or Database address.
- `BACKEND_URL` is server-only and must not use the `NEXT_PUBLIC_` prefix.
- Scripts must fail clearly when required values are missing.
- Secrets must never be printed.

## Known Deployment Targets

These are unverified planning targets only. No connection or configuration has
been performed. Replace them only after the network owner approves the final
unique addresses:

~~~text
Application VM
Hostname: DGTPROJECT01
Private IP: <APP_VM_PRIVATE_IP>
OS: Ubuntu 24.04
CPU: 2 cores
RAM: 8 GB
Storage: 200 GB

Database VM
Hostname: DGTPROJECT02
Private IP: <DB_VM_PRIVATE_IP>
OS: Ubuntu 24.04
CPU: 4 cores
RAM: 16 GB
Storage: 300 GB

Production domain:
digitalproject.bangkok.go.th
~~~

Unresolved infrastructure dependencies:

- Whether the domain is public or BMA-internal.
- Which system receives traffic for the domain.
- Whether NAT, load balancing, a WAF, or another reverse proxy exists.
- Who manages DNS.
- Who issues and renews TLS certificates.
- Which networks may access SSH.
- Which external destination stores backups.
- Which registry organization and repositories are approved.

The production domain must not be used as a local endpoint.

## Future Server Execution Checklist

The following section must not be executed during local preparation.

### Application VM — DGTPROJECT01

- [ ] Verify hostname, OS, private IP, and disk capacity.
- [ ] Install Docker Engine and Compose.
- [ ] Create the deployment user.
- [ ] Authenticate to the approved registry.
- [ ] Install protected application environment files.
- [ ] Install TLS assets through the approved process.
- [ ] Pull immutable images.
- [ ] Run migration as an explicit one-off container.
- [ ] Run required seed only when approved.
- [ ] Start Backend and verify liveness/readiness.
- [ ] Start Frontend and Nginx.
- [ ] Run smoke tests.

### Database VM — DGTPROJECT02

- [ ] Verify hostname, OS, private IP, and disk capacity.
- [ ] Install Docker Engine and Compose.
- [ ] Configure the firewall to allow port 5432 only from `<APP_VM_PRIVATE_IP>/32`.
- [ ] Start PostgreSQL.
- [ ] Create the application role.
- [ ] Create and verify the dedicated backup role.
- [ ] Verify persistence.
- [ ] Create the initial backup.
- [ ] Transfer the backup outside the Database VM.

### External infrastructure

- [ ] Confirm DNS ownership and record.
- [ ] Confirm public ingress, NAT, load balancer, or WAF behavior.
- [ ] Confirm TLS issuance and renewal.
- [ ] Confirm approved admin network ranges.
- [ ] Confirm the external backup destination.

No VM, DNS, firewall, TLS, production domain, or real secret is used in this local-preparation phase.
