variable "cluster" {
  description = "Talos cluster configuration. vip must be a free address on the bridge subnet, outside the DHCP range."
  type = object({
    name               = string
    vip                = string
    kubernetes_version = optional(string, "v1.32.0")
  })
}

variable "talos_version" {
  description = "Talos version string (e.g. v1.12.0), used for talos_machine_configuration"
  type        = string
}

variable "output_dir" {
  description = "Directory to write kubeconfig and talosconfig. Defaults to <module>/output."
  type        = string
  default     = null
}

variable "nodes" {
  description = <<-EOT
    Cluster nodes. Each node must supply its IP (pre-discovered by kvm-talos-xx or known
    for bare-metal) and the installer_image for its specific schematic/version.

    config_patches is a list of raw Talos machine config YAML strings applied after the
    role-specific patch — use it for per-node hardware configuration (GPU drivers, kernel
    parameters, device permissions, etc.).
  EOT
  type = map(object({
    ip              = string
    role            = optional(string, "controlplane")
    installer_image = string
    config_patches  = optional(list(string), [])
  }))
  validation {
    condition     = length(var.nodes) >= 1
    error_message = "At least one node must be defined."
  }
  validation {
    condition     = length([for k, v in var.nodes : k if v.role == "controlplane"]) >= 1
    error_message = "At least one controlplane node is required."
  }
}
