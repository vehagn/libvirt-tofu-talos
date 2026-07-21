variable "name" {
  description = "VM name — used for all resource names"
  type        = string
}

variable "hostname" {
  description = "OS hostname set via cloud-init; defaults to name"
  type        = string
  default     = null
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 4096
}

variable "vcpu_count" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

variable "pool_name" {
  description = "libvirt storage pool name for all volumes"
  type        = string
}

variable "base_image_source" {
  description = "Ubuntu cloud image URL or local path"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "os_disk_size_gb" {
  description = "Root disk size in GiB; runners accumulate build artifacts"
  type        = number
  default     = 50
}

variable "extra_disks" {
  description = "Additional data disks; pool defaults to pool_name"
  type = list(object({
    name    = string
    size_gb = number
    pool    = optional(string, null)
  }))
  default = []
}

variable "networks" {
  description = "Network attachments; passed through to ubuntu-vm. See ubuntu-vm.networks."
  type = map(object({
    mode        = string
    name        = optional(string, null)
    bridge_name = optional(string, null)
    mac_address = optional(string, null)
    wait_for_ip = optional(bool, true)
    static_ip   = optional(string, null)
    gateway     = optional(string, null)
    dns_servers = optional(list(string), [])
  }))
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to authorize for the ubuntu user"
  type        = list(string)
  default     = []
}

variable "extra_packages" {
  description = "Additional apt packages to install alongside runner dependencies"
  type        = list(string)
  default     = []
}

# GitHub Actions runner variables

variable "github_url" {
  description = "GitHub URL to register the runner with — repo (https://github.com/owner/repo) or org (https://github.com/owner)"
  type        = string
}

variable "runner_token" {
  description = "Registration token from GitHub (Settings → Actions → Runners → New self-hosted runner); valid for 1 hour"
  type        = string
  sensitive   = true
}

variable "runner_name" {
  description = "Runner name shown in GitHub; defaults to VM name"
  type        = string
  default     = null
}

variable "runner_labels" {
  description = "Extra labels added to the runner alongside the defaults (self-hosted, linux, x64)"
  type        = list(string)
  default     = []
}

variable "runner_group" {
  description = "Runner group name; null uses the default group (enterprise/org runners only)"
  type        = string
  default     = null
}

variable "runner_version" {
  description = "GitHub Actions runner version to install (e.g. \"2.323.0\"); pin this for reproducible builds"
  type        = string
}
