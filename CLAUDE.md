# libvirt-tofu-talos

Three-layer infrastructure stack: Ansible bootstraps the KVM hypervisor, OpenTofu provisions VMs, Flux CD manages the
Kubernetes cluster.

## Architecture

| Layer          | Tool               | Directory  | Purpose                                              |
|----------------|--------------------|------------|------------------------------------------------------|
| Task runner    | Just               | `justfile` | Aggregates sub-justfiles; single entry point         |
| Host bootstrap | Ansible            | `ansible/` | Install libvirt, QEMU, AppArmor, bridge on Debian 13 |
| VM management  | OpenTofu + libvirt | `tofu/`    | Provision VMs; modules for Ubuntu, Talos, runners    |
| Kubernetes     | Talos Linux        | `tofu/`    | 3-node HA cluster via `talos-vm` + `talos-cluster`   |
| GitOps         | Flux CD            | `k8s/`     | Reconcile cluster state from `k8s/`                  |
| CNI            | Cilium             | `k8s/`     | kube-proxy replacement; Talos-specific settings      |

## Workflow

1. `just setup` — creates `setup.env` (host, user, bridge, VIP)
2. `just configure` — generates `ansible/inventory.local.yaml` and `tofu/environments/dev/*/terraform.tfvars`
3. `just ansible bootstrap` — two-phase: creates ansible user, then configures libvirt + bridge
4. `just dev-kvm-talos-01 apply` — provisions Talos VMs (pool, per-schematic images, domains)
5. `just dev-talos apply` — bootstraps Talos cluster (machine config, etcd, kubeconfig)
6. `just k8s bootstrap <gh-user> <repo>` — installs Flux; begins GitOps reconciliation

For Ubuntu VMs: `just dev apply`

## Ansible conventions

See [ansible/CLAUDE.md](ansible/CLAUDE.md) for full LLM reference.

- Two-phase: `prepare-host.yaml` (as root) then `site.yaml` (as ansible user) — separate because the ansible user does
  not exist during phase 1
- Roles are self-contained under `ansible/roles/<role>/` with `defaults/`, `tasks/`, `handlers/`
- `inventory.yaml` is an envsubst template; real inventory is `inventory.local.yaml` (gitignored)
- Two distinct users: `libvirt_user` (management account, gets polkit rule) vs `libvirt_qemu_user` (QEMU process user
  set in qemu.conf) — do not conflate
- Integer qemu.conf settings (`dynamic_ownership`) must be unquoted integers — separate task from the string settings
  loop

## OpenTofu conventions

See [tofu/CLAUDE.md](tofu/CLAUDE.md) for full LLM reference.

- All config uses `.tofu` extension (not `.tf`); templates use `.tftpl`
- Module hierarchy: `libvirt-vm` ← `ubuntu-vm` (← `github-runner-vm`) / `talos-vm`; `talos-cluster` is independent (no
  libvirt)
- Networking: `networks-catalog` (shared data) → `libvirt-networks` (creates `libvirt_network` resources) → VM modules
  consume the same `networks` map shape (`mode`, `name`/`bridge_name`, `static_ip`, `gateway`, `dns_servers`,
  `mac_address`, `wait_for_ip`)
- New environments follow `dc-ci` (catalog pattern); `kvm-01` is the legacy local-network pattern kept for existing
  state
- Every module declares `required_providers` in its own `versions.tofu` — OpenTofu does not inherit provider source from
  the root
- `terraform.tfvars` is gitignored; always keep `terraform.tfvars.example` up to date
- Environments live in `tofu/environments/<env>/<hypervisor>/` — one statefile per hypervisor
- Apply order for Talos: `kvm-talos-xx apply` first, `talos apply` second (reads kvm-talos-xx statefile via
  `terraform_remote_state`)

## k8s / Flux conventions

- `k8s/clusters/talos/` is the Flux entry point (`--path` passed to `flux bootstrap`)
- `k8s/infrastructure/` holds cluster-wide Flux-managed resources
- Cilium settings must be kept in sync between the Talos inline manifest (`cilium-values` ConfigMap) and
  `k8s/infrastructure/cilium/helmrelease.yaml` — they are applied at different lifecycle phases
- Never commit kubeconfig or talosconfig — both are written to `tofu/environments/dev/talos/output/` (gitignored)

## Secrets — never commit

- `setup.env` — host, user, VIP
- `ansible/inventory.local.yaml` — real IP and username
- `tofu/environments/*/terraform.tfvars` — libvirt URI, node config
- `tofu/environments/dev/talos/output/` — kubeconfig, talosconfig

## Roadmap

- [x] Ubuntu 24.04 LTS PoC (`tofu/ubuntu/`) — superseded by `tofu/environments/dev/kvm-01/`
- [x] Talos Linux cluster (`tofu/talos/`) — legacy standalone module, still in use for existing state
- [x] Modular Talos cluster (`tofu/environments/dev/`) — `kvm-talos-01` + `talos` environments
- [x] Dev environment (`tofu/environments/dev/kvm-01/`) — Ubuntu VMs, GitHub runners
- [x] Cilium CNI + Flux CD GitOps (`k8s/`)
