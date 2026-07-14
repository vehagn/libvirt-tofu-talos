terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
