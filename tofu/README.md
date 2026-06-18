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
```
