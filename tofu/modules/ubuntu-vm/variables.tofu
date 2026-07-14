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
  default     = 2048
}

variable "vcpu_count" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 2
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
  description = "Root disk size in GiB"
  type        = number
  default     = 20
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

variable "interfaces" {
  description = "Network interfaces; each must specify exactly one of network_name or bridge"
  type = list(object({
    network_name = optional(string, null)
    bridge       = optional(string, null)
    mac_address  = optional(string, null)
    wait_for_ip  = optional(bool, true)
  }))
  validation {
    condition = alltrue([
      for iface in var.interfaces :
      (iface.network_name != null) != (iface.bridge != null)
    ])
    error_message = "Each interface must have exactly one of network_name or bridge set."
  }
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to authorize for the ubuntu user"
  type        = list(string)
  default     = []
}

variable "user_password" {
  description = "Password for the ubuntu user; null disables password login"
  type        = string
  default     = null
  sensitive   = true
}

variable "static_ip" {
  description = "Static IP in CIDR notation (e.g. 192.168.1.100/24); null uses DHCP"
  type        = string
  default     = null
}

variable "gateway" {
  description = "Default gateway IP; required when static_ip is set"
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS server IPs; used when static_ip is set"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "extra_packages" {
  description = "Additional apt packages to install (e.g. [\"nginx\"] for a web server VM)"
  type        = list(string)
  default     = []
}

variable "write_files" {
  description = "Files to create via cloud-init write_files, available before runcmd executes"
  type = list(object({
    path        = string
    content     = string
    permissions = optional(string, "0644")
    owner       = optional(string, "root:root")
  }))
  default = []
}

variable "extra_runcmd" {
  description = "Shell commands appended to cloud-init runcmd, run after package install"
  type        = list(string)
  default     = []
}
