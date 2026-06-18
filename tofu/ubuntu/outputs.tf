output "vm_ip" {
  description = "IP address of the Ubuntu VM"
  value       = module.ubuntu.ip_address
}

output "vm_name" {
  description = "Name of the Ubuntu VM (as known to libvirt)"
  value       = module.ubuntu.name
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = module.ubuntu.ip_address != null ? "ssh ubuntu@${module.ubuntu.ip_address}" : null
}
