# OpenTofu — VM Management

Manages VMs on the libvirt hypervisor via the [
`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs) provider.

## Usage

```bash
just configure              # generate terraform.tfvars from setup.env
just tofu ubuntu init       # first time only
just tofu ubuntu apply
just tofu ubuntu ssh        # SSH into the VM
just tofu ubuntu console    # serial console via hypervisor (exit with Ctrl+])
just tofu ubuntu destroy

# Talos cluster (3 nodes, control plane + workload on each)
just tofu talos init
just tofu talos apply
just tofu talos kubectl get nodes
just tofu talos upgrade     # rolling OS upgrade (after bumping image.version)
```

## Module: `modules/vm`

Creates a single VM from a cloud image with cloud-init first-boot configuration. The base image is downloaded once;
per-VM disks only store deltas (qcow2 copy-on-write).

| Variable              | Default | Description                          |
|-----------------------|---------|--------------------------------------|
| `name`                | —       | VM and resource name                 |
| `hostname`            | —       | OS hostname (via cloud-init)         |
| `memory_mb`           | `2048`  | RAM in MiB                           |
| `vcpu_count`          | `2`     | Virtual CPUs                         |
| `disk_size_gb`        | `20`    | Root disk in GiB                     |
| `base_image_source`   | —       | Cloud image URL or path              |
| `ssh_authorized_keys` | —       | SSH public keys for the default user |

## Provider conventions

Every module (not just root modules) must declare provider dependencies in a `versions.tf` with a `required_providers`
block. OpenTofu does not inherit provider source from the root module — omitting it causes it to look up
`hashicorp/libvirt`, which doesn't exist.

## Adding an environment

1. Create `tofu/<environment>/` and copy `ubuntu/` as a starting point
2. Adjust `versions.tf`, `variables.tf`, and `main.tf`
3. Add `mod <environment> "<environment>/justfile"` to `tofu/justfile`
4. Update the root `configure` recipe to also generate `tofu/<environment>/terraform.tfvars`

## State

State is stored locally (`.tfstate`) by default. Configure a remote backend in `versions.tf` for shared or production
environments.

## Structure

```
modules/vm/                     Reusable VM module
  main.tf                       Disk volume, cloud-init ISO, domain
  variables.tf
  outputs.tf
  versions.tf                   Provider declaration (required for modules)
  templates/
    user-data.tftpl             cloud-config: user, SSH keys, qemu-guest-agent
    meta-data.tftpl             instance-id and hostname
    network-config.tftpl        Netplan static IP config (used when static_ip is set)

ubuntu/                         Ubuntu 24.04 LTS environment
  versions.tf                   Provider requirements and connection
  main.tf                       Storage pool, NAT network (optional), VM module call
  variables.tf
  outputs.tf                    vm_ip, vm_name, ssh_command
  terraform.tfvars.example      Copy to terraform.tfvars and edit (or use `just configure`)

talos/                          Talos Linux cluster (3 control-plane + workload nodes)
  main.tf                       Pool, image factory + download, talos base volume
  nodes.tf                      Per-node libvirt domain, OS/data disks, cidata
  talos.tf                      Secrets, machine config, talos_machine, talos_cluster
  outputs.tf                    Writes output/{talosconfig,kubeconfig}
  image/schematic.yaml          Image factory schematic (qemu-guest-agent)
  machine-config/               Machine config patch templates
```

## Talos cluster (`talos/`)

Three nodes act as both control plane and worker (4 vCPU / 6 GiB RAM / 12 GiB OS + 24 GiB data by default — override
per node via the `nodes` map or globally via `node_*` vars).

### Image preparation

The Talos `nocloud` raw image is fetched from [image.factory.talos.dev](https://image.factory.talos.dev) based on a
schematic that includes `siderolabs/qemu-guest-agent`. Before upload the raw file is converted to a sparse qcow2 with
`qemu-img convert -f raw -O qcow2`; this reduces upload size from ~1 GiB to ~100 MiB. Each node's OS disk is a
thin copy-on-write overlay on top of the shared base volume.

### First boot

Machine config is delivered via a cidata ISO attached as a CD-ROM. The ISO's `meta_data` contains only
`instance-id`; no `local-hostname` is set there (setting it caused Talos to synthesise a duplicate `HostnameConfig`
document that conflicted with the one injected via `config_patches`).

### Hostname

Talos v1.12 rejects `machine.network.hostname` (v1alpha1) when a `HostnameConfig` document is also present. Hostname
is therefore set exclusively via a separate `HostnameConfig` patch (`machine-config/hostname.yaml.tftpl`), with
`auto: off` to prevent DHCP from overwriting it.

### IP discovery

Nodes get their primary address from **DHCP**. After a domain starts, `data.external.node_ip` polls
`virsh domifaddr --source agent` over SSH (up to 60 × 5 s) until an IPv4 appears on a physical NIC
(`eth*/enp*/ens*`), excluding the VIP. The QEMU guest agent (baked into the image schematic) is what makes virsh
aware of the guest-side addresses. The discovered IPs are passed to `talos_machine` and `talos_cluster`.

### VIP vs. bootstrap endpoint

The **VIP** (`cluster.vip`) is the long-term Kubernetes API endpoint — it is elected by Talos and only becomes
active once etcd is healthy. `talos_cluster` (which bootstraps etcd) must therefore connect to a real node IP, not
the VIP. `talos_cluster.node` and `talos_cluster.endpoint` are set to `local.first_control_plane`; the VIP appears
only in the machine config's `cluster_endpoint` so that kubeconfig and post-bootstrap tooling use it.

### Graceful OS upgrades

Uses `terraform-provider-talos` v0.12.0-alpha.4's new `talos_machine` resource. Bump `image.version` and run
`just tofu talos upgrade` (`-parallelism=1`) to roll upgrades sequentially and preserve etcd quorum.
`drain_on_upgrade` is off on the first apply (no `output/kubeconfig` yet) and switches on automatically for all
subsequent applies — see the `bootstrap_kubeconfig` local in `talos.tf`.
