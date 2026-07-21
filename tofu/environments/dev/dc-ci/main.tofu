resource "libvirt_pool" "dev" {
  name = "dev"
  type = "dir"
  target = {
    path = var.pool_path
  }
  create = {
    build     = true
    start     = true
    autostart = true
  }
}

# Standard network catalog shared across environments. Merge with additions or full-entry
# overrides if this environment needs to diverge:
#   networks = merge(module.catalog.networks, { datacenter = { mode = "bridge", ... } })
module "catalog" {
  source           = "../../../modules/networks-catalog"
  bridge_interface = var.bridge_interface
}

module "networks" {
  source   = "../../../modules/libvirt-networks"
  networks = module.catalog.networks
}

# For each VM, merge the caller's per-network overrides (static_ip, mac_address, ...) into the
# corresponding catalog entry. Null override fields are stripped so catalog defaults survive —
# an unset static_ip stays null instead of clobbering a catalog value.
locals {
  vm_networks = {
    for vm_name, vm_cfg in var.ubuntu_vms :
    vm_name => {
      for network_name, overrides in vm_cfg.networks :
      network_name => merge(
        module.networks.networks[network_name],
        { for k, v in overrides : k => v if v != null }
      )
    }
  }
}

module "ubuntu" {
  for_each = var.ubuntu_vms
  source   = "../../../modules/ubuntu-vm"

  name                = each.key
  pool_name           = libvirt_pool.dev.name
  vcpu_count          = each.value.vcpu_count
  memory_mb           = each.value.memory_mb
  os_disk_size_gb     = each.value.os_disk_size_gb
  extra_packages      = each.value.extra_packages
  extra_disks         = each.value.extra_disks
  networks            = local.vm_networks[each.key]
  ssh_authorized_keys = var.ssh_authorized_keys
}
