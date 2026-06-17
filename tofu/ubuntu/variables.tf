variable "libvirt_uri" {
  description = "libvirt connection URI (e.g. qemu+ssh://user@host/system or qemu:///system)"
  type        = string
}

variable "ssh_authorized_keys" {
  description = "SSH public keys to inject into the VM"
  type        = list(string)
}

variable "vm_name" {
  description = "VM name"
  type        = string
  default     = "ubuntu"
}

variable "vm_memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 2048
}

variable "vm_vcpu_count" {
  description = "Virtual CPUs"
  type        = number
  default     = 2
}

variable "vm_disk_size_gb" {
  description = "Root disk size in GiB"
  type        = number
  default     = 20
}
