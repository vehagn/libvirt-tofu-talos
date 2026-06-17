# libvirt-tofu-talos

Two-layer infrastructure stack: Ansible bootstraps the KVM hypervisor, OpenTofu manages VMs.

## Architecture

| Layer          | Tool     | Directory  | Purpose                                           |
|----------------|----------|------------|---------------------------------------------------|
| Host bootstrap | Ansible  | `ansible/` | Install libvirt, QEMU, dependencies on Debian 13  |
| VM management  | OpenTofu | `tofu/`    | Provision and manage VMs via the libvirt provider |

## Workflow

1. Run `just setup` to create `setup.env` with your hypervisor host and user
2. Run `just configure` to generate `ansible/inventory.local.yaml` and `tofu/ubuntu/terraform.tfvars` (SSH keys fetched from agent or `~/.ssh/*.pub`)
3. Bootstrap the host: `just ansible bootstrap`
5. Provision the VM: `just tofu ubuntu apply`

## Conventions

- **Ansible roles** are self-contained under `ansible/roles/<role>/` with `defaults/`, `tasks/`, and `handlers/`
- **OpenTofu modules** live in `tofu/modules/`; environments (root modules) live in `tofu/<environment>/`
- `terraform.tfvars` is gitignored — always keep `terraform.tfvars.example` up to date
- Secrets (SSH keys, passwords) are never committed; pass via vars or env vars

## Roadmap

- [x] Ubuntu 24.04 LTS PoC (`tofu/ubuntu/`)
- [ ] Talos Linux cluster (`tofu/talos/`)

## Prerequisites

- just (`brew install just` / `cargo install just`)
- Ansible >= 2.15
- OpenTofu >= 1.8
- SSH access to a Debian 13 host
