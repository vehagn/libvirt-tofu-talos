# OpenTofu — VM Management

Manages VMs on the libvirt hypervisor via the `dmacvicar/libvirt` provider.

## Structure

```
modules/vm/       Reusable module: single cloud-init VM on libvirt
ubuntu/       Ubuntu 24.04 LTS proof-of-concept environment
```

## Running an environment

From the project root:
```bash
just configure                  # generate terraform.tfvars from setup.env
just tofu ubuntu init           # first time only
just tofu ubuntu apply
```

Or directly from the environment directory:
```bash
cd tofu/ubuntu
just configure   # generate terraform.tfvars
just init        # first time only
just plan
just apply
just destroy
```

## Module: modules/vm

Creates a single VM from a cloud image with cloud-init first-boot configuration.

**Resources created per VM:**
- `libvirt_volume` (base) — cloud image downloaded once, used as a backing store
- `libvirt_volume` (disk) — per-VM overlay disk backed by the base image
- `libvirt_cloudinit_disk` — ISO with user-data and meta-data
- `libvirt_domain` — the VM itself

**Key variables:** `name`, `hostname`, `memory_mb`, `vcpu_count`, `disk_size_gb`,
`pool_name`, `network_name`, `base_image_source`, `ssh_authorized_keys`

**Output:** `ip_address`, `name`

## Provider connection

The `libvirt_uri` variable controls the hypervisor connection:
- Remote via SSH: `qemu+ssh://user@host/system`
- Local (testing): `qemu:///system`

## Provider conventions

Every module (not just root modules) must declare its provider dependencies in a `versions.tf` with a `required_providers` block. OpenTofu does not inherit provider source from the root — omitting it causes OpenTofu to guess `hashicorp/<name>`, which fails for third-party providers like `dmacvicar/libvirt`.

## Adding an environment

1. Create `tofu/<environment>/`
2. Copy the structure from `ubuntu/` as a starting point
3. Adjust `versions.tf`, `variables.tf`, and `main.tf` as needed
4. Add a `configure` recipe to `tofu/<environment>/justfile` that uses `envsubst` on the tfvars example
5. Wire the new environment into `tofu/justfile` as a `mod` and add it to the root `configure` task

## State

State is stored locally (`.tfstate`) by default. Configure a remote backend in
`versions.tf` for shared or production environments.
