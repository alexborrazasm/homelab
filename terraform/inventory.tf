resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/vms.yml"
  file_permission = "0640"

  content = templatefile("${path.module}/inventory.tftpl", {
    vms    = local.vms
    groups = local.vm_groups_hosts
  })
}
