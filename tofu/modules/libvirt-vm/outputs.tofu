locals {
  lease_interface_indexes = [
    for idx, nic in local.effective_interfaces : idx
    if nic.network_name != null
  ]
  interface_samples = try([
    for idx, iface in data.libvirt_domain_interface_addresses.vm.interfaces : {
      config_index = local.interface_address_source == "lease" ? try(local.lease_interface_indexes[idx], null) : try(
        tonumber(regexall("^enp0s([0-9]+)$", try(iface.name, ""))[0][0]) - 2,
        idx
      )
      mac_address = iface.hwaddr
      ipv4_addresses = [
        for addr in iface.addrs :
        split("/", addr.addr)[0]
        if length(regexall(":", addr.addr)) == 0
      ]
    }
    if iface.hwaddr != "00:00:00:00:00:00"
  ], [])
  interface_index_by_label = {
    for idx, nic in local.effective_interfaces :
    nic.label => idx
  }
  expected_static_ip_address_output = var.expected_static_ip != null ? split("/", var.expected_static_ip)[0] : null
  expected_static_interface_index = var.expected_static_ip_interface_label != null ? try(
    local.interface_index_by_label[var.expected_static_ip_interface_label],
    null
  ) : null
  interface_ipv4 = [
    for idx, cfg in local.effective_interfaces : {
      index        = idx
      label        = cfg.label
      network_name = cfg.network_name
      bridge       = cfg.bridge
      is_bridge    = cfg.bridge != null
      mac_address  = try([for iface in local.interface_samples : iface.mac_address if iface.config_index == idx][0], try(cfg.mac_address, null))
      ip_addresses = distinct(concat(
          (
          local.expected_static_ip_address_output != null &&
          idx == local.expected_static_interface_index
          ) ? [local.expected_static_ip_address_output] : [],
        flatten([
          for iface in local.interface_samples :
          iface.ipv4_addresses
          if iface.config_index == idx
        ])
      ))
    }
  ]
  prioritized_interfaces = concat(
    [for iface in local.interface_ipv4 : iface if iface.is_bridge],
    [for iface in local.interface_ipv4 : iface if iface.is_bridge == false]
  )
  prioritized_ip_addresses = distinct(flatten([
    for iface in local.prioritized_interfaces : iface.ip_addresses
  ]))
  discovered_ipv4_addresses = distinct(flatten([
    for iface in local.interface_samples : iface.ipv4_addresses
  ]))
  static_ip_detected = (
  local.expected_static_ip_address_output != null &&
  local.interface_address_source == "agent"
  ) ? contains(local.discovered_ipv4_addresses, local.expected_static_ip_address_output) : null
}
output "ip_addresses" {
  description = "All IPv4 addresses across all interfaces (bridge-first), including configured expected_static_ip fallback."
  value       = local.prioritized_ip_addresses
}
output "primary_ip_address" {
  description = "Primary IPv4 address, preferring bridge interfaces and configured expected_static_ip."
  value       = try(local.prioritized_ip_addresses[0], null)
}
output "network_interfaces" {
  description = "Per-interface network details and IPv4 addresses (bridge-first, with expected_static_ip fallback)."
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
output "static_ip_detected" {
  description = "True when expected_static_ip is discovered via guest-agent data; null when guest-agent probing is not used."
  value       = local.static_ip_detected
}
