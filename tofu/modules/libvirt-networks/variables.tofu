variable "networks" {
  description = <<-EOT
    Libvirt networks keyed by name. The map key becomes the libvirt_network resource name.
    Bridge-mode entries are metadata-only (the host bridge is expected to already exist and
    is not managed here — libvirt_network resources are created only for nat/none modes).
  EOT
  type = map(object({
    mode        = string
    bridge_name = optional(string, null)
    address     = optional(string, null)
    prefix      = optional(number, null)
    gateway     = optional(string, null)
    dns_servers = optional(list(string), [])
    dhcp_start  = optional(string, null)
    dhcp_end    = optional(string, null)
  }))

  validation {
    condition = alltrue([
      for _, cfg in var.networks : contains(["bridge", "nat", "none"], cfg.mode)
    ])
    error_message = "Each network must have mode = bridge, nat, or none."
  }

  validation {
    condition     = alltrue([for _, cfg in var.networks : cfg.mode != "bridge" || cfg.bridge_name != null])
    error_message = "Bridge-mode networks require bridge_name."
  }
}
