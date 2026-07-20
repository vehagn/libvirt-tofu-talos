variable "extra_network_catalog" {
  description = "Additional or overriding libvirt networks keyed by name."
  type = map(object({
    mode        = string
    bridge_name = optional(string, null)
    address     = optional(string, null)
    prefix      = optional(number, null)
    gateway     = optional(string, null)
    dns_servers = optional(list(string), null)
    dhcp_start  = optional(string, null)
    dhcp_end    = optional(string, null)
  }))
  default = {}
  validation {
    condition = alltrue([
      for _, cfg in var.extra_network_catalog :
      contains(["bridge", "nat", "none"], cfg.mode)
    ])
    error_message = "mode must be one of: bridge, nat, none."
  }
  validation {
    condition = alltrue([
      for _, cfg in var.extra_network_catalog :
      cfg.mode != "bridge" || cfg.bridge_name != null
      ])
    error_message = "bridge_name must be set when mode is bridge."
  }
  validation {
    condition = alltrue([
      for _, cfg in var.extra_network_catalog :
      cfg.mode != "none" || cfg.bridge_name == null
      ])
    error_message = "bridge_name must be null when mode is none."
  }
  validation {
    condition = alltrue([
      for _, cfg in var.extra_network_catalog :
      (cfg.address == null) == (cfg.prefix == null)
      ])
    error_message = "address and prefix must both be set or both be null."
  }
  validation {
    condition = alltrue([
      for _, cfg in var.extra_network_catalog :
      (cfg.dhcp_start == null) == (cfg.dhcp_end == null)
      ])
    error_message = "dhcp_start and dhcp_end must both be set or both be null."
  }
  validation {
    condition = alltrue([
      for _, cfg in var.extra_network_catalog :
      (cfg.dhcp_start == null && cfg.dhcp_end == null) || (cfg.address != null && cfg.prefix != null)
      ])
    error_message = "dhcp_start/dhcp_end require address and prefix."
  }
}
