# Real Staging Server Preparation Report

Status: `BLOCKED`

This report is for the staging VMs only. It must not contain
passwords, tokens, cookies, private keys, or credentialed database URLs.

The network is not approved for deployment yet. The original plan referenced
`172.27.168.248` and `172.27.168.249`, while previous VM inspection showed
different addresses and a duplicate `172.27.219.33`. Replace the placeholders
below only after the network owner confirms unique, reachable addresses.

## Scope

- VM1 Application host: `DGTPROJECT01` / `<APP_VM_PRIVATE_IP>`
- VM2 Database host: `DGTPROJECT02` / `<DB_VM_PRIVATE_IP>`
- PostgreSQL only on VM2 during this phase
- Backend, Frontend, and Nginx are explicitly out of scope
- No DNS, TLS, production traffic, production data, or production secrets

## Evidence

| Check | Result | Evidence |
|---|---|---|
| VM identity | NOT RUN | Capture with `/opt/bma/infrastructure/scripts/server-baseline.sh` |
| OS, kernel, CPU, memory, disk, time sync | NOT RUN | Baseline artifact required |
| Docker and Compose | NOT RUN | Baseline artifact required |
| Existing containers, volumes, networks | NOT RUN | Baseline artifact required |
| Deployment directories | NOT RUN | Run `/opt/bma/infrastructure/scripts/prepare-server-directories.sh` |
| Docker log rotation | NOT RUN | Review and merge `/etc/docker/daemon.json` safely |
| VM2 PostgreSQL Compose config | NOT RUN | Use `/opt/bma/infrastructure/scripts/deploy-db-vm2.sh` |
| VM2 PostgreSQL health | NOT RUN | `pg_isready` and Docker health status |
| VM2 private bind | BLOCKED | Must bind only to `<DB_VM_PRIVATE_IP>:5432` |
| VM1 → VM2 connectivity | BLOCKED | `nc -vz <DB_VM_PRIVATE_IP> 5432` |
| Backup role | NOT RUN | Run the reviewed idempotent backup-role script twice |
| Initial database backup | NOT RUN | Record dump size, timestamp, and SHA-256 |
| Persistence after PostgreSQL restart | NOT RUN | Verify data and named volume after restart |

## Required Findings Before Application Deployment

### P0

- PostgreSQL must not bind to `0.0.0.0`.
- VM1 and VM2 must have unique approved private IP addresses.
- VM1 must reach VM2 on the private network.
- PostgreSQL health and named-volume persistence must pass.
- The backup role and initial backup must succeed.
- No production data or secrets may be used.

### P1

- Restrict PostgreSQL firewall access to `<APP_VM_PRIVATE_IP>/32` before production.
- Copy backups to an encrypted external destination before production.
- Configure automated monitoring and alerts before production.
- Prepare immutable application images, registry access, DNS, and TLS before application staging deployment.

## Readiness Decision

```text
Server baseline preparation: BLOCKED
PostgreSQL deployment on VM2: BLOCKED
VM1-to-VM2 database connectivity: BLOCKED
Ready for application image and secret preparation: NO
Ready for real application staging deployment: NO
Production deployment: NOT READY
```

Update this report only after commands have been executed on VM1 and VM2 and
the evidence has been reviewed without recording secrets.
