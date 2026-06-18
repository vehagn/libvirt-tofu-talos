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
  talos_version      = var.image.version
  kubernetes_version = var.cluster.kubernetes_version
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets

  # Hostname lives in a separate HostnameConfig document, not in
  # machine.network.hostname. Setting hostname in v1alpha1 trips Talos's
  # "static hostname is already set in v1alpha1 config" validation when the
  # talos_machine resource re-applies — same conflict that the Proxmox setup
  # avoids by structuring it this way.
  config_patches = [
    templatefile("${path.module}/machine-config/hostname.yaml.tftpl", {
      hostname = each.key
    }),
    templatefile("${path.module}/machine-config/controlplane.yaml.tftpl", {
      hostname        = each.key
      cluster_name    = var.cluster.name
      vip             = var.cluster.vip
      installer_image = local.installer_image
    })
  ]
}

locals {
  # Breaking a dependency cycle: talos_machine needs the kubeconfig for
  # drain_on_upgrade, the kubeconfig comes from talos_cluster_kubeconfig which
  # needs talos_cluster which depends on talos_machine. We side-step it by
  # reading the kubeconfig file produced on the previous apply — on the very
  # first apply the file does not exist yet, so drain is skipped (there's
  # nothing to drain anyway). From the second apply onward, OS upgrades flow
  # through drain_on_upgrade.
  kubeconfig_file      = "${path.module}/output/kubeconfig"
  bootstrap_kubeconfig = try(file(local.kubeconfig_file), null)
  drain_enabled        = local.bootstrap_kubeconfig != null
}

# One talos_machine per node — keeps OS version and machine configuration in
# sync. Use `tofu apply -parallelism=1` to roll OS upgrades sequentially so
# etcd quorum is preserved across the three control-plane nodes.
resource "talos_machine" "this" {
  for_each = var.nodes

  node                  = local.node_ips[each.key]
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.this[each.key].machine_configuration
  image                 = local.installer_image

  drain_on_upgrade = local.drain_enabled
  kubeconfig_wo    = local.bootstrap_kubeconfig

  timeouts = {
    create = "15m"
    update = "30m"
  }
}

resource "talos_cluster" "this" {
  depends_on = [talos_machine.this]

  # node + endpoint must both be a real node IP, NOT the VIP: the VIP only comes
  # up after etcd is healthy on the elected node, but that's exactly what this
  # resource bootstraps. https://www.talos.dev/latest/talos-guides/network/vip/#caveats
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
