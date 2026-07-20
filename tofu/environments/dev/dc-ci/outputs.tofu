output "vms" {
  description = "Bridge-first connection details and network inventory for each Ubuntu VM"
  value = {
    for name, vm in module.ubuntu : name => {
      primary_ip         = vm.primary_ip_address
      ssh                = vm.primary_ip_address != null ? "ssh ubuntu@${vm.primary_ip_address}" : null
      ip_addresses       = vm.ip_addresses
      static_ip_detected = vm.static_ip_detected
      networks           = vm.network_interfaces
    }
  }
}
output "networks" {
  description = "Configured libvirt networks"
  value       = module.networks.networks
}
