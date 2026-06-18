variable "name" {
  description = "VM name — used for all resource names"
  type        = string
}

variable "hostname" {
  description = "OS hostname set via cloud-init"
  type        = string
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

variable "disk_size_gb" {
  description = "Root disk size in GiB"
  type        = number
  default     = 20
}

variable "pool_name" {
  description = "libvirt storage pool name"
  type        = string
}

variable "network_name" {
  description = "libvirt virtual network name; mutually exclusive with network_bridge"
  type        = string
  default     = null
}

variable "network_bridge" {
  description = "Host bridge interface for direct bridging onto the host subnet (e.g. br0, virbr0); mutually exclusive with network_name"
  type        = string
  default     = null
}

variable "base_image_source" {
  description = "URL or local path to the cloud image (e.g. Ubuntu noble cloudimg)"
  type        = string
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to authorize for the default user"
  type        = list(string)
}

variable "user_password" {
  description = "Password for the default user. If null, password login is disabled."
  type        = string
  default     = null
  sensitive   = true
}

variable "static_ip" {
  description = "Static IP in CIDR notation (e.g. 192.168.1.100/24). If null, DHCP is used."
  type        = string
  default     = null
}

variable "gateway" {
  description = "Default gateway IP. Required for routing when static_ip is set."
  type        = string
  default     = null
}

variable "dns_servers" {
  description = "DNS server IPs. Used when static_ip is set."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}
