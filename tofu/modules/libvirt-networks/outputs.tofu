output "networks" {
  description = <<-EOT
    Configured networks in the shape libvirt-vm and ubuntu-vm consume. The `id` field is null for
    bridge-mode entries (no libvirt_network resource); for other modes it references the created
    resource so consumers implicitly depend on its creation.
  EOT
  value = {
    for name, cfg in var.networks : name => {
      mode        = cfg.mode
      name        = name
      bridge_name = cfg.bridge_name
      gateway     = coalesce(cfg.gateway, cfg.address)
      dns_servers = cfg.dns_servers
      id          = try(libvirt_network.network[name].id, null)
    }
  }
}
