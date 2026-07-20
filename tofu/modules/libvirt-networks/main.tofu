locals {
  default_network_catalog = {
    bridge = {
      mode        = "bridge"
      bridge_name = "br0"
      address     = null
      prefix      = 16
      gateway     = "10.0.1.1"
      dns_servers = ["10.0.1.10", "10.0.1.11"]
      dhcp_start  = null
      dhcp_end    = null
    }
    management = {
      mode        = "nat"
      bridge_name = null
      address     = "172.20.0.1"
      prefix      = 24
      gateway     = "172.20.0.1"
      dns_servers = ["172.20.0.1"]
      dhcp_start  = "172.20.0.2"
      dhcp_end    = "172.20.0.254"
    }
    isolated = {
      mode        = "none"
      bridge_name = null
      address     = "192.168.20.1"
      prefix      = 24
      gateway     = "192.168.20.1"
      dns_servers = ["192.168.20.1"]
      dhcp_start  = "192.168.20.2"
      dhcp_end    = "192.168.20.254"
    }
  }
  network_catalog = merge(
    local.default_network_catalog,
    {
      for network_name, cfg in var.extra_network_catalog :
      network_name => (
      contains(keys(local.default_network_catalog), network_name)
      ? merge(
      local.default_network_catalog[network_name],
      { for k, v in cfg : k => v if v != null }
    )
      : cfg
    )
    }
  )
  effective_network_catalog = {
    for network_name, cfg in local.network_catalog : network_name => merge(cfg, {
      bridge_name = cfg.mode == "none" ? null : cfg.bridge_name
      gateway     = coalesce(cfg.gateway, cfg.address)
      dns_servers = cfg.dns_servers != null ? cfg.dns_servers : []
    })
  }
  managed_network_catalog = {
    for network_name, cfg in local.effective_network_catalog :
    network_name => cfg
    if cfg.mode != "bridge"
  }
}
resource "libvirt_network" "network" {
  for_each  = local.managed_network_catalog
  name      = each.key
  autostart = true
  forward = {
    mode = each.value.mode
  }
  bridge = each.value.bridge_name != null ? {
    name = each.value.bridge_name
  } : null
  ips = each.value.address != null ? [
    {
      address = each.value.address
      prefix  = each.value.prefix
      dhcp = each.value.dhcp_start != null && each.value.dhcp_end != null ? {
        ranges = [{
          start = each.value.dhcp_start
          end   = each.value.dhcp_end
        }]
      } : null
    }
  ] : null
}