# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

IaC for a single-node homelab: one Proxmox VE host (`pve`, Intel NUC 12 Pro,
PVE 9.2) plus the VMs on top of it. Ansible configures `pve` and the VMs;
OpenTofu provisions the VMs. Full narrative/rationale lives in the root
`README.md`; `ansible/README.md` and `terraform/README.md` are command
cheat sheets — check those before re-deriving a command from scratch.

## Commands

```bash
cd ansible && uv sync   # once, or after pyproject.toml changes
```

Always `--check --diff` before applying, for both playbooks:

```bash
uv run ansible-playbook playbooks/proxmox-host.yml --check --diff
uv run ansible-playbook playbooks/proxmox-host.yml

uv run ansible-playbook playbooks/vms.yml --check --diff        # all VMs
uv run ansible-playbook playbooks/vms.yml --limit test2         # just one
```

Package upgrades are opt-in (tag `never`, so a plain run never touches
packages):

```bash
uv run ansible-playbook playbooks/<playbook>.yml --tags upgrade --check --diff
uv run ansible-playbook playbooks/<playbook>.yml --tags upgrade
```

Terraform, from `terraform/`: `./tofu.sh plan|apply|destroy` — the wrapper
sources `.env` (gitignored; API token) so `tofu` never needs manual env
exports. `./tofu.sh apply` also regenerates `../ansible/inventory/vms.yml`.

## Architecture

**Two-tool split, and why**: Ansible owns config (packages, files, service
state — anything idempotent-by-diff); OpenTofu owns VM lifecycle (create,
resize, destroy). `pve` itself is Ansible-only (no VM to provision — it's
the ISO-installed host). Terraform is a separate toolchain (Go binary, not
a Python package) so it lives outside `ansible/`'s `uv` environment
entirely — see `terraform/versions.tf`, `terraform/provider.tf`.

**Single source of truth for VMs**: every VM is one entry in the `vms` map
in `terraform/locals.tf` (`vm_id` (explicit, never derived), `memory_mb`,
`memory_floating_mb` (ballooning floor), `swap_mb`, `disk_gb`, a
`networks` list — one object per NIC with `bridge`/`ip`/`gateway`, first
network = the one Ansible connects through — and the optional
`cloudinit_upgrade`/`tags`/`dns_domain`/`ansible_groups`, defaulted via
`try(...)` in `vms.tf` if omitted). The cloud-init DNS *server* is always
`networks[0].gateway`, not a separate field — a fixed DNS IP would be
unreachable from VMs on `vmbr20`/`vmbr30`, since each segment's router is
the only resolver they have a route to. `ansible_groups` puts a VM in
extra generated-inventory groups beyond `vms`, so a playbook can target
a subset of VMs without touching every one —
`terraform/locals.tf`'s `vm_groups_hosts` local derives
`{group => [hosts]}` from every VM's `ansible_groups` and
`inventory.tftpl` emits one Ansible group per key. That one map feeds
both `terraform/vms.tf` (`for_each` over the
map, one `./modules/vm` instance per VM — adding a VM is a `locals.tf`
edit only, no `.tf` file to write/copy) and the generated Ansible
inventory (`terraform/inventory.tf`
+ `inventory.tftpl` →
`ansible/inventory/vms.yml`, gitignored — it's a build artifact, edit
`locals.tf` instead). `ansible.cfg` points `inventory` at the whole
`inventory/` directory so `hosts.yml` (pve) and the generated `vms.yml`
merge into one inventory automatically.

**Role boundaries on the Ansible side** — these were deliberately split,
not just organized by topic:
- `proxmox_host`: `pve`-only. Network template, apt repos, GUI nag
  removal, HA/corosync disable, the OpenTofu API user/token (`pveum`),
  the AlmaLinux cloud-init template (VMID 9000).
- `common_tools`: applied to `pve` and every VM. Packages (nvim, htop,
  fastfetch, bat, eza), system-wide Neovim config, shell aliases/prompt,
  sshd hardening (key-only auth), fail2ban. OS-family aware
  (`ansible_facts['os_family']`) for apt vs dnf, not host-specific — the
  exceptions are `common_tools_color_prompt` (off on `pve`, which sets
  its own PS1) and `common_tools_ssh_permit_root_login` (`pve` overrides
  to `prohibit-password` since root is the actual login user there, vs
  `no` everywhere else).
- `vm_provision`: VMs only (only included from `playbooks/vms.yml`), not
  `common_tools` — swap file and root filesystem growth are VM lifecycle
  concerns that don't apply to `pve` at all, so they're a separate role
  rather than runtime-detected exceptions inside a shared one.
- `os_upgrade`: shared by both playbooks, OS-family branched internally
  (apt+dpkg kernel check on Debian, `dnf` + `dnf needs-restarting -r` on
  RedHat) since the upgrade/reboot-check *shape* is identical either way.
- `docker`: any VM in the `docker` `ansible_groups` group, via
  `playbooks/docker.yml`. Installs Docker CE (RedHat-family only right
  now) and creates the `docker` service account (fixed UID:GID `900:900`
  across every host on purpose - see Non-obvious gotchas). Not
  `common_tools` - Docker isn't universal like nvim/htop, it's opt-in per
  VM.
- `komodo`: the **one** host in the `komodo` group (`panel`) - deploys
  the full [Komodo](https://komo.do) stack (Mongo + Core + Periphery,
  self-managing) under `/srv/docker/komodo`. Exposes Core's public key as
  an Ansible fact (`komodo_core_public_key`) for `komodo_agent` to read
  via `hostvars` in the same playbook run.
- `komodo_agent`: every other docker host (`frontend`, `iot`, ...) -
  Periphery only, under `/srv/docker/komodo-agent`, trusting Core's
  public key read live from the `komodo` role's fact rather than a
  committed file (so a rebuilt Core's new key reaches every agent
  automatically). No port published - Periphery only ever needs an
  *outbound* connection to Core, confirmed live (see gotchas).

**`docker/` layout**: application stacks live in `docker/stacks/<name>/compose.yaml`,
but unlike the old Kubernetes/ArgoCD setup, nothing auto-discovers them from
git - each one is registered once in Komodo's UI (**Stacks -> Create
Stack**, pointed at the repo + path), then polling/webhook sync takes
over. See `docker/README.md`.

**Network**: physical NIC is literally named `nic0` (renamed via
udev/.link, not a placeholder). `vmbr0` is the LAN, native/untagged VLAN
10 on the trunk to the Flint2 switch. `vmbr20`/`vmbr30` are IOT/DMZ.
`vmbrSAN` is a dedicated point-to-point link to the NAS (not a VLAN) —
`pve` and any VM that needs direct NFS access attach to it directly via a
second/third entry in that VM's `networks` list.

## Non-obvious gotchas

- **CPU type matters for the template.** The AlmaLinux cloud image is the
  `x86_64_v2` build; the default Proxmox `cpu.type` (`qemu64`) doesn't
  satisfy that baseline and the VM boots with no networking/agent and no
  error. Both the template (VMID 9000) and every VM resource set
  `cpu.type = "host"` — don't drop that.
- **`--check` can't preview a download-then-use chain.** Tasks like "download
  X" → "extract/import X" show the first step as `changed` and the second
  as failing/skipping under `--check`, because the download itself is
  simulated. Not a bug — apply for real to see the actual result. Several
  tasks (`vm_template.yml`, eza fallback, swap file) have this shape.
- **`/etc/profile.d/*.sh` load in alphabetical order.** Distro-shipped
  scripts (e.g. `colorls.sh`) can load after a plainly-named file and
  clobber its aliases. `common_tools`'s own scripts are named
  `zz-*.sh` specifically to always load last.
- **`epel-release` must install before `crb enable`.** `/usr/bin/crb` is
  shipped *by* `epel-release`, not the other way around — see
  `common_tools/tasks/epel.yml`. It also installs with
  `install_weak_deps: false` — the altarch (x86_64_v2) EPEL rebuild's weak
  deps (`selinux-policy-*-extra`) can pin an exact `selinux-policy-targeted`
  build that's briefly out of sync with BaseOS's latest point release.
- **Proxmox always sorts VM tags server-side.** `modules/vm` wraps the
  `tags` variable in `sort()` before setting it on the resource, or an
  unsorted list in `locals.tf` shows permanent drift on every `plan`.
- **PVE9 kernel packages are `proxmox-kernel-*`**, not `pve-kernel-*`
  (renamed from PVE8), and the installed package name has a `-signed`
  suffix that `uname -r` doesn't — both are normalized in
  `proxmox_host/tasks/upgrade.yml`'s reboot-needed check.
- **Resizing `disk_gb` doesn't resize the guest filesystem.** Proxmox
  grows the virtual disk; the partition/filesystem only follow if
  `vm_provision`'s `grow_root.yml` (`growpart` + `xfs_growfs`/`resize2fs`)
  runs afterward — cloud-init's own growpart only fires on first boot.
- **The Terraform API token intentionally lacks `VM.GuestAgent.Unrestricted`**
  (arbitrary exec inside guests) — only `VM.GuestAgent.Audit` (read-only)
  is granted, in `proxmox_host/tasks/terraform_api.yml`. Its role is kept
  in sync on every Ansible run (`pveum role modify`, not just create),
  since `pveum role add` only fires once.
- **API token secrets are shown once.** `terraform_api.yml` prints the
  token via `debug` only when it's actually created; it's not retrievable
  from Proxmox afterward. Goes in `terraform/.env` (gitignored).
- **AlmaLinux's cloud image is missing `kernel-modules-extra` here too.**
  Same root cause as k3s used to hit (before it was pulled out): Docker's
  bridge networking needs `xt_addrtype` for its iptables NAT rules, which
  isn't installed by default. `roles/docker/tasks/main.yml` installs
  `kernel-modules-extra-{{ ansible_facts['kernel'] }}` and loads the
  module immediately, same pattern as before.
- **Changing the `docker` group's GID doesn't update a running daemon's
  socket.** `/var/run/docker.sock` is actually created by the
  `docker.socket` systemd unit (socket activation), not `docker.service`
  - restarting the service alone leaves the socket owned by the *old*
  GID. Confirmed live when migrating `panel`'s `docker` user to a fixed
  UID/GID: `systemctl restart docker.socket docker.service` (both) fixed
  it. Only matters when changing an *existing* host's GID after the fact
  - a fresh install never hits this, since `docker` role creates the
  group with its fixed GID before Docker is ever installed.
- **`komodo_agent`'s Periphery needs no inbound port at all.** It only
  ever dials *out* to Core (`PERIPHERY_CORE_ADDRESS`) - confirmed live
  that Komodo's UI "Address" field (which makes Core dial back to
  Periphery) is optional, not required for the Server to show connected.
  `komodo_agent/files/compose.yaml` doesn't publish a port for exactly
  this reason - less exposed surface on a DMZ-facing host for no
  functional gain.
- **DMZ↔LAN traffic is asymmetric by design, and both directions need
  their own router rule.** LAN→DMZ was already open (general policy);
  DMZ→LAN needed an explicit rule per port (`frontend`'s Periphery
  reaching `panel`'s Core on 9120) - confirmed live when the two
  directions behaved completely differently for what looked like the
  same problem. Keep any new DMZ→LAN rule as narrow as possible (specific
  port, specific destination IP) - that direction is the one that matters
  if a DMZ host ever gets compromised.
