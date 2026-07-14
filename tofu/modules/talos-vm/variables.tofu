variable "name" {
  description = "VM name — used for all resource names"
  type        = string
}

variable "pool_name" {
  description = "libvirt storage pool to place volumes in"
  type        = string
}

variable "base_image_path" {
  description = "File path on the hypervisor of the Talos base qcow2 image (backing store)"
  type        = string
}

variable "vcpu_count" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM in MiB"
  type        = number
  default     = 6144
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB (overlay on the base image)"
  type        = number
  default     = 12
}

variable "data_disk_size_gb" {
  description = "Secondary data disk size in GiB (for Kubernetes workloads)"
  type        = number
  default     = 24
}

variable "bridge" {
  description = "Host bridge interface to attach the VM's primary NIC to"
  type        = string
}

variable "mac_address" {
  description = "Optional MAC address for the primary NIC (useful for DHCP reservations)"
  type        = string
  default     = null
}

variable "ssh_target" {
  description = "SSH target (user@host) used to query virsh for the DHCP-assigned IP"
  type        = string
}

variable "cluster_vip" {
  description = "Cluster VIP to exclude from IP discovery. Null to skip exclusion (safe for fresh nodes before the cluster is bootstrapped)."
  type        = string
  default     = null
}
