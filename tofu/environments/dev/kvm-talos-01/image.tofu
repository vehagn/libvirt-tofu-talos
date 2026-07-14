locals {
  # Resolve each node's effective schematic path (relative to path.root)
  node_schematic_paths = {
    for name, node in var.nodes : name => coalesce(node.schematic_path, var.image.default_schematic_path)
  }

  # Unique schematic paths — one HTTP call + one image download per unique schematic
  unique_schematic_paths = toset(values(local.node_schematic_paths))

  image_dir = abspath("${path.root}/.images")
}

# Resolve each unique schematic to a factory schematic ID
data "http" "schematic_id" {
  for_each = local.unique_schematic_paths

  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = file("${path.root}/${each.key}")
}

locals {
  schematic_ids = {
    for path, resp in data.http.schematic_id : path => jsondecode(resp.response_body).id
  }

  # Per-schematic image metadata
  image_meta = {
    for path, id in local.schematic_ids : path => {
      id       = id
      basename = "talos-${id}-${var.image.version}-${var.image.platform}-${var.image.arch}"
      url      = "${var.image.factory_url}/image/${id}/${var.image.version}/${var.image.platform}-${var.image.arch}.raw.gz"
      local    = "${local.image_dir}/talos-${id}-${var.image.version}-${var.image.platform}-${var.image.arch}.qcow2"
    }
  }

  # Per-node derived values
  node_schematic_id    = { for name, _ in var.nodes : name => local.schematic_ids[local.node_schematic_paths[name]] }
  node_installer_image = { for name, id in local.node_schematic_id : name => "factory.talos.dev/installer/${id}:${var.image.version}" }
  node_base_image_path = { for name, _ in var.nodes : name => libvirt_volume.talos_base[local.node_schematic_paths[name]].path }
}

# Download each unique Talos image (idempotent — skips if already present)
resource "terraform_data" "download_image" {
  for_each = local.image_meta

  triggers_replace = {
    url = each.value.url
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      command -v qemu-img >/dev/null || { echo "qemu-img not found — install qemu (brew install qemu / apt install qemu-utils)" >&2; exit 1; }
      mkdir -p "${local.image_dir}"
      local_path="${each.value.local}"
      if [ ! -f "$local_path" ]; then
        echo "Downloading ${each.value.url}"
        tmp_gz="$local_path.tmp.gz"
        tmp_raw="$local_path.tmp.raw"
        curl -fsSL "${each.value.url}" -o "$tmp_gz"
        gunzip -c "$tmp_gz" > "$tmp_raw"
        qemu-img convert -f raw -O qcow2 "$tmp_raw" "$local_path"
        rm -f "$tmp_gz" "$tmp_raw"
      fi
    EOT
  }
}

# Upload each unique base image to the pool — used as the backing store for node OS disks
resource "libvirt_volume" "talos_base" {
  for_each = local.image_meta

  depends_on = [terraform_data.download_image]

  name = "${each.value.basename}.qcow2"
  pool = libvirt_pool.talos.name

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = "file://${each.value.local}"
    }
  }
}
