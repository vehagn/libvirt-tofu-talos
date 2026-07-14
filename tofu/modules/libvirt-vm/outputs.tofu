output "ip_address" {
  description = "First discovered IPv4 address"
  value = try(
    [
      for addr in flatten([
        for iface in data.libvirt_domain_interface_addresses.vm.interfaces :
        iface.addrs
        if iface.hwaddr != "00:00:00:00:00:00"
      ]) :
      split("/", addr.addr)[0]
      if length(regexall(":", addr.addr)) == 0
    ][0],
    null
  )
}

output "ip_addresses" {
  description = "All discovered IPv4 addresses across all interfaces"
  value = try(
    [
      for addr in flatten([
        for iface in data.libvirt_domain_interface_addresses.vm.interfaces :
        iface.addrs
        if iface.hwaddr != "00:00:00:00:00:00"
      ]) :
      split("/", addr.addr)[0]
      if length(regexall(":", addr.addr)) == 0
    ],
    []
  )
}

output "name" {
  description = "VM name"
  value       = libvirt_domain.vm.name
}

output "uuid" {
  description = "libvirt domain UUID (unknown until apply)"
  value       = libvirt_domain.vm.uuid
}
