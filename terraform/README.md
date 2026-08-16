# terraform/ cheat sheet

Full rationale/design decisions live in the repo root [README.md](../README.md).
This is just the commands you'll actually type.

## Setup (once)

```bash
sudo dnf install opentofu   # or your distro's equivalent
cd terraform
cp .env.example .env        # fill in the token from the Ansible terraform_api task
```

## Everyday commands

`tofu.sh` sources `.env` and execs `tofu "$@"`, so you don't need to
`set -a; source .env; set +a` by hand every time.

```bash
./tofu.sh plan              # preview - always run this first
./tofu.sh apply
./tofu.sh apply -auto-approve   # skips the confirmation prompt
./tofu.sh destroy               # careful - destroys everything in state
```

Applying also regenerates `../ansible/inventory/vms.yml` - run the Ansible
VM playbook after any `apply` that adds/changes a VM.

Changing `disk_gb` (or adding the `disk` block for the first time, as
happened when it was introduced) reboots the VM to apply - not
destructive, but expect a short blip in connectivity right after `apply`.
Proxmox grows the disk itself, but the guest's partition/filesystem
doesn't follow automatically after the first boot - run the Ansible VM
playbook afterwards (`common_tools` runs `growpart` + `xfs_growfs` and is
idempotent, so it's a no-op when there's nothing to grow).

## Adding a new VM

1. Add an entry to the `vms` map in `locals.tf`. Each VM has a list of
   `networks` - one per NIC, on whichever bridge(s) it needs (`vmbr0`
   LAN, `vmbr20` IOT, `vmbr30` DMZ, `vmbrSAN` for direct NAS/NFS access).
   The **first** network in the list is the one Ansible connects to, so
   put the LAN one first. Only set a `gateway` on one interface (usually
   the LAN one) - `null` on the rest.

   `vm_id` must be unique (`test` uses 100, `test2` uses 101) - it's
   explicit rather than derived, so it can never shift under an existing
   VM just because the map changed shape. `memory_mb` feeds the VM's
   actual RAM, `memory_floating_mb` is the ballooning floor (how low
   Proxmox can shrink the VM's RAM when the host is under memory pressure
   - without it, Proxmox reserves the full `memory_mb` statically even
   while the VM is idle), `swap_mb` becomes the `vm_provision_swap_mb`
   host var (swap file size, set by the `vm_provision` Ansible role), and
   `disk_gb` is the boot disk size (grow-only - Proxmox can't shrink a
   disk. `disk_gb` below the template's current size fails the apply).
   Adjust all per VM based on its expected load.

   Three more are optional, defaulted in `vms.tf` via `try(...)` if
   omitted: `cloudinit_upgrade` (default `true`) runs a full package
   upgrade via cloud-init on first boot; `tags` (default `[]`) are Proxmox
   tags - passed through `sort()` in the module, since Proxmox always
   sorts tags server-side and an unsorted list would show permanent drift
   otherwise; `dns_domain` (default `null`) is the DNS search domain. The
   DNS *server* isn't a separate field - it's always `networks[0].gateway`,
   since each network segment's router is the only resolver a VM on that
   segment actually has a route to (a fixed DNS IP would work for `vmbr0`
   but silently fail for VMs on `vmbr20`/`vmbr30`).

   `ansible_groups` (default `[]`) puts the VM in extra Ansible groups
   beyond `vms` (which every VM belongs to automatically), so a playbook
   can target a subset without touching every VM - e.g. a future set of
   VMs tagged `["db"]` could be targeted by a `playbooks/db.yml` with
   `hosts: db`, and any VM added later that doesn't need it just doesn't
   get the field and is automatically left alone.

   ```hcl
   locals {
     vms = {
       test = {
         vm_id              = 100
         memory_mb          = 2048
         memory_floating_mb = 1024
         swap_mb            = 1024
         disk_gb            = 10
         tags               = ["test", "homelab"]
         dns_domain         = "lan.pri.alexborrazasm.dev"
         networks = [
           { bridge = "vmbr0", ip = "192.168.9.10", gateway = "192.168.9.1" },
         ]
       }
       # a VM that also needs the NAS directly, skips the first-boot
       # upgrade, and is targetable on its own via `hosts: db`:
       newvm = {
         vm_id              = 102
         memory_mb          = 4096
         memory_floating_mb = 2048
         swap_mb            = 2048
         disk_gb            = 20
         cloudinit_upgrade  = false
         ansible_groups     = ["db"]
         networks = [
           { bridge = "vmbr0",   ip = "192.168.9.11", gateway = "192.168.9.1" },
           { bridge = "vmbrSAN", ip = "10.10.10.11",  gateway = null },
         ]
       }
     }
   }
   ```

2. That's it - `vms.tf` instantiates one `./modules/vm` per entry in the
   map via `for_each`, so no `.tf` file to copy/edit per VM.

3. `./tofu.sh plan` to check it, then `./tofu.sh apply`.

4. `ansible/inventory/vms.yml` now has the new host under the `vms` group.
   From `ansible/`: `uv run ansible-playbook playbooks/vms.yml`.

## Version pin gotcha

`versions.tf` pins the proxmox provider to 3 segments (`~> 0.111.0`), not
2 (`~> 0.111`). With 2 segments `~>` only pins the major, and this
provider is pre-1.0 - breaking changes land in minor bumps.
