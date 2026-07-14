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

variable "os_disk" {
  description = "OS disk volume reference (vda)"
  type = object({
    pool   = string
    volume = string
  })
}

variable "cloudinit_disk" {
  description = "Cloud-init ISO volume reference; null attaches no cloud-init cdrom"
  type = object({
    pool   = string
    volume = string
  })
  default = null
}

variable "cpu_mode" {
  description = "CPU mode (e.g. host-passthrough, host-model). Null uses the libvirt default."
  type        = string
  default     = null
}

variable "extra_disks" {
  description = "Additional data disk volume references, attached as vdb, vdc, ..."
  type = list(object({
    pool   = string
    volume = string
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
