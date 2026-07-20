output "ip_addresses" {
  description = "All VM IPv4 addresses across all interfaces (bridge-first ordering)"
  value       = module.vm.ip_addresses
}
output "primary_ip_address" {
  description = "Primary IPv4 address, preferring bridge interfaces"
  value       = module.vm.primary_ip_address
}
output "network_interfaces" {
  description = "Per-interface network details and IPv4 addresses (bridge-first ordering)"
  value       = module.vm.network_interfaces
}
output "name" {
  description = "VM name"
  value       = module.vm.name
}
output "static_ip_detected" {
  description = "Static IP detection status from libvirt-vm (null when detection is disabled)"
  value       = module.vm.static_ip_detected
}
