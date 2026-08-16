# homelab

Infrastructure as code for a single-node Proxmox homelab (`pve`, Intel NUC
12 Pro). Goal: reinstall from ISO and get back to a fully configured,
reproducible setup without touching the GUI by hand.

## Two phases

**Phase 1 — Ansible, done.** Bootstraps `pve` itself from a fresh ISO
install: networking, apt repos, hardening, GUI cleanup.

**Phase 2 — OpenTofu + Ansible, in progress.** Provisions VMs from an
AlmaLinux cloud-init template and configures them the same way Phase 1
configures the host — one Ansible role per service once those exist, no
Docker, Podman + Quadlets instead.

## Stack

- **Ansible** (`uv`-managed) — host and VM configuration
- **OpenTofu** (`bpg/proxmox` provider) — VM lifecycle
- **AlmaLinux** — cloud-init base image for service VMs
- **Podman + Quadlets** — how services will run, no Docker/compose

## Getting started

- [`ansible/README.md`](ansible/README.md) — the Ansible commands you'll actually run
- [`terraform/README.md`](terraform/README.md) — the OpenTofu commands you'll actually run
