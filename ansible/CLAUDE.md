# Ansible — Hypervisor Bootstrap

One-time bootstrap of a Debian 13 host with libvirt, QEMU, and required dependencies.

## Running

```bash
# Copy and edit the inventory for your environment
cp inventory.yaml inventory.local.yaml
$EDITOR inventory.local.yaml

# Dry run (no changes)
just bootstrap --check

# Apply
just bootstrap
```

From the project root: `just ansible bootstrap` / `just ansible bootstrap --check`

## Structure

```
site.yaml                  Main playbook — applies libvirt_host to the hypervisors group
inventory.yaml             Example inventory (gitignored when named inventory.local.yaml)
roles/libvirt_host/
  defaults/main.yaml       Package list and tuneable defaults
  tasks/main.yaml          Install packages, enable service, add user to group
  handlers/main.yaml       Reset SSH connection after group membership change
```

## Role: libvirt_host

**Installs:** `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`, `bridge-utils`,
`virtinst`, `python3-libvirt`, `cpu-checker`

**Configures:**

- Enables and starts `libvirtd`
- Adds `libvirt_user` (default: `ansible_user`) to the `libvirt` group

**Defaults** can be overridden per host or group in the inventory. See
`roles/libvirt_host/defaults/main.yaml`.
