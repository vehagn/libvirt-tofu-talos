output "ip_address" {
  description = "VM IP address (static if configured, otherwise discovered after boot)"
  value = var.static_ip != null ? split("/", var.static_ip)[0] : try(
    [
      for addr in flatten([
        for iface in data.libvirt_domain_interface_addresses.vm[0].interfaces :
        iface.addrs
        if iface.hwaddr != "00:00:00:00:00:00"
      ]) :
      split("/", addr.addr)[0]
      if length(regexall(":", addr.addr)) == 0
    ][0],
    null
  )
}

output "name" {
  description = "VM name"
  value       = libvirt_domain.vm.name
}
