# OpenTofu — VM Management

Manages VMs on the libvirt hypervisor via the [
`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs) provider.

## Usage

```bash
# Copy the example vars file and fill in your details
cp ubuntu-poc/terraform.tfvars.example ubuntu-poc/terraform.tfvars
$EDITOR ubuntu-poc/terraform.tfvars

# Provision
just ubuntu

# Destroy
cd ubuntu-poc && tofu destroy
```

From the project root: `just tofu ubuntu`

## Structure

```
modules/vm/                     Reusable VM module
  main.tf                       Base volume, overlay disk, cloud-init ISO, domain
  variables.tf
  outputs.tf
  templates/
    user-data.tftpl             cloud-config: user, SSH keys, qemu-guest-agent
    meta-data.tftpl             instance-id and hostname

ubuntu-poc/                     Ubuntu 24.04 LTS environment
  versions.tf                   Provider requirements (dmacvicar/libvirt ~> 0.8)
  main.tf                       Storage pool, NAT network, VM module call
  variables.tf
  outputs.tf                    vm_ip, ssh_command
  terraform.tfvars.example      Copy to terraform.tfvars and edit
```

## Module: modules/vm

Creates a single VM from a cloud image. Key variables:

| Variable              | Default | Description                  |
|-----------------------|---------|------------------------------|
| `name`                | —       | VM and resource name         |
| `hostname`            | —       | OS hostname (via cloud-init) |
| `memory_mb`           | `2048`  | RAM in MiB                   |
| `vcpu_count`          | `2`     | Virtual CPUs                 |
| `disk_size_gb`        | `20`    | Root disk in GiB             |
| `base_image_source`   | —       | Cloud image URL or path      |
| `ssh_authorized_keys` | —       | List of SSH public keys      |

The base image is downloaded once and used as a backing store; per-VM disks only store deltas.

## Adding an environment

1. Create a new directory under `tofu/`
2. Copy `ubuntu-poc/` as a starting point
3. Add a recipe to `tofu/justfile`
