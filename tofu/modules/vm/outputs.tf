output "ip_address" {
  description = "IP address assigned via DHCP (available after boot)"
  value       = try(data.libvirt_domain_interface_addresses.vm.interfaces[0].addrs[0].addr, null)
}

output "name" {
  description = "VM name"
  value       = libvirt_domain.vm.name
}
