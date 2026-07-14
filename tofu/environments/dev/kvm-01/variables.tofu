variable "libvirt_uri" {
  description = "libvirt connection URI (e.g. qemu+ssh://user@host/system or qemu:///system)"
  type        = string
}

variable "pool_path" {
  description = "Host filesystem path for the libvirt storage pool"
  type        = string
  default     = "/var/lib/libvirt/images/dev"
}

variable "bridge_interface" {
  description = "Host bridge interface name for the bridge network (e.g. br0)"
  type        = string
  default     = "br0"
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to inject into VMs"
  type        = list(string)
  default     = []
}

variable "ubuntu_vms" {
  description = "Ubuntu VMs to create; keys become VM names"
  type = map(object({
    memory_mb       = optional(number, 2048)
    vcpu_count      = optional(number, 2)
    os_disk_size_gb = optional(number, 20)
    extra_packages  = optional(list(string), [])
    network_name    = optional(string, "management")
  }))
  default = {}
}

variable "github_runners" {
  description = "GitHub Actions self-hosted runner VMs to create; keys become VM names"
  type = map(object({
    memory_mb       = optional(number, 4096)
    vcpu_count      = optional(number, 4)
    os_disk_size_gb = optional(number, 50)
    extra_packages  = optional(list(string), [])
    network_name    = optional(string, "management")
    github_url      = string
    runner_version  = string
    runner_labels   = optional(list(string), [])
    runner_group    = optional(string, null)
  }))
  default = {}
}

variable "runner_tokens" {
  description = "Registration tokens keyed by runner name (keys must match github_runners); each token is valid for 1 hour after generation"
  type        = map(string)
  sensitive   = true
  default     = {}
}
