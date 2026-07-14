variable "libvirt_uri" {
  description = "libvirt connection URI (e.g. qemu+ssh://user@host/system)"
  type        = string
}

variable "vm_bridge_interface" {
  description = "Host bridge interface the Talos nodes join"
  type        = string
  default     = "br0"
}

variable "pool_name" {
  description = "libvirt storage pool name"
  type        = string
  default     = "tofu-talos"
}

variable "pool_path" {
  description = "Filesystem path on the hypervisor backing the storage pool"
  type        = string
  default     = "/var/lib/libvirt/images/tofu-talos"
}

variable "cluster_vip" {
  description = "Cluster VIP to exclude from IP discovery. Set once the cluster is bootstrapped to prevent the VIP from being returned as the node's primary IP on subsequent applies."
  type        = string
  default     = null
}

variable "image" {
  description = "Talos image settings shared across all nodes"
  type = object({
    factory_url = optional(string, "https://factory.talos.dev")
    version     = string
    platform    = optional(string, "nocloud")
    arch        = optional(string, "amd64")
    # Default schematic path (relative to this environment root) used by nodes
    # that do not specify their own. Create additional files under schematics/
    # for nodes with different hardware (GPUs, cameras, etc.).
    default_schematic_path = optional(string, "schematics/default.yaml")
  })
}

variable "nodes" {
  description = <<-EOT
    Talos VM nodes. Map keys become VM and node names.

    schematic_path: path to a Talos image factory schematic YAML, relative to
    this environment directory. Defaults to image.default_schematic_path.
    Use per-node schematics for nodes with different hardware extensions
    (e.g. siderolabs/nvidia-gpu-nonfree-firmware for GPU nodes).

    mac_address: optional; set for DHCP reservations.
  EOT
  type = map(object({
    schematic_path = optional(string)
    mac_address    = optional(string)
    vcpu           = optional(number)
    memory_mb      = optional(number)
    os_disk_gb     = optional(number)
    data_disk_gb   = optional(number)
  }))
  validation {
    condition     = length(var.nodes) >= 1
    error_message = "At least one node must be defined."
  }
}

variable "node_vcpu" {
  description = "Default vCPU count per node"
  type        = number
  default     = 4
}

variable "node_memory_mb" {
  description = "Default RAM in MiB per node"
  type        = number
  default     = 6144
}

variable "node_os_disk_gb" {
  description = "Default OS disk size in GiB"
  type        = number
  default     = 12
}

variable "node_data_disk_gb" {
  description = "Default data disk size in GiB"
  type        = number
  default     = 24
}
