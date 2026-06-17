# Base cloud image — downloaded once per pool, used as a shared backing store
resource "libvirt_volume" "base" {
  name   = "${var.name}-base.qcow2"
  pool   = var.pool_name
  source = var.base_image_source
  format = "qcow2"
}

# Per-VM overlay disk — only stores deltas from the base image
resource "libvirt_volume" "disk" {
  name           = "${var.name}.qcow2"
  pool           = var.pool_name
  base_volume_id = libvirt_volume.base.id
  size           = var.disk_size_gb * 1073741824
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "init" {
  name = "${var.name}-cloudinit.iso"
  pool = var.pool_name

  user_data = templatefile("${path.module}/templates/user-data.tftpl", {
    hostname            = var.hostname
    ssh_authorized_keys = var.ssh_authorized_keys
  })

  meta_data = templatefile("${path.module}/templates/meta-data.tftpl", {
    instance_id = var.name
    hostname    = var.hostname
  })
}

resource "libvirt_domain" "vm" {
  name   = var.name
  memory = var.memory_mb
  vcpu   = var.vcpu_count

  cloudinit = libvirt_cloudinit_disk.init.id

  disk {
    volume_id = libvirt_volume.disk.id
  }

  network_interface {
    network_name   = var.network_name
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
