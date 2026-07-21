# OpenTofu — structure and design notes

## File conventions

- All OpenTofu config uses `.tofu` extension, not `.tf`. Templates use `.tftpl`.
- `terraform.tfvars` is gitignored; `terraform.tfvars.example` is the reference.
- Every module must declare `required_providers` in its own `versions.tofu`. OpenTofu does not inherit provider source
  from the root module — omitting it causes a lookup for `hashicorp/libvirt`, which does not exist.

---

## Module hierarchy

```
modules/networks-catalog/    Data-only module — outputs the standard networks map (bridge, management, isolated)
modules/libvirt-networks/    Thin resource emitter — creates libvirt_network resources from a networks map
modules/libvirt-vm/          Pure domain module — creates a libvirt_domain from a networks map
modules/ubuntu-vm/           Ubuntu wrapper — volumes + cloud-init, calls libvirt-vm
modules/talos-vm/            Talos VM wrapper — volumes, calls libvirt-vm, virsh IP discovery
modules/github-runner-vm/    GitHub Actions runner — calls ubuntu-vm with cloud-init runner setup
modules/talos-cluster/       Talos bootstrapping only — no libvirt; accepts nodes with pre-discovered IPs
environments/                Root modules
talos/                       Legacy standalone Talos root module (kept for existing state)
```

## Networking model

All three VM modules (`libvirt-vm`, `ubuntu-vm`, `talos-vm`) accept a single `networks` map keyed by
label — one NIC per entry. The two networks modules produce/normalize that map:

- **`networks-catalog`** returns the standard three-network map (bridge, management, isolated).
  Shared across environments; site-invariant parts live here (subnets, gateways, DNS servers).
  Only input is `bridge_interface` (host bridge device).
- **`libvirt-networks`** takes any networks map, creates `libvirt_network` resources for `nat`/`none`
  entries (bridge entries are metadata-only — the host bridge is expected to already exist), and
  returns the map with a `id` field forcing resource-dependency ordering on consumers.

The consumer-facing schema (what `libvirt-vm` and `ubuntu-vm` accept):

```hcl
map(object({
  mode        = string                       # "bridge" | "nat" | "none"
  name        = optional(string, null)       # libvirt network name — required if mode != bridge
  bridge_name = optional(string, null)       # host bridge device — required if mode == bridge
  mac_address = optional(string, null)       # per-NIC MAC (DHCP reservations)
  wait_for_ip = optional(bool, true)         # false skips libvirt's lease-wait on this NIC
  static_ip   = optional(string, null)       # cloud-init address (CIDR, e.g. "10.0.1.163/16")
  gateway     = optional(string, null)       # cloud-init default route
  dns_servers = optional(list(string), [])   # cloud-init nameservers
}))
```

`libvirt-vm` consumes `mode`, `name`, `bridge_name`, `mac_address`, `wait_for_ip`, `static_ip`
(for wait strategy and output fallback). `gateway`/`dns_servers` are passthrough — used only by
`ubuntu-vm` when it generates cloud-init netplan. Extra fields in a passed-in object (e.g.
`prefix`, `id` from `networks-catalog`) are silently dropped by the type constraint.

**Wait strategy in libvirt-vm** (governs when `tofu apply` returns):

- Bridge NIC → no wait (libvirt has no view of DHCP on an external bridge).
- NAT/none NIC without `static_ip` and with `wait_for_ip = true` (default) → lease-wait.
- NAT/none NIC with `static_ip` → no wait (a statically-configured guest never DHCPs).
- If nothing lease-waits and some NIC has a `static_ip` → agent-wait on the first such NIC
  (proof-of-life for bridge-only VMs).
- `wait_for_ip = false` → never wait (used by `talos-vm` — Talos boots into maintenance mode).

**Environment wiring** (see `environments/dev/dc-ci/` for the reference pattern):

```hcl
module "catalog" {
  source           = "../../../modules/networks-catalog"
  bridge_interface = var.bridge_interface
}

module "networks" {
  source   = "../../../modules/libvirt-networks"
  networks = module.catalog.networks
}
```

To add an environment-specific network, merge it in:

```hcl
module "networks" {
  source = "../../../modules/libvirt-networks"
  networks = merge(module.catalog.networks, {
    datacenter = { mode = "bridge", bridge_name = "br1", prefix = 16, gateway = "10.99.0.1", dns_servers = ["10.99.0.10"] }
  })
}
```

To modify a shared network, edit `modules/networks-catalog/outputs.tofu` — every environment picks it up.

### `modules/libvirt-vm`

Manages only the libvirt domain. It accepts disk references as typed objects and a networks map;
it does not create volumes or generate cloud-init.

**Key variables:**

| Variable         | Type                               | Notes                                                                             |
|------------------|------------------------------------|-----------------------------------------------------------------------------------|
| `os_disk`        | `object({pool, volume})`           | Required. Attached as `vda`.                                                      |
| `cloudinit_disk` | `object({pool, volume})` or `null` | Attached as `hda` cdrom; null = no cloud-init.                                    |
| `extra_disks`    | `list(object({pool, volume}))`     | Attached as `vdb`, `vdc`, … in list order.                                        |
| `networks`       | `map(object({...}))`               | One NIC per entry, alphabetical key order. See the Networking model section.      |
| `cpu_mode`       | `string` or `null`                 | KVM CPU mode (e.g. `host-passthrough`). Null uses the libvirt default.            |

Disk device names (`vdb`, `vdc`, …) are assigned by position in the `extra_disks` list — order is stable, so callers
must not reorder entries after first apply. NIC device names (`enp0s2`, `enp0s3`, …) are assigned in alphabetical
order of the `networks` map keys.

IP discovery uses the QEMU guest agent (`source = "agent"`) when nothing lease-waits, and lease info otherwise —
selected automatically from the network configuration. `qemu-guest-agent` must be running in the guest for the agent
source. Per-interface details (observed IPs, MAC, `static_ip_detected`) are on `network_interfaces` in the output.

**Do not expose the disk driver config** (`name = "qemu"`, `type = "qcow2"`, `cache = "none"`). It is a consequence of
the qcow2 volume format and hardcoding it prevents the caller from setting an inconsistent type.

**Outputs:** `ip_addresses` (bridge-first, includes static_ip fallbacks), `primary_ip_address`, `network_interfaces`
(per-interface metadata + observed IPs + `static_ip_detected` boolean), `name`, `uuid`.

### `modules/ubuntu-vm`

Owns all storage and cloud-init for Ubuntu VMs:

- `libvirt_volume.os` — OS disk, sized to `os_disk_size_gb`, sourced from `base_image_source` URL
- `libvirt_volume.extra` — one per entry in `extra_disks` (type `list(object({name, size_gb, pool?}))`)
- `libvirt_cloudinit_disk` + `libvirt_volume.cloudinit` — rendered from templates in `templates/`
- Calls `module.vm` (libvirt-vm) with assembled `{pool, volume}` references and the same `networks` map

**Networks:** `ubuntu-vm` accepts the same `networks` map shape as `libvirt-vm` (see Networking model). Per-network
`static_ip`, `gateway`, and `dns_servers` are used to render cloud-init netplan. The first bridge-mode entry (or the
first entry alphabetically if no bridge) becomes the "primary" — it inherits DHCP routes and DNS when it has no
static_ip; DHCP on other interfaces suppresses route/DNS propagation via netplan's `dhcp4-overrides`.

**Templates** (in `modules/ubuntu-vm/templates/`):

| File                   | Purpose                                                                                 |
|------------------------|-----------------------------------------------------------------------------------------|
| `user-data.tftpl`      | Creates `ubuntu` user, injects SSH keys, installs `qemu-guest-agent` + `extra_packages` |
| `meta-data.tftpl`      | Sets `instance-id` and `local-hostname`                                                 |
| `network-config.tftpl` | Netplan config per interface, static IP or DHCP driven by `networks[*].static_ip`       |

The `extra_packages` variable (list of strings, default `[]`) lets callers install additional packages at first boot.
This is the extension point for purpose-specific VMs — e.g. an `nginx-vm` wrapper would call `ubuntu-vm` with
`extra_packages = ["nginx"]`.

**Default Ubuntu image:** `noble-server-cloudimg-amd64.img` (24.04 LTS). Override with `base_image_source`.

**Extra disk ordering:** `extra_disks` in `ubuntu-vm` is `list(object({name, size_gb, pool?}))`. The `name` field is
used for volume naming only. Volumes are passed to `libvirt-vm` preserving the original list order so device
assignments (`vdb`, `vdc`, …) are stable.

### `modules/libvirt-networks`

Thin resource emitter. Takes a `networks` map, creates `libvirt_network` for `nat`/`none` entries, and returns the
map with an `id` field wired to the created resource (or `null` for bridges). Bridge-mode entries are metadata-only —
the host bridge must already exist on the hypervisor.

**Input schema** (a superset of the consumer schema, adds creation-time fields for `libvirt_network`):

```hcl
map(object({
  mode        = string                        # "bridge" | "nat" | "none"
  bridge_name = optional(string, null)        # required for bridge; also settable on nat modes to name the libvirt bridge
  address     = optional(string, null)        # e.g. "172.20.0.1"
  prefix      = optional(number, null)        # e.g. 24
  gateway     = optional(string, null)        # defaults to address if unset in the output
  dns_servers = optional(list(string), [])
  dhcp_start  = optional(string, null)        # both dhcp_start and dhcp_end required to enable DHCP
  dhcp_end    = optional(string, null)
}))
```

### `modules/networks-catalog`

Data-only module (no resources, no provider dependency). Outputs a standard three-network map:

| Key          | Mode     | Purpose                                                                |
|--------------|----------|------------------------------------------------------------------------|
| `bridge`     | `bridge` | Host bridge attachment; `bridge_name` from `var.bridge_interface`.     |
| `management` | `nat`    | libvirt-managed NAT subnet with DHCP (172.20.0.0/24).                  |
| `isolated`   | `none`   | Host-only network with DHCP but no NAT (192.168.20.0/24).              |

The catalog is designed to be passed straight to `libvirt-networks.networks`, or merged with per-environment
additions/overrides. Site-invariant defaults (subnets, gateways, DNS servers) live in `outputs.tofu` — edit there to
change the fleet-wide catalog.

### `modules/talos-vm`

Wraps `libvirt-vm` for Talos nodes. Creates an OS volume (qcow2 overlay on a pre-uploaded base image) and a data disk. *
*No machine config is embedded** — nodes boot into Talos maintenance mode; config is pushed later by `talos_machine` in
the `talos/` environment.

- `base_image_path`: file path of the Talos base qcow2 on the hypervisor (backing store path from `libvirt_volume.path`)
- `cluster_vip`: optional; excludes the VIP from IP discovery. Null is safe for fresh clusters before bootstrap. Set it
  in `kvm-talos-xx` tfvars once the cluster is running.
- IP discovery uses `data.external.node_ip` (virsh SSH, `--source agent`). The libvirt guest-agent data source is NOT
  used — it returns Kubernetes-internal interfaces (VIP, Cilium, etc.) once the node is in a cluster.
- Sets `cpu_mode = "host-passthrough"` unconditionally; sets `wait_for_ip = false` on the interface.

### `modules/talos-cluster`

Pure Talos cluster bootstrapping — **no libvirt resources**. Accepts nodes with pre-discovered IPs (from `kvm-talos-xx`
outputs or known bare-metal IPs).

| Variable        | Type                                               | Notes                                                                                                                                                                                                            |
|-----------------|----------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `nodes`         | `map({ip, role, installer_image, config_patches})` | Required. `installer_image` is per-node (supports heterogeneous schematics). `config_patches` is a list of raw Talos config YAML strings applied after the role patch — use for GPU drivers, kernel params, etc. |
| `talos_version` | `string`                                           | Used for `talos_machine_configuration`.                                                                                                                                                                          |
| `cluster`       | `object`                                           | name, vip, kubernetes_version                                                                                                                                                                                    |
| `output_dir`    | `string`                                           | Where kubeconfig + talosconfig are written. Pass `"${path.root}/output"`.                                                                                                                                        |

**Key design notes:**

- No libvirt, no image download, no pool management. Those live in `kvm-talos-xx`.
- The kubeconfig written by the previous apply is read back as `bootstrap_kubeconfig` to enable `drain_on_upgrade`
  without a dependency cycle.
- Machine config templates: `machine-config/controlplane.yaml.tftpl` (inlines Cilium),
  `machine-config/worker.yaml.tftpl` (minimal), `machine-config/hostname.yaml.tftpl`.

---

## Talos cluster workflow

```
environments/dev/
├── kvm-talos-01/     VM nodes on kvm-01 — pool, per-schematic images, talos-vm instances
│                     outputs: nodes = { name → { ip, installer_image } }
│                              talos_version
├── kvm-talos-02/     (optional) VM nodes on kvm-02 — same structure
└── talos/            Cluster bootstrapping — reads kvm-talos-xx via terraform_remote_state,
                      merges with bare_metal_nodes tfvar, calls talos-cluster
```

**Apply order:** `kvm-talos-xx apply` → `talos apply`

### Per-node schematics in `kvm-talos-xx`

Each node can specify `schematic_path` (relative to the environment root). The environment resolves unique schematics,
makes one HTTP call per unique schematic to the Talos factory, downloads/uploads one base image per unique schematic,
and maps each node to the correct base image and installer_image.

```
schematics/
├── default.yaml     qemu-guest-agent only
├── nvidia.yaml      qemu-guest-agent + NVIDIA firmware extension
└── camera.yaml      qemu-guest-agent + camera-specific kernel modules
```

Nodes without a `schematic_path` use `image.default_schematic_path` (defaults to `schematics/default.yaml`).

### Bare-metal and heterogeneous clusters

Bare-metal nodes (or VMs on a hypervisor not managed by any `kvm-talos-xx`) are added directly in
`talos/terraform.tfvars` under `bare_metal_nodes`:

```hcl
bare_metal_nodes = {
  "bm-gpu-00" = {
    ip              = "192.168.1.50"
    role            = "worker"
    installer_image = "factory.talos.dev/installer/<schematic-id>:v1.12.0"
    config_patches = [file("patches/nvidia.yaml")]
  }
}
```

### Multi-hypervisor

Add a `kvm-talos-02/` environment and register its statefile in `talos/terraform.tfvars`:

```hcl
kvm_talos_state_paths = {
  kvm-talos-01 = "../kvm-talos-01/terraform.tfstate"
  kvm-talos-02 = "../kvm-talos-02/terraform.tfstate"
}
```

---

## Environment structure

Two patterns exist in the tree; new environments should use the catalog pattern.

**Catalog pattern (recommended, e.g. `dc-ci`)** — networks come from the shared `networks-catalog`
module, VMs get per-NIC config via a `networks` map:

```
environments/<env-name>/<name>/
├── versions.tofu               required_version + provider "libvirt"
├── variables.tofu              libvirt_uri, pool_path, bridge_interface, ssh_authorized_keys, ubuntu_vms
├── main.tofu                   libvirt_pool + module "catalog" + module "networks" + module "ubuntu"
├── outputs.tofu                vms = { name => { ip_addresses, ssh, by_network, ... } }
├── justfile
└── terraform.tfvars.example
```

**Local-network pattern (legacy, e.g. `kvm-01`)** — networks defined inline as `libvirt_network`
resources; VMs pick a single network by name. Kept for existing state; do not use as a template
for new environments.

```
environments/dev/kvm-01/
├── versions.tofu
├── variables.tofu              libvirt_uri, pool_path, bridge_interface, ubuntu_vms (with network_name scalar)
├── networks.tofu               inline libvirt_network resources + local.networks map for ubuntu-vm
├── ubuntu.tofu / github-runner.tofu
├── outputs.tofu
└── justfile
```

Each root module is an independent OpenTofu state. Adding a second hypervisor means creating
`environments/dev/<name>/` rather than using provider aliases (which must be static).

### The `ubuntu_vms` variable (catalog pattern)

```hcl
variable "ubuntu_vms" {
  type = map(object({
    memory_mb       = optional(number, 2048)
    vcpu_count      = optional(number, 2)
    os_disk_size_gb = optional(number, 20)
    extra_packages  = optional(list(string), [])
    extra_disks     = optional(list(object({ name = string, size_gb = number, pool = optional(string, null) })), [])
    networks = map(object({
      static_ip   = optional(string, null)
      gateway     = optional(string, null)
      dns_servers = optional(list(string), null)
      mac_address = optional(string, null)
      wait_for_ip = optional(bool, null)
    }))
  }))
  default = {}
}
```

Each VM's `networks` map selects entries from the catalog by key. Fields left `null` pass through
to catalog defaults. Example:

```hcl
ubuntu_vms = {
  ubuntu-01 = {
    networks = {
      bridge     = { static_ip = "10.0.1.163/16" }
      management = {}
    }
  }
  ubuntu-02 = {
    memory_mb = 4096
    networks = {
      bridge     = { static_ip = "10.0.1.164/16", mac_address = "52:54:00:12:34:56" }
      management = {}
    }
  }
}
```

The environment's `main.tofu` merges each VM's overrides into the catalog entry (nulls stripped
so catalog defaults survive):

```hcl
locals {
  vm_networks = {
    for vm_name, vm_cfg in var.ubuntu_vms :
    vm_name => {
      for network_name, overrides in vm_cfg.networks :
      network_name => merge(
        module.networks.networks[network_name],
        { for k, v in overrides : k => v if v != null }
      )
    }
  }
}
```

### Networks (catalog pattern)

Three networks are provided by `modules/networks-catalog`, shared across all catalog-pattern
environments:

| Key          | Mode     | Subnet           | Purpose                                         |
|--------------|----------|------------------|-------------------------------------------------|
| `bridge`     | `bridge` | host LAN (10.0.1.0/16 defaults) | Attach to a physical LAN via the host bridge.   |
| `management` | `nat`    | 172.20.0.0/24    | libvirt-managed NAT with DHCP.                  |
| `isolated`   | `none`   | 192.168.20.0/24  | Host-only isolated network with DHCP.           |

`bridge_interface` sets the host bridge device (default `br0`). To evolve the catalog fleet-wide,
edit `modules/networks-catalog/outputs.tofu`.

---

## Adding a second hypervisor

```bash
cp -r tofu/environments/dev/kvm-01 tofu/environments/dev/kvm-02
# edit kvm-02/terraform.tfvars (or run `just configure` from that dir)
```

Add to `tofu/justfile`:

```
mod dev-kvm02 "environments/dev/kvm-02/justfile"
```

---

## Adding a new VM type

For a purpose-specific VM (e.g. nginx), create `modules/nginx-vm/` that wraps `ubuntu-vm` with
`extra_packages = ["nginx"]` and any additional cloud-init `runcmd` steps. The existing `ubuntu-vm` variable interface
is the composition point.

---

## Talos (`talos/`)

Legacy standalone root module retained for its existing state. New Talos deployments should use
`environments/dev/talos/` (which calls `modules/talos-cluster`). The standalone module has its own image pipeline and IP
discovery — do not modify it in ways that would drift from `modules/talos-cluster`.

---

## `tofu/justfile` aggregation

```
mod talos             "talos/justfile"
mod dev               "environments/dev/kvm-01/justfile"
mod dev-kvm-talos-01  "environments/dev/kvm-talos-01/justfile"
mod dev-talos         "environments/dev/talos/justfile"
```

`kvm-talos-xx` justfiles expose: `configure`, `init`, `plan`, `apply`, `destroy`, `ips`, `console <node>`.
`talos/` justfile exposes: `configure`, `init`, `plan`, `apply`, `upgrade`, `destroy`, `talosctl`, `kubectl`.

Add a second hypervisor: copy `kvm-talos-01/` to `kvm-talos-02/`, configure tfvars, add `mod dev-kvm-talos-02` to
`tofu/justfile`, and add the new statefile path to `talos/terraform.tfvars`.
