locals {
  libvirt_pool = "/var/lib/libvirt/images/pool-0"
  ubuntu_defaults = {
    vcpu_count           = 2
    memory_mb            = 2048
    os_disk_size_gb      = 20
    extra_packages       = []
    networks             = ["bridge", "management"]
    static_ip_address    = null
    primary_network_name = "bridge"
    extra_disks          = []
    ssh_authorized_keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICN+u3bnDmvw5AdqpIWTbqWKVuDnztP8e1hil+YQHYvY vegard-hagen@sr-612208"
    ]
  }
  # Only per-VM overrides; defaults are applied below.
  ubuntu_instance_overrides = {
    ubuntu-01 = {
      static_ip_address = "10.0.1.163"
    }
  }
  # Final VM config: defaults + overrides.
  ubuntu_instances = {
    for vm_name, vm_cfg in local.ubuntu_instance_overrides :
    vm_name => merge(local.ubuntu_defaults, vm_cfg)
  }
}
resource "libvirt_pool" "dev" {
  name = "dev"
  type = "dir"
  target = {
    path = local.libvirt_pool
  }
  create = {
    build     = true
    start     = true
    autostart = true
  }
}
module "networks" {
  source = "../../../modules/libvirt-networks"
}
module "ubuntu" {
  for_each   = local.ubuntu_instances
  source     = "../../../modules/ubuntu-vm"
  depends_on = [module.networks]
  name                 = each.key
  pool_name            = libvirt_pool.dev.name
  vcpu_count           = each.value.vcpu_count
  memory_mb            = each.value.memory_mb
  os_disk_size_gb      = each.value.os_disk_size_gb
  extra_packages       = each.value.extra_packages
  extra_disks          = each.value.extra_disks
  networks             = {
    for network_name in each.value.networks :
    network_name => module.networks.networks[network_name]
  }
  primary_network_name = each.value.primary_network_name
  static_ip_address    = each.value.static_ip_address
  ssh_authorized_keys = each.value.ssh_authorized_keys
}
