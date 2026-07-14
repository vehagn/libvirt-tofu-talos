output "ip_address" {
  description = "Primary VM IP address"
  value       = module.vm.ip_address
}

output "ip_addresses" {
  description = "All VM IPv4 addresses across all interfaces"
  value       = module.vm.ip_addresses
}

output "name" {
  description = "VM name"
  value       = module.vm.name
}
