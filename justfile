mod ansible "ansible/justfile"
mod tofu "tofu/justfile"

# List available recipes
default:
    @just --list

# Install ansible and opentofu (macOS via Homebrew, Debian/Ubuntu via apt)
install-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
        Darwin)
            brew install ansible opentofu
            ;;
        Linux)
            if [[ ! -f /etc/debian_version ]]; then
                echo "Unsupported Linux distro — install ansible and opentofu manually." >&2
                exit 1
            fi
            # Ansible
            sudo apt-get update -qq
            sudo apt-get install -y ansible

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
