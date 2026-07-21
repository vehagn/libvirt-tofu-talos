output "primary_ip_address" {
  description = "Primary IPv4 address, preferring bridge interfaces"
  value       = module.vm.primary_ip_address
}

output "ip_addresses" {
  description = "All VM IPv4 addresses across all interfaces (bridge-first ordering)"
  value       = module.vm.ip_addresses
}

output "name" {
  description = "VM name"
  value       = module.vm.name
}
