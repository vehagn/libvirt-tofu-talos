locals {
  hostname = coalesce(var.hostname, var.name)
  extra_disk_entries = [
    for i, disk in var.extra_disks : {
      device = "disk"
      // vdb, vdc, vdd, ... for extra disks, 98 is the ASCII code for 'b'
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
  expected_static_ip_address = var.expected_static_ip != null ? split("/", var.expected_static_ip)[0] : null
  network_names = keys(var.networks)
  interfaces_from_networks = [
    for network_name in local.network_names : {
      label        = network_name
      network_name = try(var.networks[network_name].mode, null) == "bridge" ? null : try(var.networks[network_name].name, network_name)
      bridge       = try(var.networks[network_name].mode, null) == "bridge" ? try(var.networks[network_name].bridge_name, network_name) : null
      mac_address  = null
      wait_for_ip  = (
      try(var.networks[network_name].mode, null) != "bridge" &&
      (
      var.expected_static_ip == null ||
      var.expected_static_ip_interface_label == null ||
      network_name != var.expected_static_ip_interface_label
      )
      )
    }
  ]
  effective_interfaces = length(var.interfaces) > 0 ? var.interfaces : local.interfaces_from_networks
  interface_entries = [
    for iface in local.effective_interfaces : {
      mac = iface.mac_address != null ? { address = iface.mac_address } : null
      source = {
        bridge  = iface.bridge != null ? { bridge = iface.bridge } : null
        network = iface.network_name != null ? { network = iface.network_name } : null
      }
      model = {
        type = "virtio"
      }
      wait_for_ip = iface.wait_for_ip && iface.network_name != null ? {
        timeout = 300
        source  = "lease"
      } : (
        local.wait_for_static_ip_on_create && iface.label == var.expected_static_ip_interface_label ? {
        timeout = var.static_ip_detection_timeout_seconds
        source  = "agent"
      } : null
      )
    }
  ]
  has_lease_interfaces = anytrue([
    for iface in local.effective_interfaces :
    iface.network_name != null
    ])
  has_lease_wait_interfaces = anytrue([
    for iface in local.effective_interfaces :
    iface.network_name != null && iface.wait_for_ip
    ])
  wait_for_static_ip_on_create = (
  local.expected_static_ip_address != null &&
  local.has_lease_wait_interfaces == false
  )
  interface_address_source = (
  local.has_lease_wait_interfaces ||
  (local.expected_static_ip_address == null && local.has_lease_interfaces)
  ) ? "lease" : "agent"
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
  source = local.interface_address_source
}
