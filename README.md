# libvirt-tofu-talos

Bootstrap a KVM hypervisor with Ansible, manage VMs with OpenTofu, and run a GitOps-managed Talos cluster with Flux CD
and Cilium.

## Overview

| Layer          | Tool                        | Directory   | Purpose                                            |
|----------------|-----------------------------|-------------|----------------------------------------------------|
| Task runner    | Just                        | `justfile`  | Unified entry point for all commands               |
| Host bootstrap | Ansible                     | `ansible/`  | Install libvirt, QEMU, AppArmor, bridge on Debian 13 |
| VM management  | OpenTofu + libvirt provider | `tofu/`     | Provision and manage virtual machines              |
| Kubernetes     | Talos Linux                 | `tofu/`     | 3-node HA cluster (control plane + worker)         |
| GitOps         | Flux CD                     | `k8s/`      | Reconcile cluster state from `k8s/`                |
| CNI            | Cilium                      | `k8s/`      | Networking with kube-proxy replacement             |

## Quick Start

### 1. Configure the hypervisor connection

```bash
just setup       # prompts for host, user, bridge, and Talos VIP; writes setup.env
just configure   # generates inventory.local.yaml and terraform.tfvars files
```

### 2. Bootstrap the hypervisor

```bash
just ansible bootstrap
```

### 3. Provision Talos VMs

```bash
just dev-kvm-talos-01 apply
```

### 4. Bootstrap the Talos cluster

```bash
just dev-talos apply
```

```bash
just dev-talos kubectl get nodes                              # wait for all three nodes Ready
just dev-talos kubectl -n kube-system get job cilium-install  # confirm Job succeeded
just dev-talos talosctl dashboard                             # live node metrics and logs
```

### 5. Bootstrap Flux CD

Requires the [Flux CLI](https://fluxcd.io/flux/installation/#install-the-flux-cli) and
the [GitHub CLI](https://cli.github.com/) authenticated with `repo` scope. The bootstrap recipe obtains the token
automatically via `gh auth token`.

```bash
gh auth login   # if not already authenticated
just k8s bootstrap $(gh api user -q ".login") libvirt-tofu-talos
```

If you get `401 Bad credentials`, your OAuth token may be stale — refresh it:

```bash
gh auth refresh -s repo
```

Flux installs itself into `flux-system`, commits its own manifests to `k8s/clusters/talos/flux-system/`, and begins
reconciling the cluster from `k8s/`. The first reconciliation upgrades Cilium to the version pinned in
`k8s/infrastructure/cilium/helmrelease.yaml` and hands off lifecycle management from the bootstrap Job to the
HelmRelease.

```bash
just k8s status     # watch Flux resources converge
```

## Ansible — Hypervisor Bootstrap

Two-phase bootstrap of a Debian 13 host. See [ansible/README.md](ansible/README.md) for roles, variables, security
model, and network topology.

1. **`prepare-host`** — runs once as root; creates the `ansible` service account with passwordless sudo
2. **`configure-libvirt`** — configures QEMU, libvirt, AppArmor, and a host bridge via NetworkManager

| Role           | Purpose                                                                  |
|----------------|--------------------------------------------------------------------------|
| `prepare_host` | Create ansible service account, sudoers, authorized keys                 |
| `common`       | Install system utilities                                                 |
| `libvirt_host` | QEMU + libvirt packages, AppArmor, polkit rule, qemu.conf, host bridge   |

QEMU processes run as `libvirt-qemu` (not root), confined by per-VM AppArmor profiles. The management user (`ansible`)
gets a polkit rule granting full libvirt API access without sudo.

## OpenTofu — VM Management

Environments live in `tofu/environments/<env>/`. Each hypervisor is a separate root module with its own statefile.
See [tofu/README.md](tofu/README.md) for the full workflow, per-node schematics, multi-hypervisor setup, Ubuntu VM
configuration, and command reference.

| Module              | Purpose                                                                     |
|---------------------|-----------------------------------------------------------------------------|
| `networks-catalog`  | Data-only — outputs the standard networks map (bridge, management, isolated)|
| `libvirt-networks`  | Thin emitter — creates `libvirt_network` resources from a networks map      |
| `libvirt-vm`        | Bare libvirt domain — disks + a `networks` map, no cloud-init               |
| `ubuntu-vm`         | Ubuntu 24.04 LTS — cloud-init, SSH keys, extra packages, per-NIC static IPs |
| `talos-vm`          | Talos OS overlay — qcow2 backing image, data disk, virsh IP discovery       |
| `talos-cluster`     | Cluster bootstrapping only — no libvirt; accepts pre-discovered IPs         |
| `github-runner-vm`  | GitHub Actions self-hosted runner on Ubuntu                                 |

All VM modules accept a single `networks` map (keyed by label, one NIC per entry) carrying attachment
info (`mode`, `name`/`bridge_name`, `mac_address`, `wait_for_ip`) and guest-OS hints (`static_ip`,
`gateway`, `dns_servers`). Environments feed that map from `networks-catalog` (see
`environments/dev/dc-ci/` for the reference pattern).

For the Talos cluster, apply order is mandatory: `kvm-talos-01` must complete before `talos` (the `talos` environment
reads `kvm-talos-01`'s statefile via `terraform_remote_state`).

## k8s — GitOps

Cluster state is managed with Flux CD reconciling from `k8s/`:

```
k8s/
  clusters/talos/       Flux entry point (--path passed to flux bootstrap)
  infrastructure/
    cilium/             Cilium HelmRepository + HelmRelease
```

To upgrade Cilium: bump `spec.chart.spec.version` in `k8s/infrastructure/cilium/helmrelease.yaml` and push.
Flux reconciles on the next interval (default 1 h) or immediately via `just k8s reconcile`.

## Talos + Cilium compatibility notes

Talos requires several non-default Cilium settings that are encoded in both the bootstrap
`cilium-values` ConfigMap (applied as a Talos inline manifest) and the Flux HelmRelease:

```YAML
# Point Cilium at Talos's local API server proxy instead of the cluster VIP.
# The proxy is always reachable on localhost:7445 regardless of VIP state.
k8sServiceHost: localhost
k8sServicePort: 7445

# Talos has an immutable root filesystem — /etc/sysctl.d/ does not exist.
sysctlfix:
  enabled: false

# Allow VLAN-tagged frames through the BPF host hook. The KVM bridge (br0 on a trunk port)
# forwards VLAN-tagged broadcast traffic from the Unifi switch (e.g. ARP requests) to VM eth0.
# Without this bypass, Cilium drops those frames and the upstream router cannot refresh its
# ARP entry for cluster IPs including the VIP.
bpf:
  vlanBypass: [ 0 ]

# Talos's container runtime (containerd) does not grant capabilities unless explicitly listed.
securityContext:
  capabilities:
    ciliumAgent: [ CHOWN, KILL, NET_ADMIN, NET_RAW, IPC_LOCK, SYS_ADMIN, SYS_RESOURCE, DAC_OVERRIDE, FOWNER, SETGID, SETUID ]
    cleanCiliumState: [ NET_ADMIN, SYS_ADMIN, SYS_RESOURCE ]
```

kube-proxy is disabled in the Talos machine config (`cluster.proxy.disabled: true`) so that
Cilium's kube-proxy replacement is the sole owner of service routing.

If Cilium pods are stuck in `Init:CrashLoopBackOff` after a fresh cluster, check which init
container is failing with `just dev-talos talosctl dashboard` or:

```bash
just dev-talos kubectl -n kube-system logs <cilium-pod> -c apply-sysctl-overwrites
just dev-talos kubectl -n kube-system logs <cilium-pod> -c clean-cilium-state
```

## VIP / DHCP conflict

The cluster VIP (`TALOS_VIP` in `setup.env`) must be **outside your DHCP pool**. If another VM on the
same bridge gets DHCP-assigned the same IP as the VIP, both will respond to ARP and every other
packet will be routed to the wrong host — producing intermittent "connection refused" errors when
connecting via the VIP.

Symptoms: `arping -c 3 -I br0 <VIP>` from the hypervisor returns replies from **two different MACs**.

Fix: either reserve the VIP in your DHCP server, or stop any VM that holds the conflicting IP.

## Rolling OS upgrades

Change `image.version` in `tofu/environments/dev/kvm-talos-01/terraform.tfvars`, then apply with parallelism 1 so
etcd quorum is preserved across the three control-plane nodes:

```bash
just dev-kvm-talos-01 apply   # re-downloads new image, recreates VMs
just dev-talos upgrade        # rolling restart with parallelism=1
```

## Requirements

- [just](https://just.systems/man/en/packages.html) — command runner (`brew install just` / `cargo install just`)
- Ansible >= 2.15 on the control machine
- OpenTofu >= 1.8
- `qemu-img` — for converting Talos images to qcow2 before upload (`brew install qemu` / `apt install qemu-utils`)
- `jq` — for node IP discovery (`brew install jq` / `apt install jq`)
- [Flux CLI](https://fluxcd.io/flux/installation/#install-the-flux-cli) >= 2.0 (`brew install fluxcd/tap/flux`)
- [GitHub CLI](https://cli.github.com/) (`brew install gh`) — used to obtain a GitHub token for `just k8s bootstrap`
- Debian 13 host with SSH access
- SSH key pair

Run `just install-deps` to install all of the above on macOS (Homebrew) or Debian/Ubuntu.

### Dev Container

A [dev container](.devcontainer/devcontainer.json) is provided with all tools pre-installed (OpenTofu, Ansible,
`just`, `talosctl`, Flux CLI, `kubectl`, `k9s`, `yq`, `kubeconform`, `kubecolor`, and krew plugins). Open the
repository in VS Code or any IDE with dev container support and choose **Reopen in Container**.

Your SSH agent is forwarded into the container so Ansible can reach the hypervisor without copying keys.

## Project Structure

```
ansible/
  roles/
    prepare_host/         Create ansible service account (phase 1)
    common/               System utilities
    libvirt_host/         QEMU, libvirt, AppArmor, host bridge (phase 2)
  prepare-host.yaml       Phase 1 playbook
  site.yaml               Phase 2 playbook (configure-libvirt)
  inventory.yaml          envsubst template — generate with `just configure`

tofu/
  modules/
    networks-catalog/     Standard networks map (data-only)
    libvirt-networks/     libvirt_network resources from a networks map
    libvirt-vm/           Bare libvirt domain
    ubuntu-vm/            Ubuntu 24.04 LTS + cloud-init
    talos-vm/             Talos OS overlay + virsh IP discovery
    talos-cluster/        Talos bootstrapping (no libvirt)
    github-runner-vm/     GitHub Actions self-hosted runner
  environments/dev/
    dc-ci/                Ubuntu VMs (catalog pattern — recommended)
    kvm-01/               Ubuntu VMs + GitHub runners (legacy local-network pattern)
    kvm-talos-01/         Talos VM nodes (pool, per-schematic images, VMs)
    talos/                Talos cluster bootstrapping
  talos/                  Legacy standalone Talos root module (existing state)

k8s/
  clusters/talos/         Flux entry point
  infrastructure/
    cilium/               Cilium CNI — HelmRepository + HelmRelease
```
