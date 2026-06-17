locals {
  ubuntu_noble_cloud_image = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

resource "libvirt_pool" "main" {
  name = "tofu-poc"
  type = "dir"
  path = "/var/lib/libvirt/images/tofu-poc"
}

resource "libvirt_network" "main" {
  name      = "tofu-net"
  mode      = "nat"
  addresses = ["192.168.100.0/24"]
  autostart = true

  dns {
    enabled = true
  }
}

module "ubuntu" {
  source = "../modules/vm"

  name              = var.vm_name
  hostname          = var.vm_name
  memory_mb         = var.vm_memory_mb
  vcpu_count        = var.vm_vcpu_count
  disk_size_gb      = var.vm_disk_size_gb
  pool_name         = libvirt_pool.main.name
  network_name      = libvirt_network.main.name
  base_image_source = local.ubuntu_noble_cloud_image

  ssh_authorized_keys = var.ssh_authorized_keys
}
