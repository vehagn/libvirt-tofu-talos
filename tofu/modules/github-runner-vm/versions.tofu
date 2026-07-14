# Modules must declare required_providers explicitly — OpenTofu won't inherit from root and defaults to hashicorp/libvirt.
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }
}
