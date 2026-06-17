# libvirt-tofu-talos

Two-layer infrastructure stack: Ansible bootstraps the KVM hypervisor, OpenTofu manages VMs.

## Architecture

| Layer          | Tool     | Directory  | Purpose                                           |
|----------------|----------|------------|---------------------------------------------------|
| Host bootstrap | Ansible  | `ansible/` | Install libvirt, QEMU, dependencies on Debian 13  |
| VM management  | OpenTofu | `tofu/`    | Provision and manage VMs via the libvirt provider |

## Workflow

1. Edit `ansible/inventory.local.yaml` (copied from `ansible/inventory.yaml`) with your hypervisor's address
2. Bootstrap the host: `just ansible bootstrap`
3. Copy and edit `tofu/ubuntu-poc/terraform.tfvars.example` → `terraform.tfvars`
4. Provision the VM: `just tofu ubuntu`

## Conventions

- **Ansible roles** are self-contained under `ansible/roles/<role>/` with `defaults/`, `tasks/`, and `handlers/`
- **OpenTofu modules** live in `tofu/modules/`; environments (root modules) live in `tofu/<environment>/`
- `terraform.tfvars` is gitignored — always keep `terraform.tfvars.example` up to date
- Secrets (SSH keys, passwords) are never committed; pass via vars or env vars

## Roadmap

- [x] Ubuntu 24.04 LTS PoC (`tofu/ubuntu-poc/`)
- [ ] Talos Linux cluster (`tofu/talos/`)

## Prerequisites

- just (`brew install just` / `cargo install just`)
- Ansible >= 2.15
- OpenTofu >= 1.8
- SSH access to a Debian 13 host
