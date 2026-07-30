# VM1 Baseline Evidence — 2026-07-29

This file is sanitized evidence from the Application VM inspection. It does
not contain credentials, private keys, TLS material, database URLs, or shell
history.

## Identity and capacity

- Hostname: `ubuntu-248`
- OS: Ubuntu 24.04.4 LTS
- Kernel: Linux 6.8.0-136-generic
- Architecture: x86_64
- Virtualization: KVM / OpenStack Nova
- CPU: 2 vCPU
- RAM: approximately 7.7 GiB observed
- Swap: 8 GiB
- Virtual disk: 200 GB
- Root logical volume: approximately 49 GB
- Root free space: approximately 32 GB
- Docker Engine: 29.6.2
- Docker Compose: v5.3.1

## Network findings

- `192.168.1.248` is technically operational but not formally approved by Infrastructure.
- `172.27.219.33` is configured but non-operational.
- `172.27.168.248` is planned or externally documented but is not present in the guest OS.
- The operational gateway observed was `192.168.1.1`.
- The observed DNS server was `172.27.2.11`.
- Netplan contains conflicting default routes and validation currently fails.
- The stale or duplicate `172.27.219.33` configuration remains unresolved.

## Existing services and blockers

- Existing container: `bma-nginx`.
- Existing Nginx ownership of ports 80 and 443 is not approved for replacement.
- Cloud-init is disabled while `50-cloud-init.yaml` remains read by Netplan.
- Upload storage layout and recovery location are not finalized.
- Direct SSH, sudo, console recovery, registry, hostname, TLS, and final VM addresses remain unresolved.

No remote action was performed while collecting or documenting this evidence.
