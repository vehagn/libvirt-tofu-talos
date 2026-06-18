terraform {
  # Ephemeral resources and write-only arguments (talos provider 0.12 uses
  # ephemeral talos_cluster_kubeconfig) require Terraform 1.11+/OpenTofu 1.10+.
  required_version = ">= 1.10"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-alpha.4"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}
