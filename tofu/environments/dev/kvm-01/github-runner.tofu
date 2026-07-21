module "github_runner" {
  for_each = var.github_runners
  source   = "../../../modules/github-runner-vm"

  name            = each.key
  pool_name       = libvirt_pool.dev.name
  memory_mb       = each.value.memory_mb
  vcpu_count      = each.value.vcpu_count
  os_disk_size_gb = each.value.os_disk_size_gb
  extra_packages  = each.value.extra_packages

  networks            = { (each.value.network_name) = local.networks[each.value.network_name] }
  ssh_authorized_keys = var.ssh_authorized_keys

  github_url     = each.value.github_url
  runner_token   = var.runner_tokens[each.key]
  runner_version = each.value.runner_version
  runner_labels  = each.value.runner_labels
  runner_group   = each.value.runner_group
}
