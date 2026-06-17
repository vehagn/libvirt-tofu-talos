# OpenTofu — VM Management

Manages VMs on the libvirt hypervisor via the `dmacvicar/libvirt` provider.

## Structure

```
modules/vm/       Reusable module: single cloud-init VM on libvirt
ubuntu-poc/       Ubuntu 24.04 LTS proof-of-concept environment
```

## Running an environment

From the project root:
```bash
just tofu ubuntu          # init + apply
```

Or directly from the environment directory:
```bash
cd tofu/ubuntu-poc
tofu init                 # first time only
tofu plan
tofu apply
tofu destroy
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

## Adding an environment

1. Create `tofu/<environment>/`
2. Copy the structure from `ubuntu-poc/` as a starting point
3. Adjust `versions.tf`, `variables.tf`, and `main.tf` as needed

## State

State is stored locally (`.tfstate`) by default. Configure a remote backend in
`versions.tf` for shared or production environments.
