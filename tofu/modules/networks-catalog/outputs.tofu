locals {
  networks = {
    bridge = {
      mode        = "bridge"
      bridge_name = var.bridge_interface
      prefix      = 16
      gateway     = "10.0.1.1"
      dns_servers = ["10.0.1.10", "10.0.1.11"]
    }
    management = {
      mode        = "nat"
      address     = "172.20.0.1"
      prefix      = 24
      gateway     = "172.20.0.1"
      dns_servers = ["172.20.0.1"]
      dhcp_start  = "172.20.0.2"
      dhcp_end    = "172.20.0.254"
    }
    isolated = {
      mode        = "none"
      address     = "192.168.20.1"
      prefix      = 24
      gateway     = "192.168.20.1"
      dns_servers = ["192.168.20.1"]
      dhcp_start  = "192.168.20.2"
      dhcp_end    = "192.168.20.254"
    }
  }
}

output "networks" {
  description = <<-EOT
    Standard libvirt network catalog. Pass this to the libvirt-networks module directly, or merge
    with per-environment additions/overrides — the map is a plain object, so merge() works.
  EOT
  value = local.networks
}
