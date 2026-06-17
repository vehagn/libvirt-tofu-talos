# Ansible — Hypervisor Bootstrap

One-time bootstrap of a Debian 13 host with libvirt, QEMU, and required dependencies.

## Usage

```bash
# Copy the example inventory and fill in your host details
cp inventory.yaml inventory.local.yaml
$EDITOR inventory.local.yaml

# Dry run
just bootstrap --check

# Apply
just bootstrap
```

From the project root: `just ansible bootstrap`

## What it does

Applies the `libvirt_host` role, which:

1. Installs `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`, `bridge-utils`, `virtinst`, `python3-libvirt`,
   `cpu-checker`
2. Enables and starts `libvirtd`
3. Adds the target user to the `libvirt` group

## Configuration

| Variable           | Default        | Description                       |
|--------------------|----------------|-----------------------------------|
| `libvirt_user`     | `ansible_user` | User added to the `libvirt` group |
| `libvirt_service`  | `libvirtd`     | Service to enable                 |
| `libvirt_packages` | see defaults   | Package list to install           |

Override defaults per host or group in `inventory.local.yaml`, or edit `roles/libvirt_host/defaults/main.yaml`.

## Structure

```
site.yaml                        Main playbook
inventory.yaml                   Example inventory (copy to inventory.local.yaml)
roles/libvirt_host/
  defaults/main.yaml             Tunable defaults
  tasks/main.yaml                Install, configure, group membership
  handlers/main.yaml             Reset SSH connection after group change
```
