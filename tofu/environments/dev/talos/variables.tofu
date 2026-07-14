variable "cluster" {
  description = "Talos cluster configuration"
  type = object({
    name               = string
    vip                = string
    kubernetes_version = optional(string, "v1.32.0")
  })
}

variable "talos_version" {
  description = "Talos version string (e.g. v1.12.0). Should match the version deployed in kvm-talos-xx environments."
  type        = string
}

variable "kvm_talos_state_paths" {
  description = <<-EOT
    Map of kvm-talos-xx statefile paths (relative to this environment) to read VM node
    IPs and installer images from. Key is a label used internally.
    Apply kvm-talos-xx environments before running `tofu apply` here.
  EOT
  type        = map(string)
  default     = { kvm-talos-01 = "../kvm-talos-01/terraform.tfstate" }
}

variable "vm_node_roles" {
  description = <<-EOT
    Role overrides for VM nodes read from kvm-talos-xx states. Defaults to controlplane for
    all. Set role = "worker" for dedicated worker nodes.
  EOT
  type        = map(string)
  default     = {}
}

variable "vm_node_config_patches" {
  description = "Per-node extra Talos config patches (raw YAML strings) for VM nodes, keyed by node name."
  type        = map(list(string))
  default     = {}
}

variable "bare_metal_nodes" {
  description = <<-EOT
    Bare-metal or externally-managed nodes not coming from any kvm-talos-xx state.
    Provide the IP and the exact installer_image for the node's schematic and version.

    config_patches: per-node Talos config patches for hardware-specific config
    (GPU drivers, PCIe passthrough, kernel parameters, etc.).
  EOT
  type = map(object({
    ip              = string
    role            = optional(string, "controlplane")
    installer_image = string
    config_patches  = optional(list(string), [])
  }))
  default = {}
}

variable "output_dir" {
  description = "Directory to write kubeconfig and talosconfig. Defaults to ./output."
  type        = string
  default     = null
}
