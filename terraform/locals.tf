locals {
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBkMYwuNdqWYMYnW/xb5cqJWmn+0+vkwfJ7iLJjtAag0 alexborrazasm@gmail.com"

  # First network in the list is the primary/management one (used for
  # ansible_host). Only set a gateway on the interface that should carry
  # the VM's default route - null on the rest.
  #
  # Full field reference (copy/uncomment as a starting point for a new VM):
  #
  # example = {
  #   vm_id              = 199                    # unique, explicit - never derived, so it can't shift under an existing VM
  #   memory_mb          = 2048                    # actual RAM
  #   memory_floating_mb = 1024                    # ballooning floor - how low Proxmox can shrink RAM under host memory pressure
  #   swap_mb            = 0                    # -> vm_provision_swap_mb host var, swap file size (ansible/roles/vm_provision)
  #   disk_gb            = 10                      # boot disk size, grow-only - can't shrink below the template's current size
  #   cloudinit_upgrade  = true                     # optional, default true - full package upgrade via cloud-init on first boot
  #   tags               = ["service", "homelab"]   # optional, default [] - order doesn't matter, sorted in modules/vm (Proxmox sorts server-side anyway)
  #   dns_domain         = "lan.pri.alexborrazasm.dev" # optional, default null - DNS search domain. DNS server is always networks[0].gateway, not a separate field
  #   ansible_groups     = ["k3s", "k3s_server"]   # optional, default [] - extra Ansible groups (beyond "vms"), so playbooks can target a subset (e.g. only k3s nodes) without touching every VM
  #   networks = [
  #     # bridge: vmbr0 (LAN), vmbr20 (IOT), vmbr30 (DMZ), vmbrSAN (direct NAS/NFS access)
  #     { bridge = "vmbr0", ip = "192.168.9.99", gateway = "192.168.9.1" },  # first = the one Ansible connects to. ip has no /24 - the module appends it
  #     { bridge = "vmbrSAN", ip = "10.10.10.99", gateway = null },          # only one interface should ever set a gateway
  #   ]
  # }
  vms = {
    test = {
      vm_id              = 100
      memory_mb          = 2048
      memory_floating_mb = 1024
      swap_mb            = 1024
      disk_gb            = 20
      tags               = ["test", "lan"]
      dns_domain         = "lan.pri.alexborrazasm.dev"
      # no ansible_groups on purpose - proves a regular VM stays out of
      # the k3s group automatically, without needing to opt out of anything.
      networks = [
        { bridge = "vmbr0", ip = "192.168.9.10", gateway = "192.168.9.1" },
      ]
    }
    k3s-server = {
      vm_id              = 310
      memory_mb          = 4096
      memory_floating_mb = 2048
      swap_mb            = 0
      disk_gb            = 20
      tags               = ["k3s", "k3s-server", "dmz"]
      dns_domain         = "dmz.pri.alexborrazasm.dev"
      ansible_groups     = ["k3s", "k3s_server"]
      networks = [
        { bridge = "vmbr30", ip = "10.0.0.10", gateway = "10.0.0.1" },
      ]
    }
    k3s-agent1 = {
      vm_id              = 311
      memory_mb          = 3072
      memory_floating_mb = 1536
      swap_mb            = 0
      disk_gb            = 20
      tags               = ["k3s", "k3s-agent", "dmz"]
      dns_domain         = "dmz.pri.alexborrazasm.dev"
      ansible_groups     = ["k3s", "k3s_agent"]
      networks = [
        { bridge = "vmbr30", ip = "10.0.0.11", gateway = "10.0.0.1" },
      ]
    }
    k3s-agent2 = {
      vm_id              = 312
      memory_mb          = 3072
      memory_floating_mb = 1536
      swap_mb            = 0
      disk_gb            = 20
      tags               = ["k3s", "k3s-agent", "dmz"]
      dns_domain         = "dmz.pri.alexborrazasm.dev"
      ansible_groups     = ["k3s", "k3s_agent"]
      networks = [
        { bridge = "vmbr30", ip = "10.0.0.12", gateway = "10.0.0.1" },
      ]
    }
  }

  # Derives {group_name => [host names]} from each VM's ansible_groups, so
  # inventory.tftpl can emit extra Ansible groups (e.g. "k3s") without
  # every VM needing to belong to them - keeps a future non-k3s VM out of
  # any k3s-scoped playbook automatically, just by omitting the field.
  vm_group_names = toset(flatten([
    for name, cfg in local.vms : try(cfg.ansible_groups, [])
  ]))

  vm_groups_hosts = {
    for g in local.vm_group_names : g => [
      for name, cfg in local.vms : name if contains(try(cfg.ansible_groups, []), g)
    ]
  }
}
