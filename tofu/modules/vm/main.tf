# Base cloud image — downloaded once per pool, used as a shared backing store
resource "libvirt_volume" "base" {
  name = "${var.name}-base.qcow2"
  pool = var.pool_name

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

# Per-VM overlay disk — only stores deltas from the base image
resource "libvirt_volume" "disk" {
  name          = "${var.name}.qcow2"
  pool          = var.pool_name
  capacity      = var.disk_size_gb
  capacity_unit = "GiB"

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.base.path
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "init" {
  name = "${var.name}-cloudinit.iso"

  user_data = templatefile("${path.module}/templates/user-data.tftpl", {
    hostname            = var.hostname
    ssh_authorized_keys = var.ssh_authorized_keys
  })

  meta_data = templatefile("${path.module}/templates/meta-data.tftpl", {
    instance_id = var.name
    hostname    = var.hostname
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

resource "libvirt_domain" "vm" {
  name        = var.name
  type        = "kvm"
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.vcpu_count

  os = {
    type = "hvm"
  }

  devices = {
    disks = [
      {
        device = "disk"
        target = { dev = "vda", bus = "virtio" }
        source = {
          volume = {
            pool   = libvirt_volume.disk.pool
            volume = libvirt_volume.disk.name
          }
        }
        driver = {
          name  = "qemu"
          type  = "qcow2"
          cache = "none"
        }
      },
      {
        device = "cdrom"
        target = { dev = "hda", bus = "ide" }
        source = {
          volume = {
            pool   = libvirt_volume.cloudinit.pool
            volume = libvirt_volume.cloudinit.name
          }
        }
      }
    ]

    interfaces = [
      {
        source = {
          network = {
            network = var.network_name
          }
        }
        model = {
          type = "virtio"
        }
        wait_for_ip = {
          timeout = 300
          source  = "lease"
        }
      }
    ]
  }
}

data "libvirt_domain_interface_addresses" "vm" {
  domain = libvirt_domain.vm.uuid
  source = "lease"
}
