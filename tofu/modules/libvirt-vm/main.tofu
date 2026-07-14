locals {
  hostname = coalesce(var.hostname, var.name)

  extra_disk_entries = [
    for i, disk in var.extra_disks : {
      device = "disk"
      target = { dev = "vd${chr(98 + i)}", bus = "virtio" }
      source = {
        volume = {
          pool   = disk.pool
          volume = disk.volume
        }
      }
      driver = {
        name  = "qemu"
        type  = "qcow2"
        cache = "none"
      }
    }
  ]

  cloudinit_entry = var.cloudinit_disk != null ? [
    {
      device = "cdrom"
      target = { dev = "hda", bus = "ide" }
      source = {
        volume = {
          pool   = var.cloudinit_disk.pool
          volume = var.cloudinit_disk.volume
        }
      }
    }
  ] : []

  interface_entries = [
    for iface in var.interfaces : {
      mac = iface.mac_address != null ? { address = iface.mac_address } : null
      source = {
        bridge  = iface.bridge != null ? { bridge = iface.bridge } : null
        network = iface.network_name != null ? { network = iface.network_name } : null
      }
      model = {
        type = "virtio"
      }
      wait_for_ip = iface.wait_for_ip ? {
        timeout = 300
        source  = iface.bridge != null ? "agent" : "lease"
      } : null
    }
  ]
}

resource "libvirt_domain" "vm" {
  name        = var.name
  type        = "kvm"
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.vcpu_count
  running     = true

  cpu = var.cpu_mode != null ? { mode = var.cpu_mode } : null

  os = {
    type = "hvm"
  }

  devices = {
    disks = concat(
      [
        {
          device = "disk"
          target = { dev = "vda", bus = "virtio" }
          source = {
            volume = {
              pool   = var.os_disk.pool
              volume = var.os_disk.volume
            }
          }
          driver = {
            name  = "qemu"
            type  = "qcow2"
            cache = "none"
          }
        }
      ],
      local.extra_disk_entries,
      local.cloudinit_entry
    )

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

    interfaces = local.interface_entries
  }
}

data "libvirt_domain_interface_addresses" "vm" {
  domain = libvirt_domain.vm.uuid
  source = "agent"
}
