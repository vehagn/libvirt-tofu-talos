locals {
  hostname = coalesce(var.hostname, var.name)
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
    user_password       = var.user_password
    extra_packages      = var.extra_packages
    write_files         = var.write_files
    extra_runcmd        = var.extra_runcmd
  })

  meta_data = templatefile("${path.module}/templates/meta-data.tftpl", {
    instance_id = var.name
    hostname    = local.hostname
  })

  network_config = var.static_ip != null ? templatefile("${path.module}/templates/network-config.tftpl", {
    static_ip   = var.static_ip
    gateway     = var.gateway
    dns_servers = var.dns_servers
  }) : null
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

  interfaces = var.interfaces
}
