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
  description = "Explicit interface definitions. If empty, interfaces are derived from networks."
  type = list(object({
    label        = string
    network_name = optional(string, null)
    bridge       = optional(string, null)
    mac_address  = optional(string, null)
    wait_for_ip  = optional(bool, true)
  }))
  default = []

  validation {
    condition = alltrue([
      for iface in var.interfaces :
      (iface.network_name != null) != (iface.bridge != null)
      ])
    error_message = "Each interface must have exactly one of network_name or bridge set."
  }

  validation {
    condition     = length(distinct([for iface in var.interfaces : iface.label])) == length(var.interfaces)
    error_message = "Interface labels must be unique."
  }

  validation {
    condition     = length(var.interfaces) > 0 || length(var.networks) > 0
    error_message = "Configure at least one interface via interfaces or networks."
  }
}

variable "networks" {
  description = "module.libvirt-networks.networks output map."
  type = map(object({
    name        = string
    mode        = string
    bridge_name = optional(string, null)
    gateway     = optional(string, null)
    dns_servers = optional(list(string), [])
  }))
  default = {}
}

variable "expected_static_ip" {
  description = "Expected static IPv4 (CIDR allowed, e.g. 10.0.1.163/16). Null disables static IP detection."
  type        = string
  default     = null
}

variable "expected_static_ip_interface_label" {
  description = "Interface label to probe for expected_static_ip. Required when expected_static_ip is set."
  type        = string
  default     = null

  validation {
    condition = (
    var.expected_static_ip == null && var.expected_static_ip_interface_label == null
    ) || (
    var.expected_static_ip != null &&
    var.expected_static_ip_interface_label != null &&
    contains(
      distinct(concat([for iface in var.interfaces : iface.label], keys(var.networks))),
      var.expected_static_ip_interface_label
    )
    )
    error_message = "When expected_static_ip is set, expected_static_ip_interface_label must match one of interfaces[*].label or networks keys."
  }
}

variable "static_ip_detection_timeout_seconds" {
  description = "Timeout for guest-agent static IP detection on the selected interface."
  type        = number
  default     = 300

  validation {
    condition     = var.static_ip_detection_timeout_seconds > 0
    error_message = "static_ip_detection_timeout_seconds must be greater than 0."
  }
}
