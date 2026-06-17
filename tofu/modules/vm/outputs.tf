output "ip_address" {
  description = "IP address assigned via DHCP (available after boot)"
  value       = try(libvirt_domain.vm.network_interface[0].addresses[0], null)
}

output "name" {
  description = "VM name"
  value       = libvirt_domain.vm.name
}
