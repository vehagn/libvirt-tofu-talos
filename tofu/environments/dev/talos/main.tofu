# Read VM node IPs and installer images from each kvm-talos-xx environment.
# Keys must be known at plan time (they are, since kvm_talos_state_paths is a tfvars input).
# Run `just kvm-talos-01 apply` (and any other kvm-talos-xx) before running `just talos apply`.
data "terraform_remote_state" "kvm" {
  for_each = var.kvm_talos_state_paths

  backend = "local"
  config  = { path = "${path.root}/${each.value}" }
}

locals {
  # Merge nodes from all kvm-talos-xx states into a flat map.
  # Node names must be unique across all hypervisors.
  vm_nodes_raw = merge([
    for _, state in data.terraform_remote_state.kvm : state.outputs.nodes
  ]...)

  # Apply role overrides and per-node config patches from tfvars
  vm_nodes = {
    for name, node in local.vm_nodes_raw : name => {
      ip              = node.ip
      role            = lookup(var.vm_node_roles, name, "controlplane")
      installer_image = node.installer_image
      config_patches  = lookup(var.vm_node_config_patches, name, [])
    }
  }

  # Merge VM nodes with bare-metal nodes — bare_metal_nodes takes precedence on name collision
  all_nodes = merge(local.vm_nodes, var.bare_metal_nodes)
}

module "cluster" {
  source = "../../../modules/talos-cluster"

  cluster       = var.cluster
  talos_version = var.talos_version
  nodes         = local.all_nodes
  output_dir    = coalesce(var.output_dir, "${path.root}/output")
}
