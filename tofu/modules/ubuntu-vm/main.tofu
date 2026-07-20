locals {
  hostname = coalesce(var.hostname, var.name)
  network_names = keys(var.networks)
  # Select the primary network name, either from the explicit variable or the first network in the list.
  effective_primary_network_name = coalesce(
    var.primary_network_name,
    local.network_names[0]
  )
  primary_interface_index = index(local.network_names, local.effective_primary_network_name)
  # qemu/libvirt Ubuntu guest names are typically enp0s2, enp0s3, ...
  primary_interface_name    = "enp0s${local.primary_interface_index + 2}"
  secondary_interface_names = [for idx, _ in local.network_names : "enp0s${idx + 2}" if idx != local.primary_interface_index]
  primary_network = try(var.networks[local.effective_primary_network_name], {})
}
resource "libvirt_volume" "os" {
  name     = "${var.name}-os.qcow2"
  pool     = var.pool_name
  capacity = var.os_disk_size_gb * 1024 * 1024 * 1024
  target = {
    format = {
      type = "qcow2"
    }
  }
  create = {
    content = {
      url = var.base_image_source
    }
  }
}
resource "libvirt_volume" "extra" {
  for_each = { for d in var.extra_disks : d.name => d }
  name     = "${var.name}-${each.key}.qcow2"
  pool     = coalesce(each.value.pool, var.pool_name)
  capacity = each.value.size_gb * 1024 * 1024 * 1024
  target = {
    format = {
      type = "qcow2"
    }
  }
}
resource "libvirt_cloudinit_disk" "init" {
  name = "${var.name}-cloudinit.iso"
  user_data = templatefile("${path.module}/templates/user-data.tftpl", {
    hostname            = local.hostname
    ssh_authorized_keys = var.ssh_authorized_keys
    extra_packages      = var.extra_packages
    write_files         = var.write_files
    extra_runcmd        = var.extra_runcmd
  })
  meta_data = templatefile("${path.module}/templates/meta-data.tftpl", {
    instance_id = var.name
    hostname    = local.hostname
  })
  network_config = templatefile("${path.module}/templates/network-config.tftpl", {
    primary_interface_name    = local.primary_interface_name
    secondary_interface_names = local.secondary_interface_names
    static_ip                 = var.static_ip_address
    gateway                   = try(local.primary_network.gateway, null)
    dns_servers               = try(local.primary_network.dns_servers, [])
  })
}
resource "libvirt_volume" "cloudinit" {
  name = "${var.name}-cloudinit.iso"
  pool = var.pool_name
  create = {
    content = {
      url = libvirt_cloudinit_disk.init.path
    }
  }
}
module "vm" {
  source = "../libvirt-vm"
  name       = var.name
  hostname   = local.hostname
  memory_mb  = var.memory_mb
  vcpu_count = var.vcpu_count
  os_disk = {
    pool   = libvirt_volume.os.pool
    volume = libvirt_volume.os.name
  }
  cloudinit_disk = {
    pool   = libvirt_volume.cloudinit.pool
    volume = libvirt_volume.cloudinit.name
  }
  # Preserve var.extra_disks ordering so device names (vdb, vdc, ...) are stable.
  extra_disks = [
    for disk in var.extra_disks : {
      pool   = libvirt_volume.extra[disk.name].pool
      volume = libvirt_volume.extra[disk.name].name
    }
  ]
  networks = var.networks
  expected_static_ip                  = var.static_ip_address
  expected_static_ip_interface_label  = var.static_ip_address != null ? local.effective_primary_network_name : null
  static_ip_detection_timeout_seconds = var.static_ip_detection_timeout_seconds
}
