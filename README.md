# homelab

Infrastructure as code for a single-node Proxmox homelab (`pve`, Intel NUC
12 Pro). Goal: reinstall from ISO and get back to a fully configured,
reproducible setup without touching the GUI by hand.

## Layers

- **`pve` itself** — Ansible. Networking, repos, hardening, GUI cleanup.
- **VMs** — OpenTofu (create/resize/destroy) + Ansible (configuration).
- **Services** — Docker, deployed via [Komodo](https://komo.do)
  (self-hosted, git-backed compose stacks).

## Stack

- **Ansible** (`uv`-managed) — host and VM configuration
- **OpenTofu** (`bpg/proxmox` provider) — VM lifecycle
- **AlmaLinux** — cloud-init base image for service VMs
- **Docker + Komodo** — how services run and get deployed

## Getting started

- [`ansible/README.md`](ansible/README.md)
- [`terraform/README.md`](terraform/README.md)
- [`docker/README.md`](docker/README.md)
