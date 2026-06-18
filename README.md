# libvirt-tofu-talos

Bootstrap a KVM hypervisor with Ansible, manage VMs with OpenTofu, and run a GitOps-managed Talos cluster with Flux CD
and Cilium.

## Overview

| Layer          | Tool                        | Purpose                                          |
|----------------|-----------------------------|--------------------------------------------------|
| Host bootstrap | Ansible                     | Install libvirt, QEMU, dependencies on Debian 13 |
| VM management  | OpenTofu + libvirt provider | Provision and manage virtual machines            |
| GitOps         | Flux CD                     | Reconcile cluster state from `k8s/`              |
| CNI            | Cilium                      | Networking with kube-proxy replacement           |

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

### 3. Provision an Ubuntu VM (optional PoC)

```bash
just tofu ubuntu apply
```

### 4. Spin up a Talos cluster

```bash
just tofu talos init
just tofu talos apply
```

Talos applies two inline manifests during bootstrap: a `cilium-values` ConfigMap containing the cluster VIP and IPAM
settings, and a `cilium-install` Job that runs `cilium-cli` to install Cilium before any workload pods schedule. The
cluster will not reach `Ready` until this Job completes (~2 minutes).

```bash
just tofu talos kubectl get nodes                              # wait for all three nodes Ready
just tofu talos kubectl -n kube-system get job cilium-install  # confirm Job succeeded
just tofu talos talosctl dashboard                             # live node metrics and logs
```

### 5. Bootstrap Flux CD

Requires the [Flux CLI](https://fluxcd.io/flux/installation/#install-the-flux-cli) and
the [GitHub CLI](https://cli.github.com/) authenticated (`gh auth login`). The bootstrap recipe obtains the token
automatically via `gh auth token`.

```bash
gh auth login   # once, if not already authenticated
just flux bootstrap vehagn libvirt-tofu-talos
```

Flux installs itself into `flux-system`, commits its own manifests to `k8s/clusters/talos/flux-system/`, and begins
reconciling the cluster from `k8s/`. The first reconciliation upgrades Cilium to the version pinned in
`k8s/infrastructure/cilium/helmrelease.yaml` and hands off lifecycle management from the bootstrap Job to the
HelmRelease.

```bash
just flux status     # watch Flux resources converge
```

## Updating Cilium

Bump `spec.chart.spec.version` in `k8s/infrastructure/cilium/helmrelease.yaml` and push.
Flux reconciles on the next interval (default 1 h) or immediately via `just flux reconcile`.

## Talos + Cilium compatibility notes

Talos requires two non-default Cilium settings that are encoded in both the bootstrap
`cilium-values` ConfigMap (applied as a Talos inline manifest) and the Flux HelmRelease:

| Setting                                         | Value                                  | Reason                                                                                                           |
|-------------------------------------------------|----------------------------------------|------------------------------------------------------------------------------------------------------------------|
| `sysctlfix.enabled`                             | `false`                                | Talos has an immutable root filesystem — `/etc/sysctl.d/` does not exist                                         |
| `securityContext.capabilities.ciliumAgent`      | explicit list                          | Talos's container runtime (containerd) requires capabilities to be enumerated; it will not grant them implicitly |
| `securityContext.capabilities.cleanCiliumState` | `[NET_ADMIN, SYS_ADMIN, SYS_RESOURCE]` | Same reason as above                                                                                             |
| `bpf.vlanBypass`                                | `[0]`                                  | The KVM `br0` bridge (trunk port) forwards VLAN-tagged Unifi ARP broadcasts to VM `eth0`; Cilium drops those frames by default, preventing the upstream router from refreshing its ARP entry for cluster IPs |

kube-proxy is disabled in the Talos machine config (`cluster.proxy.disabled: true`) so that
Cilium's kube-proxy replacement is the sole owner of service routing.

If Cilium pods are stuck in `Init:CrashLoopBackOff` after a fresh cluster, check which init
container is failing with `just tofu talos talosctl dashboard` or:

```bash
just tofu talos kubectl -n kube-system logs <cilium-pod> -c apply-sysctl-overwrites
just tofu talos kubectl -n kube-system logs <cilium-pod> -c clean-cilium-state
```

## VIP / DHCP conflict

The cluster VIP (`TALOS_VIP` in `setup.env`) must be **outside your DHCP pool**. If another VM on the
same bridge gets DHCP-assigned the same IP as the VIP, both will respond to ARP and every other
packet will be routed to the wrong host — producing intermittent "connection refused" errors when
connecting via the VIP.

Symptoms: `arping -c 3 -I br0 <VIP>` from the hypervisor returns replies from **two different MACs**.

Fix: either reserve the VIP in your DHCP server, or stop any VM that holds the conflicting IP.
`just tofu ubuntu destroy` tears down the Ubuntu PoC if it happens to own the address.

## Rolling OS upgrades

Change `image.version` in `tofu/talos/terraform.tfvars`, then apply with parallelism 1 so etcd quorum is preserved
across the three control-plane nodes:

```bash
just tofu talos upgrade
```

## Requirements

- [just](https://just.systems/man/en/packages.html) — command runner (`brew install just` / `cargo install just`)
- Ansible >= 2.15 on the control machine
- OpenTofu >= 1.8
- `qemu-img` — for converting Talos images to qcow2 before upload (`brew install qemu` / `apt install qemu-utils`)
- `jq` — for node IP discovery (`brew install jq` / `apt install jq`)
- [Flux CLI](https://fluxcd.io/flux/installation/#install-the-flux-cli) >= 2.0 (`brew install fluxcd/tap/flux`)
- [GitHub CLI](https://cli.github.com/) (`brew install gh`) — used to obtain a GitHub token for `just flux bootstrap`
- Debian 13 host with SSH access
- SSH key pair

Run `just install-deps` to install all of the above on macOS (Homebrew) or Debian/Ubuntu.

## Project Structure

```
ansible/
  roles/libvirt_host/   Install and configure libvirt + QEMU on the host
  site.yaml              Main playbook
  inventory.yaml         Example inventory (copy to inventory.local.yaml)

tofu/
  modules/vm/           Reusable libvirt VM module (cloud-init, disk, network)
  ubuntu/               Ubuntu 26.04 LTS proof-of-concept environment
  talos/                Three-node Talos Linux cluster (control plane + workload)

k8s/
  clusters/talos/       Flux entry point — bootstrapped by flux bootstrap --path=k8s/clusters/talos
  infrastructure/       Cluster-wide infrastructure managed by Flux
    cilium/             Cilium CNI — HelmRepository + HelmRelease

flux/
  justfile              bootstrap / status / reconcile helpers
```
