resource "libvirt_pool" "dev" {
  name = "dev"
  type = "dir"

  target = {
    path = var.pool_path
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }
}
