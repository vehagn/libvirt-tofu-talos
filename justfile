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
    read -rp "Talos cluster VIP [192.168.1.99]: " vip
    vip="${vip:-192.168.1.99}"
    {
        printf 'HYPERVISOR_HOST=%s\n' "$host"
        printf 'HYPERVISOR_USER=%s\n' "$user"
        printf 'VM_BRIDGE_INTERFACE=%s\n' "$bridge"
        printf 'VM_USER_PASSWORD=%s\n' "$password"
        printf '\n'
        printf '# Talos cluster (used by tofu/talos). Nodes use DHCP; VIP is the cluster endpoint.\n'
        printf 'TALOS_VIP=%s\n' "$vip"
    } > setup.env
    echo "Created setup.env — run 'just configure' to generate config files"

# Generate ansible/inventory.local.yaml and tofu/*/terraform.tfvars from setup.env
configure:
    #!/usr/bin/env bash
    set -euo pipefail
    envsubst '${HYPERVISOR_HOST} ${HYPERVISOR_USER}' < ansible/inventory.yaml > ansible/inventory.local.yaml
    echo "Created ansible/inventory.local.yaml"
    just tofu ubuntu configure
    just tofu talos configure

# Install ansible, opentofu, qemu-img, jq, and envsubst (macOS via Homebrew, Debian/Ubuntu via apt)
install-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
        Darwin)
            brew install ansible opentofu gettext qemu jq
            ;;
        Linux)
            if [[ ! -f /etc/debian_version ]]; then
                echo "Unsupported Linux distro — install ansible and opentofu manually." >&2
                exit 1
            fi
            # Ansible + qemu-img (tofu/talos image conversion) + jq (node IP discovery)
            sudo apt-get update -qq
            sudo apt-get install -y ansible gettext-base qemu-utils jq

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
