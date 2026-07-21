locals {
  hostname = coalesce(var.hostname, var.name)

  extra_disk_entries = [
    for i, disk in var.extra_disks : {
      device = "disk"
      # vdb, vdc, vdd, ... (98 is the ASCII code for 'b')
      target = { dev = "vd${chr(98 + i)}", bus = "virtio" }
      source = { volume = { pool = disk.pool, volume = disk.volume } }
      driver = { name = "qemu", type = "qcow2", cache = "none" }
    }
  ]

  cloudinit_entry = var.cloudinit_disk == null ? [] : [
    {
      device = "cdrom"
      target = { dev = "hda", bus = "ide" }
      source = { volume = { pool = var.cloudinit_disk.pool, volume = var.cloudinit_disk.volume } }
    }
  ]

  network_names = keys(var.networks)

  # Wait strategy per interface:
  # - bridge attachments never lease-wait (libvirt has no view of DHCP on an external bridge)
  # - NAT/none without a static_ip: lease-wait unless the caller opted out via wait_for_ip = false
  # - NAT/none with a static_ip: no lease-wait (a statically-configured guest never DHCPs)
  lease_wait_by_name = {
    for name, cfg in var.networks :
    name => cfg.mode != "bridge" && cfg.wait_for_ip && cfg.static_ip == null
  }
  any_lease_wait = anytrue(values(local.lease_wait_by_name))

  # Fallback: when nothing lease-waits, block on the guest agent reporting the first configured
  # static IP. This ensures bridge-only VMs with a static IP have observable reachability before
  # terraform apply returns.
  agent_wait_target_name = try(
    [for name, cfg in var.networks : name if cfg.static_ip != null][0],
    null
  )
  agent_wait_active = local.agent_wait_target_name != null && !local.any_lease_wait

  interface_entries = [
    for name, cfg in var.networks : {
      mac = cfg.mac_address != null ? { address = cfg.mac_address } : null
      source = {
        bridge  = cfg.mode == "bridge" ? { bridge = cfg.bridge_name } : null
        network = cfg.mode != "bridge" ? { network = cfg.name } : null
      }
      model = { type = "virtio" }
      wait_for_ip = (
        local.lease_wait_by_name[name] ?
        { timeout = 300, source = "lease" } :
        local.agent_wait_active && name == local.agent_wait_target_name ?
        { timeout = var.static_ip_detection_timeout_seconds, source = "agent" } :
        null
      )
    }
  ]

  interface_address_source = local.any_lease_wait ? "lease" : "agent"
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
          source = { volume = { pool = var.os_disk.pool, volume = var.os_disk.volume } }
          driver = { name = "qemu", type = "qcow2", cache = "none" }
        }
      ],
      local.extra_disk_entries,
      local.cloudinit_entry
    )
    serials  = [{ target = { type = "isa-serial", port = 0 } }]
    consoles = [{ target = { type = "serial", port = 0 } }]
    channels = [
      {
        source = { unix = {} }
        target = { virt_io = { name = "org.qemu.guest_agent.0" } }
      }
    ]
    interfaces = local.interface_entries
  }
}

data "libvirt_domain_interface_addresses" "vm" {
  domain = libvirt_domain.vm.uuid
  source = local.interface_address_source
}
