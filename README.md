# libvirt-tofu-talos

Bootstrap a KVM hypervisor with Ansible, then manage VMs with OpenTofu and libvirt.

## Overview

| Layer          | Tool                        | Purpose                                          |
|----------------|-----------------------------|--------------------------------------------------|
| Host bootstrap | Ansible                     | Install libvirt, QEMU, dependencies on Debian 13 |
| VM management  | OpenTofu + libvirt provider | Provision and manage virtual machines            |

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
just tofu talos kubectl get nodes
```

## Requirements

- [just](https://just.systems/man/en/packages.html) — command runner (`brew install just` / `cargo install just`)
- Ansible >= 2.15 on the control machine
- OpenTofu >= 1.8
- `qemu-img` — for converting Talos images to qcow2 before upload (`brew install qemu` / `apt install qemu-utils`)
- `jq` — for node IP discovery (`brew install jq` / `apt install jq`)
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
  ubuntu/               Ubuntu 24.04 LTS proof-of-concept environment
  talos/                Three-node Talos Linux cluster (control plane + workload)
```
