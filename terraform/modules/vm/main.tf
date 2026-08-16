variable "name" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "node_name" {
  type    = string
  default = "pve"
}

variable "template_vm_id" {
  type    = number
  default = 9000
}

variable "memory_mb" {
  type = number
}

variable "memory_floating_mb" {
  type = number
}

variable "disk_gb" {
  type = number
}

variable "networks" {
  type = list(object({
    bridge  = string
    ip      = string
    gateway = optional(string)
  }))
}

variable "ssh_public_key" {
  type = string
}

variable "cloudinit_upgrade" {
  description = "Run a full package upgrade via cloud-init on first boot."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Proxmox tags. Sorted automatically - Proxmox always sorts them server-side and would otherwise show permanent drift."
  type        = list(string)
  default     = []
}

variable "dns_domain" {
  description = "DNS search domain. Optional - null skips setting it."
  type        = string
  default     = null
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id
  tags      = sort(var.tags)

  clone {
    vm_id = var.template_vm_id
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
    floating  = var.memory_floating_mb
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.disk_gb
  }

  dynamic "network_device" {
    for_each = var.networks
    content {
      bridge = network_device.value.bridge
    }
  }

  initialization {
    upgrade = var.cloudinit_upgrade

    # DNS server is that VM's own gateway (each network segment's router
    # doubles as its resolver) - not a fixed IP, so VMs on vmbr20/vmbr30
    # don't end up pointed at a DNS server they have no route to.
    dns {
      domain  = var.dns_domain
      servers = [var.networks[0].gateway]
    }

    dynamic "ip_config" {
      for_each = var.networks
      content {
        ipv4 {
          address = "${ip_config.value.ip}/24"
          gateway = ip_config.value.gateway
        }
      }
    }

    user_account {
      username = "alex"
      keys     = [var.ssh_public_key]
    }
  }
}
