locals {
  node_ips          = { for k, v in var.nodes : k => v.ip }
  control_plane_ips = [for k, v in var.nodes : v.ip if v.role == "controlplane"]
  # Bootstrap target must be a direct node IP — the VIP only comes up after etcd is healthy.
  first_control_plane = local.control_plane_ips[0]
}
