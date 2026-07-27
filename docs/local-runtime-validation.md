# Local Runtime Validation Report

Status: `PASSED`

This report covers the disposable Docker Desktop runtime only. It contains no
passwords, tokens, cookies, private keys, or full database URLs.

## Test Context

- Test date: 2026-07-27 (Asia/Bangkok)
- Public URL: `http://localhost:8088`
- Database Compose: `compose.db.staging.yml` with `env/db.staging.local`
- Application Compose: `compose.app.staging.yml` with `compose.staging-local.override.yml`
- Frontend image ID: `sha256:61ce22b065caaa35d29675e0d65c9a270f4219af9cc1acdaaefcaa2e83015c49`
- Backend image ID: `sha256:33a875b37e3767950647e4513763d2c744e83a302bbc2cb72e1848b31d116f64`
- PostgreSQL image ID: `sha256:9b4593c6de443299b46098151fc1ec154c882339b77a56334c7ce612c8a7be6a`
- Nginx image ID: `sha256:6769dc3a703c719c1d2756bda113659be28ae16cf0da58dd5fd823d6b9a050ea`
- Existing database volume preserved: `bma_staging_pg_data`
- Existing upload volume preserved: `bma_staging_uploads`
- Final containers: PostgreSQL healthy; Backend healthy; Frontend running; Nginx running
- Final published ports: PostgreSQL `127.0.0.1:55432`; Nginx `0.0.0.0:8088`

## Results

| Area | Result | Evidence | Finding |
|---|---|---|---|
| Git/worktree safety | PASS | Frontend is clean; Backend contains uncommitted Drizzle migration edits that were left untouched; Infrastructure changes are limited to the validation tooling and report | Review the existing Backend migration work before committing |
| Runtime baseline | PASS | Independent Database and Application Compose stacks started successfully | PostgreSQL is not part of the Application stack |
| Compose validation | PASS | Both stacks passed `docker compose ... config --quiet` with explicit env files | None |
| Explicit migration | PASS | One-off Backend migration completed successfully | No migration ran during normal startup/restart |
| Required seed twice | PASS | Required seed completed twice without duplicate reference rows; representative counts remained stable | None |
| Demo seed | PASS | Demo seed completed in the disposable local environment; 5 demo users and 6 seeded projects were available | None |
| Authentication | PASS | Valid login, invalid login, logout, session persistence after refresh, and protected-route redirect verified through `localhost:8088` | Cookie configuration was verified from local env values; browser cookie attributes were not programmatically inspected |
| Authorization | PASS | User, Secretary, Admin, Super Admin, and Analyst navigation plus direct API `403` checks verified | None |
| Core workflow | PASS | Three new projects were created, saved as drafts, submitted, Secretary-approved, Admin-assigned, then exercised through Analyst approve/return/reject paths (`9`, `7`, `8`) | Workflow API was exercised through the public origin; UI navigation and RBAC were also verified |
| Upload validation | PASS | Allowed System Diagram upload returned `201`; invalid category/file combination returned `400`; oversized image returned `413` | None |
| Upload persistence | PASS | Attachment metadata, type mapping, preview response, Backend restart, and Application stack recreation all preserved the file | None |
| PostgreSQL outage recovery | PASS | `/health/live` remained `200`; `/health/ready` returned `503`; readiness returned `200` after PostgreSQL restart | None |
| Service restart recovery | PASS | Backend restart and full Application stack down/up without `-v` completed successfully | No migration or seed ran during restart |
| Database backup | PASS | Custom-format dump and SHA-256 checksum generated with the dedicated backup role | None |
| Database restore | PASS | Restore into a separate disposable volume succeeded; migration history and representative counts verified; temporary Backend readiness passed | None |
| Upload backup | PASS | Upload volume archive and SHA-256 checksum generated after the validation upload | None |
| Upload restore | PASS | Archive restored into a separate disposable upload volume; one file and its byte count were recovered | None |
| Browser leakage scan | PASS | Smoke test rejected private VM IPs, `host.docker.internal`, direct backend/frontend ports, database URLs, and secret variable names in browser assets | None |
| Non-root verification | PASS | Backend ran as `appuser`; Frontend ran as `nextjs` | None |
| Nginx smoke routes | PASS | `/`, `/api/v1/projects`, `/health/live`, `/health/ready`, `/openapi-v1.json`, and `/docs/` responded as expected | Unauthenticated API request correctly returned `401` |

## Health and Smoke Evidence

- `/health/live`: `200`
- `/health/ready`: `200` with database connected
- `/openapi-v1.json`: `200`
- `/docs/`: `200`
- `/api/v1/projects` without authentication: `401`
- Final smoke test: passed, including browser-bundle leakage checks

## Seed and Restore Counts

The final disposable database restore verified:

```text
migrationCount: 5
users: 5
projects: 9
proposals: 3
attachments: 1
```

## Backup Evidence

- Database dump: `backups/bma_staging_db_2026-07-27T04-22-33-594Z.dump`
- Database dump size: `110394` bytes
- Database SHA-256: `B695A9349885FD0EDBD30256377588F7C8A347AD16FFAED8B8EF4F31FB2C938E`
- Database restore duration: `8439 ms`
- Upload archive: `backups/bma_staging_uploads_2026-07-27T04-21-24-452Z.tar.gz`
- Upload archive size: `96130` bytes
- Upload source bytes: `102400`
- Upload file count: `1`
- Upload SHA-256: `97E37269984919329F4B699B9FC502B432A5D807DB962C16655BC0B658D40BC6`

## Findings

### P0

- None. All required local validation gates passed.

### P1

- The Backend worktree currently contains uncommitted Drizzle migration changes. The validation work did not modify or reset them; review and commit them separately when appropriate.
- Cookie settings were validated from the local configuration (`Secure=false`, `SameSite=Lax`, empty domain). Automated browser tooling did not inspect cookie contents or attributes.
- The workflow validation used the public API through Nginx for deterministic state-transition checks. The browser UI role/navigation checks passed separately.

### P2

- Docker reported an orphan legacy development container (`bma_dev_postgres`) during an earlier Compose operation. It was not part of the staging-local stack and did not affect validation. Remove it manually only after confirming it is no longer needed.

## Exit Decision

```text
Local production-like validation: PASSED
Ready for real Staging VM preparation: YES
Real staging deployment: NOT STARTED
Production deployment: NOT READY
```
