resource "libvirt_volume" "os" {
  name     = "${var.name}-os.qcow2"
  pool     = var.pool_name
  capacity = var.os_disk_size_gb * 1024 * 1024 * 1024

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = var.base_image_path
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "data" {
  name     = "${var.name}-data.qcow2"
  pool     = var.pool_name
  capacity = var.data_disk_size_gb * 1024 * 1024 * 1024

  target = {
    format = { type = "qcow2" }
  }
}

module "vm" {
  source = "../libvirt-vm"

  name       = var.name
  memory_mb  = var.memory_mb
  vcpu_count = var.vcpu_count
  cpu_mode   = "host-passthrough"

  os_disk = {
    pool   = libvirt_volume.os.pool
    volume = libvirt_volume.os.name
  }

  extra_disks = [
    {
      pool   = libvirt_volume.data.pool
      volume = libvirt_volume.data.name
    }
  ]

  # IP discovery is handled below via virsh; libvirt's guest-agent source
  # returns every Kubernetes-internal interface once kubelet starts.
  networks = {
    bridge = {
      mode        = "bridge"
      bridge_name = var.bridge
      mac_address = var.mac_address
      wait_for_ip = false
    }
  }
}

# Discover the DHCP-assigned IPv4 by polling virsh on the hypervisor over SSH.
# Talos boots in maintenance mode (no cidata); machine config is pushed later
# by talos_machine in the talos environment.
data "external" "node_ip" {
  program = ["bash", "-c", <<-EOT
    set -euo pipefail
    q=$(cat)
    remote=$(jq -r .ssh_target <<<"$q")
    dom=$(jq -r .domain_name <<<"$q")
    vip=$(jq -r '.vip // ""' <<<"$q")
    for i in $(seq 1 60); do
      out=$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$remote" "virsh domifaddr --domain $dom --source agent" 2>/dev/null || true)
      ip=$(echo "$out" | awk -v vip="$vip" '
        $1 ~ /^(eth|enp|ens)/ && $3 == "ipv4" {
          sub(/\/.*/, "", $4)
          if (vip == "" || $4 != vip) { print $4; exit }
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
    # domain_uuid is unknown until libvirt_domain is created, forcing deferral to apply time
    domain_uuid = module.vm.uuid
    domain_name = module.vm.name
    ssh_target  = var.ssh_target
    vip         = var.cluster_vip
  }
}
