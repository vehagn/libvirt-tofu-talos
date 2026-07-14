output "vms" {
  description = "IP address and SSH command for each Ubuntu VM"
  value = {
    for name, vm in module.ubuntu : name => {
      ip  = vm.ip_address
      ssh = vm.ip_address != null ? "ssh ubuntu@${vm.ip_address}" : null
    }
  }
}

output "runners" {
  description = "IP address and SSH command for each GitHub Actions runner VM"
  value = {
    for name, runner in module.github_runner : name => {
      ip  = runner.ip_address
      ssh = runner.ip_address != null ? "ssh ubuntu@${runner.ip_address}" : null
    }
  }
}
