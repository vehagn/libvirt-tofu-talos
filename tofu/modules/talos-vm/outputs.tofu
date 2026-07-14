output "ip_address" {
  description = "DHCP-assigned IPv4 address of the primary NIC"
  value       = data.external.node_ip.result.ip
}

output "name" {
  description = "VM name"
  value       = module.vm.name
}

output "uuid" {
  description = "libvirt domain UUID"
  value       = module.vm.uuid
}
