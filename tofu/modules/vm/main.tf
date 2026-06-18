resource "libvirt_volume" "disk" {
  name          = "${var.name}.qcow2"
  pool          = var.pool_name
  capacity      = var.disk_size_gb * 1024 * 1024 * 1024

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

resource "libvirt_cloudinit_disk" "init" {
  name = "${var.name}-cloudinit.iso"

  user_data = templatefile("${path.module}/templates/user-data.tftpl", {
    hostname            = var.hostname
    ssh_authorized_keys = var.ssh_authorized_keys
    user_password       = var.user_password
  })

  meta_data = templatefile("${path.module}/templates/meta-data.tftpl", {
    instance_id = var.name
    hostname    = var.hostname
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

resource "libvirt_domain" "vm" {
  name        = var.name
  type        = "kvm"
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.vcpu_count
  running     = true

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

    serials = [
      {
        target = {
          type = "isa-serial"
          port = 0
        }
      }
    ]

    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    channels = [
      {
        source = {
          unix = {}
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]

    interfaces = [
      {
        source = {
          bridge  = var.network_bridge != null ? { bridge = var.network_bridge } : null
          network = var.network_name != null ? { network = var.network_name } : null
        }
        model = {
          type = "virtio"
        }
        wait_for_ip = var.static_ip == null ? {
          timeout = 300
          source  = var.network_bridge != null ? "agent" : "lease"
        } : null
      }
    ]
  }
}

data "libvirt_domain_interface_addresses" "vm" {
  count  = var.static_ip == null ? 1 : 0
  domain = libvirt_domain.vm.uuid
  source = var.network_bridge != null ? "agent" : "lease"
}
