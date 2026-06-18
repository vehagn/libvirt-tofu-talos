locals {
  ubuntu_resolute_cloud_image = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}

resource "libvirt_pool" "main" {
  name = "tofu-poc"
  type = "dir"

  target = {
    path = "/var/lib/libvirt/images/tofu-poc"
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }
}

resource "libvirt_network" "main" {
  count = var.vm_bridge_interface == null ? 1 : 0

  name      = "tofu-net"
  autostart = true

  forward = {
    mode = "nat"
  }

  ips = [
    {
      address = "192.168.100.1"
      prefix  = 24
      dhcp = {
        ranges = [
          {
            start = "192.168.100.2"
            end   = "192.168.100.254"
          }
        ]
      }
    }
  ]
}

module "ubuntu" {
  source = "../modules/vm"

  name              = var.vm_name
  hostname          = var.vm_name
  memory_mb         = var.vm_memory_mb
  vcpu_count        = var.vm_vcpu_count
  disk_size_gb      = var.vm_disk_size_gb
  pool_name         = libvirt_pool.main.name
  network_name      = var.vm_bridge_interface == null ? libvirt_network.main[0].name : null
  network_bridge    = var.vm_bridge_interface
  base_image_source = local.ubuntu_resolute_cloud_image

  ssh_authorized_keys = var.ssh_authorized_keys
  user_password       = var.vm_user_password

  static_ip   = var.vm_static_ip
  gateway     = var.vm_gateway
  dns_servers = var.vm_dns_servers
}
