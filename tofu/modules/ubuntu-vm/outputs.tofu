output "ip_addresses" {
  description = "All VM IPv4 addresses across all interfaces (bridge-first ordering)"
  value       = module.vm.ip_addresses
}
output "primary_ip_address" {
  description = "Primary IPv4 address, preferring bridge interfaces"
  value       = module.vm.primary_ip_address
}
output "network_interfaces" {
  description = "Per-interface details with observed IPv4 addresses, static_ip, static_ip_detected, gateway, dns_servers (bridge-first ordering)"
  value       = module.vm.network_interfaces
}
output "name" {
  description = "VM name"
  value       = module.vm.name
}
