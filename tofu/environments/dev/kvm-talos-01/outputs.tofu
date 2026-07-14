# Consumed by environments/dev/talos via terraform_remote_state
output "nodes" {
  description = "Per-node IP and installer image, keyed by node name"
  value = {
    for name, _ in var.nodes : name => {
      ip              = module.node[name].ip_address
      installer_image = local.node_installer_image[name]
    }
  }
}

output "talos_version" {
  description = "Talos version deployed to these nodes"
  value       = var.image.version
}
