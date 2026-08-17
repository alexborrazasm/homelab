module "vm" {
  source   = "./modules/vm"
  for_each = local.vms

  name               = each.key
  vm_id              = each.value.vm_id
  memory_mb          = each.value.memory_mb
  memory_floating_mb = each.value.memory_floating_mb
  disk_gb            = each.value.disk_gb
  networks           = each.value.networks
  ssh_public_key     = local.ssh_public_key
  cloudinit_upgrade  = try(each.value.cloudinit_upgrade, true)
  tags               = try(each.value.tags, [])
  dns_domain         = try(each.value.dns_domain, null)
  hostpci            = try(each.value.hostpci, null)
}
