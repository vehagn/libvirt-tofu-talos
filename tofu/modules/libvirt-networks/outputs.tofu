output "network_catalog" {
  description = "Effective network catalog (module defaults merged with extra_network_catalog)."
  value       = local.effective_network_catalog
}
output "networks" {
  description = "Configured networks keyed by name (bridge-mode entries are metadata-only and not managed as libvirt networks)."
  value = {
    for network_name, cfg in local.effective_network_catalog : network_name => {
      id          = try(libvirt_network.network[network_name].id, null)
      name        = try(libvirt_network.network[network_name].name, network_name)
      mode        = cfg.mode
      bridge_name = cfg.bridge_name
      prefix      = cfg.prefix
      gateway     = cfg.gateway
      dns_servers = cfg.dns_servers
      subnet      = cfg.address != null ? "${cfg.address}/${cfg.prefix}" : null
      dhcp_range  = cfg.dhcp_start != null ? {
        start = cfg.dhcp_start
        end   = cfg.dhcp_end
      } : null
    }
  }
}
