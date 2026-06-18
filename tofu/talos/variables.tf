variable "libvirt_uri" {
  description = "libvirt connection URI (e.g. qemu+ssh://user@host/system)"
  type        = string
}

variable "vm_bridge_interface" {
  description = "Host bridge interface the nodes join (must exist on the hypervisor)"
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

variable "cluster" {
  description = "Talos cluster configuration. vip is the shared cluster endpoint and must be a free address on the bridge subnet, outside the DHCP range."
  type = object({
    name               = string
    vip                = string
    kubernetes_version = optional(string, "v1.32.0")
  })
}

variable "image" {
  description = "Talos image configuration"
  type = object({
    factory_url    = optional(string, "https://factory.talos.dev")
    version        = string
    schematic_path = optional(string, "image/schematic.yaml")
    platform       = optional(string, "nocloud")
    arch           = optional(string, "amd64")
  })
}

variable "nodes" {
  description = "Talos nodes. All nodes act as both control plane and worker. Nodes use DHCP for their primary address; mac_address is optional and only useful for DHCP reservations."
  type = map(object({
    mac_address  = optional(string)
    vcpu         = optional(number)
    memory_mb    = optional(number)
    os_disk_gb   = optional(number)
    data_disk_gb = optional(number)
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
  description = "Default data disk size in GiB (attached as a second disk for Kubernetes workloads)"
  type        = number
  default     = 24
}
