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

variable "networks" {
  description = <<-EOT
    Network attachments keyed by label — one NIC per entry. Bridge-mode entries attach to a host
    bridge (bridge_name); other modes attach to a libvirt-managed network (name). The static_ip,
    gateway, and dns_servers fields are guest-OS configuration hints — libvirt-vm uses static_ip
    for its wait strategy and output fallback; other fields are passthrough for callers like
    ubuntu-vm that generate cloud-init.

    Pass module.libvirt-networks.networks directly, or a hand-built map. Extra fields in the
    input value (id, prefix, subnet, ...) are silently dropped by the type constraint.
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
    error_message = "At least one network attachment is required."
  }

  validation {
    condition     = alltrue([for _, cfg in var.networks : contains(["bridge", "nat", "none"], cfg.mode)])
    error_message = "Each network must have mode = bridge, nat, or none."
  }

  validation {
    condition     = alltrue([for _, cfg in var.networks : cfg.mode != "bridge" || cfg.bridge_name != null])
    error_message = "Bridge-mode networks require bridge_name."
  }

  validation {
    condition     = alltrue([for _, cfg in var.networks : cfg.mode == "bridge" || cfg.name != null])
    error_message = "nat/none networks require name."
  }

  validation {
    condition     = alltrue([for _, cfg in var.networks : cfg.static_ip == null || can(cidrnetmask(cfg.static_ip))])
    error_message = "static_ip must be an IPv4 CIDR (e.g. 10.0.1.163/16)."
  }
}

variable "static_ip_detection_timeout_seconds" {
  description = "Timeout for guest-agent static IP detection when no interface can wait via DHCP lease."
  type        = number
  default     = 300

  validation {
    condition     = var.static_ip_detection_timeout_seconds > 0
    error_message = "static_ip_detection_timeout_seconds must be greater than 0."
  }
}
