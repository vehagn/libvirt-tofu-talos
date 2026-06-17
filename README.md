# libvirt-tofu-talos

Bootstrap a KVM hypervisor with Ansible, then manage VMs with OpenTofu and libvirt.

## Overview

| Layer          | Tool                        | Purpose                                          |
|----------------|-----------------------------|--------------------------------------------------|
| Host bootstrap | Ansible                     | Install libvirt, QEMU, dependencies on Debian 13 |
| VM management  | OpenTofu + libvirt provider | Provision and manage virtual machines            |

## Quick Start

### 1. Bootstrap the hypervisor

```bash
cp ansible/inventory.yaml ansible/inventory.local.yaml
# Edit inventory.local.yaml with your host IP and user
just ansible bootstrap
```

### 2. Provision an Ubuntu VM

```bash
cp tofu/ubuntu-poc/terraform.tfvars.example tofu/ubuntu-poc/terraform.tfvars
# Edit terraform.tfvars with your libvirt URI and SSH public key
just tofu ubuntu
```

## Requirements

- [just](https://just.systems/man/en/packages.html) — command runner (`brew install just` / `cargo install just`)
- Ansible >= 2.15 on the control machine
- OpenTofu >= 1.8
- Debian 13 host with SSH access
- SSH key pair

## Project Structure

```
ansible/
  roles/libvirt_host/   Install and configure libvirt + QEMU on the host
  site.yaml              Main playbook
  inventory.yaml         Example inventory (copy to inventory.local.yaml)

tofu/
  modules/vm/           Reusable libvirt VM module (cloud-init, disk, network)
  ubuntu-poc/           Ubuntu 24.04 LTS proof-of-concept environment
```
