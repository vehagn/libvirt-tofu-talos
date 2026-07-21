resource "libvirt_network" "management" {
  name      = "management"
  autostart = true

  forward = {
    mode = "nat"
  }

  ips = [
    {
      address = "192.168.100.1"
      prefix  = 24
    }
  ]
}

resource "libvirt_network" "isolated" {
  name      = "isolated"
  autostart = true

  forward = {
    mode = "none"
  }

  ips = [
    {
      address = "10.100.0.1"
      prefix  = 24
    }
  ]
}

# Wraps an existing host bridge; the bridge interface must already exist on the hypervisor.
resource "libvirt_network" "bridge" {
  name      = "bridge"
  autostart = true

  forward = {
    mode = "bridge"
  }

  bridge = {
    name = var.bridge_interface
  }
}

# Networks in the shape ubuntu-vm/libvirt-vm expects — a map keyed by label.
# Callers reference an entry by name (e.g. local.networks["management"]).
locals {
  networks = {
    management = {
      mode = "nat"
      name = libvirt_network.management.name
    }
    isolated = {
      mode = "none"
      name = libvirt_network.isolated.name
    }
    bridge = {
      mode        = "bridge"
      bridge_name = var.bridge_interface
    }
  }
}
