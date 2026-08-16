data "proxmox_version" "pve" {}

output "pve_version" {
  value = data.proxmox_version.pve.version
}
