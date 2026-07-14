output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.cluster.cluster_endpoint
}

output "control_plane_nodes" {
  description = "Control plane node IPs"
  value       = module.cluster.control_plane_nodes
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig"
  value       = module.cluster.kubeconfig_path
}

output "talosconfig_path" {
  description = "Path to the generated talosconfig"
  value       = module.cluster.talosconfig_path
}
