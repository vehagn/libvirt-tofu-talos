set shell := ["bash", "-c"]
set dotenv-filename := "setup.env"
set dotenv-load

mod ansible "ansible/justfile"
mod tofu "tofu/justfile"

# List available recipes
default:
    @just --list

# Interactively create setup.env with hypervisor host and user
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    read -rp "Hypervisor host (IP or hostname): " host
    read -rp "Hypervisor user [root]: " user
    user="${user:-root}"
    read -rp "VM bridge interface [br0]: " bridge
    bridge="${bridge:-br0}"
    read -rp "VM console password [ubuntu]: " password
    password="${password:-ubuntu}"
    printf 'HYPERVISOR_HOST=%s\nHYPERVISOR_USER=%s\nVM_BRIDGE_INTERFACE=%s\nVM_USER_PASSWORD=%s\n' \
        "$host" "$user" "$bridge" "$password" > setup.env
    echo "Created setup.env — run 'just configure' to generate config files"

# Generate ansible/inventory.local.yaml and tofu/ubuntu/terraform.tfvars from setup.env
configure:
    #!/usr/bin/env bash
    set -euo pipefail
    envsubst '${HYPERVISOR_HOST} ${HYPERVISOR_USER}' < ansible/inventory.yaml > ansible/inventory.local.yaml
    echo "Created ansible/inventory.local.yaml"
    ssh_keys=$(ssh-add -L 2>/dev/null || true)
    if [[ -z "$ssh_keys" ]]; then
        for f in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
            [[ -f "$f" ]] && ssh_keys+="$(cat "$f")"$'\n'
        done
        ssh_keys="${ssh_keys%$'\n'}"
    fi
    if [[ -z "$ssh_keys" ]]; then
        echo "Error: no SSH keys found — load keys with ssh-add, or place a public key in ~/.ssh/*.pub" >&2
        exit 1
    fi
    keys_hcl=""
    while IFS= read -r key; do
        [[ -n "$key" ]] && keys_hcl+="  \"${key}\","$'\n'
    done <<< "$ssh_keys"
    bridge="${VM_BRIDGE_INTERFACE:-br0}"
    {
        printf 'libvirt_uri = "qemu+ssh://%s@%s/system"\n\n' "$HYPERVISOR_USER" "$HYPERVISOR_HOST"
        printf 'ssh_authorized_keys = [\n%s]\n\n' "$keys_hcl"
        if [[ "$bridge" == "null" ]]; then
            printf 'vm_bridge_interface = null  # private NAT network\n\n'
        else
            printf 'vm_bridge_interface = "%s"\n\n' "$bridge"
        fi
        if [[ -n "${VM_USER_PASSWORD:-}" ]]; then
            printf 'vm_user_password = "%s"\n\n' "$VM_USER_PASSWORD"
        fi
        printf '# Optional overrides (defaults shown)\n'
        printf '# vm_name         = "ubuntu"\n'
        printf '# vm_memory_mb    = 2048\n'
        printf '# vm_vcpu_count   = 2\n'
        printf '# vm_disk_size_gb = 20\n'
    } > tofu/ubuntu/terraform.tfvars
    echo "Created tofu/ubuntu/terraform.tfvars ($(echo "$ssh_keys" | grep -c .) SSH key(s))"

# Install ansible, opentofu, and envsubst (macOS via Homebrew, Debian/Ubuntu via apt)
install-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
        Darwin)
            brew install ansible opentofu gettext
            ;;
        Linux)
            if [[ ! -f /etc/debian_version ]]; then
                echo "Unsupported Linux distro — install ansible and opentofu manually." >&2
                exit 1
            fi
            # Ansible
            sudo apt-get update -qq
            sudo apt-get install -y ansible gettext-base

            # OpenTofu via official apt repo
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://get.opentofu.org/opentofu.gpg \
                | sudo tee /etc/apt/keyrings/opentofu.gpg > /dev/null
            curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey \
                | sudo gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg > /dev/null
            printf 'deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main\n' \
                | sudo tee /etc/apt/sources.list.d/opentofu.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y opentofu
            ;;
        *)
            echo "Unsupported OS: $(uname -s)" >&2
            exit 1
            ;;
    esac
