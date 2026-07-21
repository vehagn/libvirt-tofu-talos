locals {
  # Interfaces keyed by their config index in var.networks (alphabetical).
  configured_interfaces = [
    for idx, name in local.network_names : {
      index        = idx
      label        = name
      mode         = var.networks[name].mode
      is_bridge    = var.networks[name].mode == "bridge"
      network_name = var.networks[name].mode != "bridge" ? var.networks[name].name : null
      bridge       = var.networks[name].mode == "bridge" ? var.networks[name].bridge_name : null
      # Guest-OS config passthrough (used by ubuntu-vm cloud-init generation; may be null).
      static_ip   = var.networks[name].static_ip
      gateway     = var.networks[name].gateway
      dns_servers = var.networks[name].dns_servers
      # Requested MAC (the actually-assigned one comes from the sample; see interface_ipv4 below).
      requested_mac_address = var.networks[name].mac_address
    }
  ]

  # Filter interface samples returned by the data source to IPv4 only, skipping the fake
  # 00:00:00:00:00:00 entries libvirt returns for interfaces without a hwaddr yet.
  raw_interface_samples = try([
    for iface in data.libvirt_domain_interface_addresses.vm.interfaces : {
      guest_name  = try(iface.name, "")
      mac_address = iface.hwaddr
      ipv4_addresses = [
        for addr in iface.addrs : split("/", addr.addr)[0]
        if length(regexall(":", addr.addr)) == 0
      ]
    } if iface.hwaddr != "00:00:00:00:00:00"
  ], [])

  # NAT/none interfaces without static IPs are the only ones libvirt sees a lease for; when
  # source = "lease", the data-source array contains only those. Map lease-index → config-index.
  lease_eligible_indexes = [
    for cfg in local.configured_interfaces : cfg.index
    if !cfg.is_bridge && cfg.static_ip == null
  ]

  # Map each raw sample to its position in var.networks.
  # - source = "lease": the Nth sample is the Nth lease-eligible network.
  # - source = "agent": guest reports device names (enp0sN); N-2 is the config index (libvirt
  #   attaches interfaces starting at PCI slot 2). Fall back to array order if the regex fails.
  interface_samples = [
    for idx, sample in local.raw_interface_samples : merge(sample, {
      config_index = (local.interface_address_source == "lease" ?
        try(local.lease_eligible_indexes[idx], null) :
        try(tonumber(regexall("^enp0s([0-9]+)$", sample.guest_name)[0][0]) - 2, idx)
      )
    })
  ]

  # Merge observed IPs (and MAC, if the caller didn't set one) into each configured interface.
  # Prepend each interface's static_ip as a fallback: cloud-init may configure the address before
  # the guest agent reports it, and callers rely on ip_addresses being populated at apply time.
  discovered_ipv4_addresses = distinct(flatten([for s in local.interface_samples : s.ipv4_addresses]))

  interface_ipv4 = [
    for cfg in local.configured_interfaces : merge(cfg, {
      mac_address = try(
        [for s in local.interface_samples : s.mac_address if s.config_index == cfg.index][0],
        cfg.requested_mac_address
      )
      ip_addresses = distinct(concat(
        cfg.static_ip != null ? [split("/", cfg.static_ip)[0]] : [],
        flatten([for s in local.interface_samples : s.ipv4_addresses if s.config_index == cfg.index])
      ))
      # True when the configured static IP has been observed in the guest agent's report.
      # Null when detection isn't running via agent (lease source) or the interface has no static.
      static_ip_detected = (
        cfg.static_ip != null && local.interface_address_source == "agent"
      ) ? contains(local.discovered_ipv4_addresses, split("/", cfg.static_ip)[0]) : null
    })
  ]

  # Bridge-first ordering: bridge attachments are usually the reachable IP the operator wants.
  prioritized_interfaces = concat(
    [for i in local.interface_ipv4 : i if i.is_bridge],
    [for i in local.interface_ipv4 : i if !i.is_bridge]
  )
  prioritized_ip_addresses = distinct(flatten([for i in local.prioritized_interfaces : i.ip_addresses]))
}

output "ip_addresses" {
  description = "All IPv4 addresses across all interfaces (bridge-first), including static_ip fallbacks."
  value       = local.prioritized_ip_addresses
}

output "primary_ip_address" {
  description = "First IPv4 address after bridge-first ordering; null if none observed."
  value       = try(local.prioritized_ip_addresses[0], null)
}

output "network_interfaces" {
  description = <<-EOT
    Per-interface details keyed by label with observed IPv4 addresses (bridge-first ordering).
    Each entry includes static_ip (configured value), static_ip_detected (bool when detection
    runs via guest agent, null otherwise), gateway, dns_servers, and mac_address.
  EOT
  value       = local.prioritized_interfaces
}

output "name" {
  description = "VM name"
  value       = libvirt_domain.vm.name
}

output "uuid" {
  description = "libvirt domain UUID for the VM"
  value       = libvirt_domain.vm.uuid
}
