locals {
  cluster_endpoint     = "https://${var.cluster.vip}:6443"
  effective_output_dir = coalesce(var.output_dir, "${path.module}/output")
}
