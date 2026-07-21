module "ubuntu" {
  for_each = var.ubuntu_vms
  source   = "../../../modules/ubuntu-vm"

  name            = each.key
  pool_name       = libvirt_pool.dev.name
  memory_mb       = each.value.memory_mb
  vcpu_count      = each.value.vcpu_count
  os_disk_size_gb = each.value.os_disk_size_gb
  extra_packages  = each.value.extra_packages

  networks            = { (each.value.network_name) = local.networks[each.value.network_name] }
  ssh_authorized_keys = var.ssh_authorized_keys
}
