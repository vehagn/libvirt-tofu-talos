resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = local.control_plane_ips
  endpoints            = local.control_plane_ips
}

data "talos_machine_configuration" "this" {
  for_each = var.nodes

  cluster_name       = var.cluster.name
  cluster_endpoint   = local.cluster_endpoint
  talos_version      = var.talos_version
  kubernetes_version = var.cluster.kubernetes_version
  machine_type       = each.value.role
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  # Hostname is a separate HostnameConfig document to avoid conflicts when
  # talos_machine re-applies (setting machine.network.hostname in v1alpha1 trips
  # "static hostname is already set in v1alpha1 config").
  config_patches = concat(
    [
      templatefile("${path.module}/machine-config/hostname.yaml.tftpl", {
        hostname = each.key
      }),
      each.value.role == "controlplane" ? templatefile("${path.module}/machine-config/controlplane.yaml.tftpl", {
        hostname        = each.key
        cluster_name    = var.cluster.name
        vip             = var.cluster.vip
        installer_image = each.value.installer_image
        }) : templatefile("${path.module}/machine-config/worker.yaml.tftpl", {
        hostname        = each.key
        installer_image = each.value.installer_image
      })
    ],
    each.value.config_patches
  )
}

locals {
  # Breaking a dependency cycle: talos_machine needs the kubeconfig for
  # drain_on_upgrade; kubeconfig comes from talos_cluster_kubeconfig which
  # depends on talos_cluster which depends on talos_machine. We side-step this
  # by reading the kubeconfig file written on the previous apply — on the very
  # first apply the file does not exist yet, so drain is skipped.
  kubeconfig_file      = "${local.effective_output_dir}/kubeconfig"
  bootstrap_kubeconfig = try(file(local.kubeconfig_file), null)
  drain_enabled        = local.bootstrap_kubeconfig != null
}

# One talos_machine per node — keeps OS version and machine configuration in
# sync. Use `tofu apply -parallelism=1` to roll OS upgrades sequentially so
# etcd quorum is preserved across control-plane nodes.
resource "talos_machine" "this" {
  for_each = var.nodes

  node                  = local.node_ips[each.key]
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this[each.key].machine_configuration
  image                 = each.value.installer_image

  drain_on_upgrade = local.drain_enabled
  kubeconfig_wo    = local.bootstrap_kubeconfig

  timeouts = {
    create = "15m"
    update = "30m"
  }
}

resource "talos_cluster" "this" {
  depends_on = [talos_machine.this]

  # node + endpoint must be a real node IP, NOT the VIP: the VIP only comes up
  # after etcd is healthy, but that is exactly what this resource bootstraps.
  node                 = local.first_control_plane
  endpoint             = local.first_control_plane
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = local.control_plane_ips
  kubernetes_version   = var.cluster.kubernetes_version

  timeouts = {
    create = "15m"
    update = "30m"
  }
}

data "talos_cluster_health" "this" {
  depends_on = [talos_cluster.this]

  client_configuration   = data.talos_client_configuration.this.client_configuration
  control_plane_nodes    = local.control_plane_ips
  endpoints              = data.talos_client_configuration.this.endpoints
  skip_kubernetes_checks = false

  timeouts = {
    read = "10m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_cluster.this, data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.first_control_plane
  endpoint             = local.first_control_plane

  timeouts = {
    create = "2m"
  }
}
