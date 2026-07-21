locals {
  runner_name       = coalesce(var.runner_name, var.name)
  runner_labels_str = join(",", concat(["self-hosted", "linux", "x64"], var.runner_labels))
  runner_group_arg  = var.runner_group != null ? " --runnergroup ${var.runner_group}" : ""
}

module "vm" {
  source = "../ubuntu-vm"

  name              = var.name
  hostname          = var.hostname
  memory_mb         = var.memory_mb
  vcpu_count        = var.vcpu_count
  pool_name         = var.pool_name
  base_image_source = var.base_image_source
  os_disk_size_gb   = var.os_disk_size_gb
  extra_disks       = var.extra_disks
  networks          = var.networks

  ssh_authorized_keys = var.ssh_authorized_keys
  extra_packages      = var.extra_packages

  write_files = [{
    path = "/opt/runner-setup.sh"
    content = templatefile("${path.module}/templates/runner-setup.sh.tftpl", {
      runner_version    = var.runner_version
      github_url        = var.github_url
      runner_token      = var.runner_token
      runner_name       = local.runner_name
      runner_labels_str = local.runner_labels_str
      runner_group_arg  = local.runner_group_arg
    })
    permissions = "0750"
    owner       = "root:root"
  }]

  # Delete the setup script after registration; the token is a one-hour registration
  # token and has no value after the runner is enrolled.
  extra_runcmd = [
    "/opt/runner-setup.sh",
    "rm -f /opt/runner-setup.sh",
  ]
}
