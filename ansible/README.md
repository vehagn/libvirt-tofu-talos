# Ansible — Hypervisor Bootstrap

One-time bootstrap of a Debian 13 host with libvirt, QEMU, and bridge networking.

## Usage

```bash
just configure          # generate inventory.local.yaml from setup.env
just ansible bootstrap  # apply (add --check for a dry run)
```

## What it does

Applies two roles to the `hypervisors` group:

### `common`

Installs system utilities. Add packages to `roles/common/defaults/main.yaml`.

### `libvirt_host`

1. Installs QEMU and libvirt packages
2. Enables and starts `libvirtd`
3. Adds the target user to the `libvirt` group
4. Configures QEMU to run VMs as root (required for bridge access)
5. Configures a host bridge (`br0`) via NetworkManager so VMs share the host subnet

## Configuration

Override defaults per host or group in `inventory.local.yaml`.

| Variable                   | Default        | Description                         |
|----------------------------|----------------|-------------------------------------|
| `libvirt_user`             | `ansible_user` | User added to the `libvirt` group   |
| `libvirt_service`          | `libvirtd`     | Service name                        |
| `libvirt_packages`         | see defaults   | Packages to install                 |
| `libvirt_bridge_name`      | `br0`          | Bridge interface name               |
| `libvirt_bridge_configure` | `true`         | Set to `false` to skip bridge setup |

## Structure

```
site.yaml                        Main playbook
inventory.yaml                   envsubst template — generate with `just configure`
roles/
  common/                        System utilities
  libvirt_host/
    defaults/main.yaml           Tunable defaults
    tasks/main.yaml              Install, configure, bridge setup
    handlers/main.yaml           Reset SSH connection and restart services
```
