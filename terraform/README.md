# terraform

VM lifecycle - create, resize, destroy.

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

Changing `disk_gb` reboots the VM (brief connectivity blip). Proxmox
grows the virtual disk; the guest filesystem doesn't follow until the
Ansible VM playbook runs afterward (idempotent, no-op if there's nothing
to grow).

## Adding a new VM

1. Add an entry to the `vms` map in `locals.tf` - field reference is
   commented at the top of that file, copy/uncomment as a starting point.
2. `./tofu.sh plan`, then `./tofu.sh apply`. No `.tf` file to write - one
   `for_each` in `vms.tf` handles every VM in the map.
3. From `ansible/`: `uv run ansible-playbook playbooks/vms.yml`.

## Version pin gotcha

`versions.tf` pins the proxmox provider to 3 segments (`~> 0.111.0`), not
2 (`~> 0.111`). With 2 segments `~>` only pins the major, and this
provider is pre-1.0 - breaking changes land in minor bumps.
