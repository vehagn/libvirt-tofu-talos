output "vms" {
  description = "Per-VM IP inventory. by_network exposes ip_addresses + static_ip + static_ip_detected per interface."
  value = {
    for name, vm in module.ubuntu : name => {
      ip_addresses = vm.ip_addresses
      ssh          = try("ssh ubuntu@${vm.ip_addresses[0]}", null)
      by_network = {
        for iface in vm.network_interfaces : iface.label => {
          ip_addresses       = iface.ip_addresses
          static_ip          = iface.static_ip
          static_ip_detected = iface.static_ip_detected
        }
      }
    }
  }
}
output "networks" {
  description = "Configured libvirt networks"
  value       = module.networks.networks
}
