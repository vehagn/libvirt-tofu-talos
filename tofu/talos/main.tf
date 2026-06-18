locals {
  schematic    = file("${path.module}/${var.image.schematic_path}")
  schematic_id = jsondecode(data.http.schematic_id.response_body).id

  image_basename = "talos-${local.schematic_id}-${var.image.version}-${var.image.platform}-${var.image.arch}"
  image_dir      = abspath("${path.module}/.images")
  image_local    = "${local.image_dir}/${local.image_basename}.qcow2"
  image_url      = "${var.image.factory_url}/image/${local.schematic_id}/${var.image.version}/${var.image.platform}-${var.image.arch}.raw.gz"

  installer_image = "factory.talos.dev/installer/${local.schematic_id}:${var.image.version}"

  # Nodes use DHCP; their IPs are discovered after first boot via the QEMU guest
  # agent (see nodes.tf). The cluster endpoint is the static VIP so machine
  # config can reference it before any node has booted.
  cluster_endpoint_host = var.cluster.vip
  cluster_endpoint      = "https://${var.cluster.vip}:6443"

  # Extracts the SSH target (user@host) from qemu+ssh://user@host/system so the
  # node-IP poller (see data.external.node_ip in nodes.tf) can run virsh over
  # SSH on the hypervisor.
  ssh_target = regex("qemu\\+ssh://([^/]+)", var.libvirt_uri)[0]
}

# Resolve the Talos image factory schematic ID once per schematic file.
data "http" "schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

# Download the Talos raw image and convert it locally to a sparse qcow2 so the
# libvirt provider has a fast, format-correct payload to upload (raw is ~1 GiB
# and matches what the factory serves; qcow2 sparse trims that to ~100 MiB).
# Idempotent: skips if the target qcow2 already exists.
resource "terraform_data" "download_image" {
  triggers_replace = {
    url = local.image_url
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      command -v qemu-img >/dev/null || { echo "qemu-img not found — install qemu (brew install qemu / apt install qemu-utils)" >&2; exit 1; }
      mkdir -p "${local.image_dir}"
      if [ ! -f "${local.image_local}" ]; then
        echo "Downloading ${local.image_url}"
        tmp_gz="${local.image_local}.tmp.gz"
        tmp_raw="${local.image_local}.tmp.raw"
        curl -fsSL "${local.image_url}" -o "$tmp_gz"
        gunzip -c "$tmp_gz" > "$tmp_raw"
        qemu-img convert -f raw -O qcow2 "$tmp_raw" "${local.image_local}"
        rm -f "$tmp_gz" "$tmp_raw"
      fi
    EOT
  }
}

resource "libvirt_pool" "this" {
  name = var.pool_name
  type = "dir"

  target = {
    path = var.pool_path
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }
}

# Base image volume: uploaded once, used as the backing store for every node OS disk.
resource "libvirt_volume" "talos_base" {
  depends_on = [terraform_data.download_image]

  name = "${local.image_basename}.qcow2"
  pool = libvirt_pool.this.name

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = "file://${local.image_local}"
    }
  }
}
