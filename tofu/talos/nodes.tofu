resource "libvirt_volume" "os" {
  for_each = var.nodes

  name     = "${each.key}-os.qcow2"
  pool     = libvirt_pool.this.name
  capacity = coalesce(each.value.os_disk_gb, var.node_os_disk_gb) * 1024 * 1024 * 1024

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.talos_base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "data" {
  for_each = var.nodes

  name     = "${each.key}-data.qcow2"
  pool     = libvirt_pool.this.name
  capacity = coalesce(each.value.data_disk_gb, var.node_data_disk_gb) * 1024 * 1024 * 1024

  target = {
    format = { type = "qcow2" }
  }
}

# Talos's nocloud platform reads the machine config from the cidata ISO at first
# boot, so the node comes up with its static IP already configured. Subsequent
# config changes go through talos_machine, not this disk.
resource "libvirt_cloudinit_disk" "this" {
  for_each = var.nodes

  name = "${each.key}-cidata.iso"

  user_data = data.talos_machine_configuration.this[each.key].machine_configuration
  # Hostname comes from the machine config (machine.network.hostname). Setting
  # local-hostname here too makes Talos's nocloud platform synthesise a separate
  # HostnameConfig document, which then collides with v1alpha1's hostname when
  # talos_machine re-applies — "static hostname is already set in v1alpha1 config".
  meta_data = yamlencode({
    instance-id = each.key
  })
}

# Upload the cidata ISO produced by libvirt_cloudinit_disk into the storage pool
# so libvirt can attach it as a CD-ROM regardless of the connection (qemu+ssh).
resource "libvirt_volume" "cidata" {
  for_each = var.nodes

  name = "${each.key}-cidata.iso"
  pool = libvirt_pool.this.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.this[each.key].path
    }
  }
}

resource "libvirt_domain" "node" {
  for_each = var.nodes

  name        = "talos-${each.key}"
  description = "Talos node ${each.key} (${var.cluster.name})"
  type        = "kvm"
  memory      = coalesce(each.value.memory_mb, var.node_memory_mb)
  memory_unit = "MiB"
  vcpu        = coalesce(each.value.vcpu, var.node_vcpu)
  running     = true

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type = "hvm"
  }

  devices = {
    disks = [
      {
        device = "disk"
        target = { dev = "vda", bus = "virtio" }
        source = {
          volume = {
            pool   = libvirt_volume.os[each.key].pool
            volume = libvirt_volume.os[each.key].name
          }
        }
        driver = {
          name  = "qemu"
          type  = "qcow2"
          cache = "none"
        }
      },
      {
        device = "disk"
        target = { dev = "vdb", bus = "virtio" }
        source = {
          volume = {
            pool   = libvirt_volume.data[each.key].pool
            volume = libvirt_volume.data[each.key].name
          }
        }
        driver = {
          name = "qemu"
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        target = { dev = "sda", bus = "sata" }
        source = {
          volume = {
            pool   = libvirt_volume.cidata[each.key].pool
            volume = libvirt_volume.cidata[each.key].name
          }
        }
      }
    ]

    serials = [
      {
        target = {
          type = "isa-serial"
          port = 0
        }
      }
    ]

    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    channels = [
      {
        source = { unix = {} }
        target = { virt_io = { name = "org.qemu.guest_agent.0" } }
      }
    ]

    interfaces = [
      {
        mac = each.value.mac_address != null ? { address = each.value.mac_address } : null
        source = {
          bridge = { bridge = var.vm_bridge_interface }
        }
        model = { type = "virtio" }
      }
    ]
  }
}

# Discover the DHCP-assigned IPv4 for each node by polling virsh on the
# hypervisor over SSH. libvirt's data.libvirt_domain_interface_addresses returns
# whatever the guest agent has reported so far — that includes IPv6 link-local
# the moment Talos boots, well before DHCP completes, and also every
# Kubernetes-internal interface (cilium_host, etc.) once kubelet starts. Polling
# lets us wait specifically for an IPv4 on the primary NIC (eth*/enp*/ens*) and
# exclude the VIP, with retries that don't block plan/refresh.
data "external" "node_ip" {
  for_each = libvirt_domain.node

  program = ["bash", "-c", <<-EOT
    set -euo pipefail
    q=$(cat)
    remote=$(jq -r .ssh_target <<<"$q")
    dom=$(jq -r .domain_name <<<"$q")
    vip=$(jq -r .vip <<<"$q")
    for i in $(seq 1 60); do
      out=$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$remote" "virsh domifaddr --domain $dom --source agent" 2>/dev/null || true)
      ip=$(echo "$out" | awk -v vip="$vip" '
        $1 ~ /^(eth|enp|ens)/ && $3 == "ipv4" {
          sub(/\/.*/, "", $4)
          if ($4 != vip) { print $4; exit }
        }')
      if [ -n "$ip" ]; then
        printf '{"ip":"%s"}' "$ip"
        exit 0
      fi
      sleep 5
    done
    echo "Timed out waiting for IPv4 on $dom" >&2
    exit 1
  EOT
  ]

  query = {
    # domain_uuid forces deferral to apply time (unknown until libvirt_domain is created)
    domain_uuid = each.value.uuid
    domain_name = each.value.name
    ssh_target  = local.ssh_target
    vip         = var.cluster.vip
  }
}

locals {
  node_ips            = { for k, v in data.external.node_ip : k => v.result.ip }
  node_keys           = keys(var.nodes)
  control_plane_ips   = [for k in local.node_keys : local.node_ips[k]]
  first_control_plane = local.control_plane_ips[0]
}
