resource "libvirt_network" "network" {
  for_each  = { for name, cfg in var.networks : name => cfg if cfg.mode != "bridge" }
  name      = each.key
  autostart = true

  forward = { mode = each.value.mode }
  bridge  = each.value.bridge_name != null ? { name = each.value.bridge_name } : null

  ips = each.value.address != null ? [
    {
      address = each.value.address
      prefix  = each.value.prefix
      dhcp = each.value.dhcp_start != null && each.value.dhcp_end != null ? {
        ranges = [{ start = each.value.dhcp_start, end = each.value.dhcp_end }]
      } : null
    }
  ] : null
}
