# Ansible — LLM Reference

## Two-phase setup

`prepare-host.yaml` runs first as root to create the ansible service account. `site.yaml` (the `configure-libvirt` recipe) then runs as that account to configure libvirt. These are separate because the ansible user doesn't exist yet during phase 1.

## Role: prepare_host

Minimal: user, sudoers, authorized_key. No libvirt, no packages. If you add SSH key logic, use `ansible.posix.authorized_key` (not shell/copy) — it is idempotent per-key.

## Role: libvirt_host — key design decisions

### Two distinct users

`libvirt_user` (default: `ansible_user`) — the human/service account that runs `virsh`. Gets added to `libvirt` and `kvm` groups; gets the polkit rule.

`libvirt_qemu_user` (default: `libvirt-qemu`) — the OS user QEMU *processes* run as. Set in `/etc/libvirt/qemu.conf`. Created by the `libvirt-daemon-system` package.

Do not conflate them. The polkit rule is for the management user; `dynamic_ownership` is for the QEMU process user.

### qemu.conf integer vs string

`dynamic_ownership`, `memory_backing_dir`, and similar numeric settings in qemu.conf must be **unquoted integers**. The lineinfile loop uses `'{{ item.key }} = "{{ item.value }}"'` (adds quotes) — correct for user/group/security_driver, wrong for integers. `dynamic_ownership` has its own task using `{{ libvirt_qemu_dynamic_ownership | int }}` (no surrounding quotes in the format string).

If you add more integer settings, follow this pattern: separate task, no quotes in the `line:` value.

### AppArmor storage pool abstraction

`/etc/apparmor.d/local/abstractions/libvirt-qemu` is included by libvirt's QEMU profile template on both Debian and Ubuntu. Writing to this file is the canonical way to extend AppArmor permissions for QEMU domains.

The default pool path `/var/lib/libvirt/images` is already covered by the upstream profile. The explicit write here makes it overridable via `libvirt_pool_path` and documents the mechanism for non-default pool paths (e.g. custom directories created by OpenTofu).

After editing this file the `Reload AppArmor` handler runs; then `Restart libvirtd` so libvirtd picks up the new profile. Order matters — both notifies must fire.

### polkit rule

Without the polkit rule, the management user must use `sudo virsh`. The rule file is named after `libvirt_user` so multiple users can coexist. If you rename or remove a user, delete the corresponding `/etc/polkit-1/rules.d/50-libvirt-<user>.rules` manually.

## Inventory template

`inventory.yaml` uses `envsubst` with explicit variable names (`'${HYPERVISOR_HOST} ${HYPERVISOR_USER}'`) so shell variables in Ansible's Jinja2 expressions (e.g. `{{ ansible_user }}`) are not clobbered. Always specify the variable list to `envsubst`.

## Handlers

`Reload AppArmor` uses `state: reloaded` (SIGHUP to the service), which re-parses all profiles in `/etc/apparmor.d/` including the local overrides. `Restart polkit` is required after writing new rules — polkit auto-watches the directory but a restart is the safe path. `Reset connection` is a meta handler (not a service) and must stay first in the handlers file.

## Adding a new role

1. Create `roles/<name>/defaults/main.yaml` and `tasks/main.yaml`
2. If the role is a one-time setup step (like `prepare_host`), add a dedicated playbook
3. If it runs on every managed host, add it to `site.yaml`
4. Add a recipe to `justfile`

## Files to never commit

- `inventory.local.yaml` — contains real IP and username, gitignored
- `setup.env` — contains credentials, gitignored at repo root
