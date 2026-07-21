variable "libvirt_uri" {
  description = "libvirt connection URI (e.g. qemu+ssh://user@host/system)"
  type        = string
}

variable "pool_path" {
  description = "Host filesystem path for the libvirt storage pool"
  type        = string
  default     = "/var/lib/libvirt/images/pool-0"
}

variable "bridge_interface" {
  description = "Host bridge device for the default bridge network"
  type        = string
  default     = "br0"
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to inject into VMs"
  type        = list(string)
  default     = []
}

variable "ubuntu_vms" {
  description = <<-EOT
    Ubuntu VMs to create; keys become VM names. Each entry's `networks` map selects catalog
    entries by key and can override any per-network field (static_ip, mac_address, ...). Fields
    left unset fall through to the libvirt-networks catalog defaults.
  EOT
  type = map(object({
    memory_mb       = optional(number, 2048)
    vcpu_count      = optional(number, 2)
    os_disk_size_gb = optional(number, 20)
    extra_packages  = optional(list(string), [])
    extra_disks = optional(list(object({
      name    = string
      size_gb = number
      pool    = optional(string, null)
    })), [])
    networks = map(object({
      static_ip   = optional(string, null)
      gateway     = optional(string, null)
      dns_servers = optional(list(string), null)
      mac_address = optional(string, null)
      wait_for_ip = optional(bool, null)
    }))
  }))
  default = {}
}
