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
  description = "libvirt network name"
  type        = string
}

variable "base_image_source" {
  description = "URL or local path to the cloud image (e.g. Ubuntu noble cloudimg)"
  type        = string
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to authorize for the default user"
  type        = list(string)
}
