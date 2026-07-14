locals {
  ssh_target = regex("qemu\\+ssh://([^/]+)", var.libvirt_uri)[0]
}

module "node" {
  for_each = var.nodes

  source = "../../../modules/talos-vm"

  name              = each.key
  pool_name         = libvirt_pool.talos.name
  base_image_path   = local.node_base_image_path[each.key]
  vcpu_count        = coalesce(each.value.vcpu, var.node_vcpu)
  memory_mb         = coalesce(each.value.memory_mb, var.node_memory_mb)
  os_disk_size_gb   = coalesce(each.value.os_disk_gb, var.node_os_disk_gb)
  data_disk_size_gb = coalesce(each.value.data_disk_gb, var.node_data_disk_gb)
  bridge            = var.vm_bridge_interface
  mac_address       = each.value.mac_address
  ssh_target        = local.ssh_target
  cluster_vip       = var.cluster_vip
}
