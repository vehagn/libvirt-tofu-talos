terraform {
  required_version = ">= 1.10"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-alpha.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
