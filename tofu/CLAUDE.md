# OpenTofu — structure and design notes

## File conventions

- All OpenTofu config uses `.tofu` extension, not `.tf`. Templates use `.tftpl`.
- `terraform.tfvars` is gitignored; `terraform.tfvars.example` is the reference.
- Every module must declare `required_providers` in its own `versions.tofu`. OpenTofu does not inherit provider source
  from the root module — omitting it causes a lookup for `hashicorp/libvirt`, which does not exist.

---

## Module hierarchy

```
modules/libvirt-vm/     Pure domain module — creates a libvirt_domain only
modules/ubuntu-vm/      Ubuntu wrapper — volumes + cloud-init, calls libvirt-vm
modules/talos-vm/       Talos VM wrapper — volumes, calls libvirt-vm, virsh IP discovery
modules/talos-cluster/  Talos bootstrapping only — no libvirt; accepts nodes with pre-discovered IPs
environments/           Root modules
talos/                  Legacy standalone Talos root module (kept for existing state)
```

### `modules/libvirt-vm`

Manages only the libvirt domain. It accepts disk references as typed objects; it does not create volumes or generate
cloud-init.

**Key variables:**

| Variable         | Type                                                                 | Notes                                                                                              |
|------------------|----------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| `os_disk`        | `object({pool, volume})`                                             | Required. Attached as `vda`.                                                                       |
| `cloudinit_disk` | `object({pool, volume})` or `null`                                   | Attached as `hda` cdrom; null = no cloud-init.                                                     |
| `extra_disks`    | `list(object({pool, volume}))`                                       | Attached as `vdb`, `vdc`, … in list order.                                                         |
| `interfaces`     | `list(object({network_name?, bridge?, mac_address?, wait_for_ip?}))` | Exactly one of `network_name` or `bridge` per entry (validated). `wait_for_ip` defaults to `true`. |

Disk device names (`vdb`, `vdc`, …) are assigned by position in the `extra_disks` list — order is stable, so callers
must not reorder entries after first apply.

IP discovery always reads from the QEMU guest agent (`source = "agent"`), so `qemu-guest-agent` must be running in the
guest. The `data.libvirt_domain_interface_addresses` resource is unconditional; it returns all interface IPs after the
domain is running.

**Do not expose the disk driver config** (`name = "qemu"`, `type = "qcow2"`, `cache = "none"`). It is a consequence of
the qcow2 volume format and hardcoding it prevents the caller from setting an inconsistent type.

**Recent additions to `modules/libvirt-vm`:**

- `cpu_mode` variable (optional, default `null`) — sets KVM CPU mode (e.g. `host-passthrough`)
- `uuid` output — exposes the libvirt domain UUID (unknown until apply)
- `mac_address` is now wired through to the domain interface (was declared but unused)

### `modules/ubuntu-vm`

Owns all storage and cloud-init for Ubuntu VMs:

- `libvirt_volume.os` — OS disk, sized to `os_disk_size_gb`, sourced from `base_image_source` URL
- `libvirt_volume.extra` — one per entry in `extra_disks` (type `list(object({name, size_gb, pool?}))`)
- `libvirt_cloudinit_disk` + `libvirt_volume.cloudinit` — rendered from templates in `templates/`
- Calls `module.vm` (libvirt-vm) with assembled `{pool, volume}` references

**Templates** (in `modules/ubuntu-vm/templates/`):

| File                   | Purpose                                                                                 |
|------------------------|-----------------------------------------------------------------------------------------|
| `user-data.tftpl`      | Creates `ubuntu` user, injects SSH keys, installs `qemu-guest-agent` + `extra_packages` |
| `meta-data.tftpl`      | Sets `instance-id` and `local-hostname`                                                 |
| `network-config.tftpl` | Netplan static IP config; rendered only when `static_ip` is set                         |

The `extra_packages` variable (list of strings, default `[]`) lets callers install additional packages at first boot.
This is the extension point for purpose-specific VMs — e.g. an `nginx-vm` wrapper would call `ubuntu-vm` with
`extra_packages = ["nginx"]`.

**Default Ubuntu image:** `noble-server-cloudimg-amd64.img` (24.04 LTS). Override with `base_image_source`.

**Extra disk ordering:** `extra_disks` in `ubuntu-vm` is `list(object({name, size_gb, pool?}))`. The `name` field is
used for volume naming only. Volumes are passed to `libvirt-vm` preserving the original list order so device
assignments (`vdb`, `vdc`, …) are stable.

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

```
environments/
└── <env-name>/
    └── <hypervisor-hostname>/    ← one OpenTofu root module per hypervisor
        ├── versions.tofu         provider + required_version
        ├── variables.tofu        libvirt_uri, pool_path, bridge_interface, ssh_authorized_keys, vms
        ├── pool.tofu             libvirt_pool.dev
        ├── networks.tofu         management (nat), isolated (none), bridge
        ├── main.tofu             module "ubuntu" { for_each = var.vms }
        ├── outputs.tofu          vms = { name => { ip, ssh } }
        ├── justfile
        └── terraform.tfvars.example
```

Each hypervisor directory is an independent OpenTofu state. This avoids the OpenTofu constraint that provider aliases
must be static — adding a second hypervisor means creating `environments/dev/kvm-02/` rather than using provider
aliases.

### The `vms` variable

```hcl
variable "vms" {
  type = map(object({
    memory_mb = optional(number, 2048)
    vcpu_count = optional(number, 2)
    os_disk_size_gb = optional(number, 20)
    extra_packages = optional(list(string), [])
    network_name = optional(string, "management")  # must match a libvirt_network name in this root module
  }))
  default = {}
}
```

Map keys become VM names. Example:

```hcl
vms = {
  "ubuntu-01" = {}
  "web-01" = { extra_packages = ["nginx"] }
  "db-01" = { memory_mb = 4096, os_disk_size_gb = 50, network_name = "isolated" }
}
```

### Networks

Three networks are defined per hypervisor root module:

| Resource                     | Name         | Mode     | Subnet           |
|------------------------------|--------------|----------|------------------|
| `libvirt_network.management` | `management` | `nat`    | 192.168.100.0/24 |
| `libvirt_network.isolated`   | `isolated`   | `none`   | 10.100.0.0/24    |
| `libvirt_network.bridge`     | `bridge`     | `bridge` | host bridge      |

`bridge_interface` variable sets the host bridge device name (default `br0`).

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
