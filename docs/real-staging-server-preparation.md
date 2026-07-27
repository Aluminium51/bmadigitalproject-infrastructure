# Real Staging Server Preparation Report

Status: `NOT RUN`

This report is for the approved staging VMs only. It must not contain
passwords, tokens, cookies, private keys, or credentialed database URLs.

## Scope

- VM1 Application host: `DGTPROJECT01` / `172.27.168.248`
- VM2 Database host: `DGTPROJECT02` / `172.27.168.249`
- PostgreSQL only on VM2 during this phase
- Backend, Frontend, and Nginx are explicitly out of scope
- No DNS, TLS, production traffic, production data, or production secrets

## Evidence

| Check | Result | Evidence |
|---|---|---|
| VM identity | NOT RUN | Capture with `scripts/server-baseline.sh` |
| OS, kernel, CPU, memory, disk, time sync | NOT RUN | Baseline artifact required |
| Docker and Compose | NOT RUN | Baseline artifact required |
| Existing containers, volumes, networks | NOT RUN | Baseline artifact required |
| Deployment directories | NOT RUN | Run `scripts/prepare-server-directories.sh` |
| Docker log rotation | NOT RUN | Review and merge `/etc/docker/daemon.json` safely |
| VM2 PostgreSQL Compose config | NOT RUN | Use `scripts/deploy-db-vm2.sh` |
| VM2 PostgreSQL health | NOT RUN | `pg_isready` and Docker health status |
| VM2 private bind | NOT RUN | Must bind only to `172.27.168.249:5432` |
| VM1 → VM2 connectivity | NOT RUN | `nc -vz 172.27.168.249 5432` |
| Backup role | NOT RUN | Run the reviewed idempotent backup-role script twice |
| Initial database backup | NOT RUN | Record dump size, timestamp, and SHA-256 |
| Persistence after PostgreSQL restart | NOT RUN | Verify data and named volume after restart |

## Required Findings Before Application Deployment

### P0

- PostgreSQL must not bind to `0.0.0.0`.
- VM1 must reach VM2 on the private network.
- PostgreSQL health and named-volume persistence must pass.
- The backup role and initial backup must succeed.
- No production data or secrets may be used.

### P1

- Restrict PostgreSQL firewall access to `172.27.168.248/32` before production.
- Copy backups to an encrypted external destination before production.
- Configure automated monitoring and alerts before production.
- Prepare immutable application images, registry access, DNS, and TLS before application staging deployment.

## Readiness Decision

```text
Server baseline preparation: NOT RUN
PostgreSQL deployment on VM2: NOT RUN
VM1-to-VM2 database connectivity: NOT RUN
Ready for application image and secret preparation: NO
Ready for real application staging deployment: NO
Production deployment: NOT READY
```

Update this report only after commands have been executed on VM1 and VM2 and
the evidence has been reviewed without recording secrets.