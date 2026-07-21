variable "name" {
  description = "VM name — used for all resource names"
  type        = string
}

variable "hostname" {
  description = "Hostname label shown in libvirt; defaults to name"
  type        = string
  default     = null
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 1024
}

variable "vcpu_count" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 1
}

variable "pool_name" {
  description = "Libvirt pool name for all volumes"
  type        = string
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB"
  type        = number
  default     = 20

  validation {
    condition     = var.os_disk_size_gb > 0
    error_message = "os_disk_size_gb must be positive."
  }
}

variable "base_image_source" {
  description = "URL for the base Ubuntu cloud image (qcow2)"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to inject into the ubuntu user"
  type        = list(string)
  default     = []
}

variable "extra_packages" {
  description = "Additional APT packages to install at first boot"
  type        = list(string)
  default     = []
}

variable "write_files" {
  description = "Files to write via cloud-init write_files directive"
  type = list(object({
    path        = string
    content     = string
    owner       = optional(string, "root:root")
    permissions = optional(string, "0644")
  }))
  default = []
}

variable "extra_runcmd" {
  description = "Additional runcmd entries executed at first boot"
  type        = list(string)
  default     = []
}

variable "extra_disks" {
  description = "Additional data disks to attach as vdb, vdc, ...; name is used for volume naming only"
  type = list(object({
    name    = string
    size_gb = number
    pool    = optional(string, null)
  }))
  default = []
}

variable "networks" {
  description = <<-EOT
    Network attachments keyed by label — one NIC per entry. Pass module.libvirt-networks.networks
    directly, or a hand-built map. Per-entry static_ip (CIDR), gateway, and dns_servers configure
    cloud-init; the first bridge-mode entry (or the first entry alphabetically if no bridge) also
    receives DHCP-provided routes and DNS when it has no static_ip.
  EOT
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

  validation {
    condition     = length(var.networks) > 0
    error_message = "At least one network must be provided."
  }
}

variable "static_ip_detection_timeout_seconds" {
  description = "Seconds to wait for the guest agent to report the static IP (only when no lease-wait applies)"
  type        = number
  default     = 300

  validation {
    condition     = var.static_ip_detection_timeout_seconds > 0
    error_message = "static_ip_detection_timeout_seconds must be greater than 0."
  }
}
