locals {
  hostname      = coalesce(var.hostname, var.name)
  network_names = keys(var.networks)

  # The primary network is the interface that inherits DHCP routes/DNS when it doesn't have a
  # static IP configured — otherwise its own gateway/dns_servers apply. Bridges are preferred
  # since they typically sit on the physical LAN; falls back to the first network alphabetically.
  primary_network_name = try(
    [for n in local.network_names : n if var.networks[n].mode == "bridge"][0],
    local.network_names[0]
  )

  # Alphabetical key order matches libvirt attachment order — enp0s2 is the first network, enp0s3 the second, etc.
  cloud_init_interfaces = [
    for idx, name in local.network_names : {
      device      = "enp0s${idx + 2}"
      is_primary  = name == local.primary_network_name
      static_ip   = var.networks[name].static_ip
      gateway     = var.networks[name].gateway
      dns_servers = var.networks[name].dns_servers
    }
  ]
}

resource "libvirt_volume" "os" {
  name     = "${var.name}-os.qcow2"
  pool     = var.pool_name
  capacity = var.os_disk_size_gb * 1024 * 1024 * 1024
  target = {
    format = { type = "qcow2" }
  }
  create = {
    content = { url = var.base_image_source }
  }
}

resource "libvirt_volume" "extra" {
  for_each = { for d in var.extra_disks : d.name => d }
  name     = "${var.name}-${each.key}.qcow2"
  pool     = coalesce(each.value.pool, var.pool_name)
  capacity = each.value.size_gb * 1024 * 1024 * 1024
  target = {
    format = { type = "qcow2" }
  }
}

# libvirt_cloudinit_disk (v0.9) only writes to the "default" pool, so we wrap the generated ISO
# in a libvirt_volume placed in the target pool.
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
    interfaces = local.cloud_init_interfaces
  })
}

resource "libvirt_volume" "cloudinit" {
  name = "${var.name}-cloudinit.iso"
  pool = var.pool_name
  create = {
    content = { url = libvirt_cloudinit_disk.init.path }
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

  networks                            = var.networks
  static_ip_detection_timeout_seconds = var.static_ip_detection_timeout_seconds
}
