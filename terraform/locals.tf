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
  #   dns_domain         = "home.arpa" # optional, default null - DNS search domain. DNS server is always networks[0].gateway, not a separate field
  #   ansible_groups     = ["db"]                   # optional, default [] - extra Ansible groups (beyond "vms"), so playbooks can target a subset (e.g. only db nodes) without touching every VM
  #   hostpci            = "intel-gpu-vf2"          # optional, default null - PCI Resource Mapping name, e.g. an Intel GPU SR-IOV VF (see ansible/roles/proxmox_host/tasks/vgpu.yml for how VFs + mappings get created on pve)
  #   networks = [
  #     # bridge: vmbr0 (LAN), vmbr20 (IOT), vmbr30 (DMZ), vmbrSAN (direct NAS/NFS access)
  #     { bridge = "vmbr0", ip = "192.168.9.99", gateway = "192.168.9.1" },  # first = the one Ansible connects to. ip has no /24 - the module appends it
  #     { bridge = "vmbrSAN", ip = "10.10.10.99", gateway = null },          # only one interface should ever set a gateway
  #   ]
  # }
  vms = {
    panel = {
      vm_id              = 110
      memory_mb          = 2048
      memory_floating_mb = 1024
      swap_mb            = 1024
      disk_gb            = 20
      tags               = ["panel", "lan", "docker"]
      dns_domain         = "home.arpa"
      ansible_groups     = ["docker", "komodo"]
      networks = [
        { bridge = "vmbr0", ip = "192.168.9.10", gateway = "192.168.9.1" },
      ]
    }
    iot = {
      vm_id              = 111
      memory_mb          = 4096
      memory_floating_mb = 2048
      swap_mb            = 1024
      disk_gb            = 20
      tags               = ["lan", "docker"]
      dns_domain         = "home.arpa"
      ansible_groups     = ["docker", "komodo_agent", "gpu"]
      hostpci            = "intel-gpu-vf2"
      networks = [
        { bridge = "vmbr0", ip = "192.168.9.11", gateway = "192.168.9.1" },
      ]
    }
    frontend = {
      vm_id              = 310
      memory_mb          = 2048
      memory_floating_mb = 1024
      swap_mb            = 1024
      disk_gb            = 20
      tags               = ["frontend", "dmz", "docker"]
      dns_domain         = "home.arpa"
      ansible_groups     = ["docker", "komodo_agent"]
      networks = [
        { bridge = "vmbr30", ip = "10.0.0.10", gateway = "10.0.0.1" },
      ]
    }
  }

  # Derives {group_name => [host names]} from each VM's ansible_groups, so
  # inventory.tftpl can emit extra Ansible groups (e.g. "db") without every
  # VM needing to belong to them - keeps a VM that doesn't need a group out
  # of any group-scoped playbook automatically, just by omitting the field.
  vm_group_names = toset(flatten([
    for name, cfg in local.vms : try(cfg.ansible_groups, [])
  ]))

  vm_groups_hosts = {
    for g in local.vm_group_names : g => [
      for name, cfg in local.vms : name if contains(try(cfg.ansible_groups, []), g)
    ]
  }
}
