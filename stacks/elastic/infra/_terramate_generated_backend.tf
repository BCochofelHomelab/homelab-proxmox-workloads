# TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

terraform {
  required_version = "> 1.9.0, < 2.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
  }
  cloud {
    hostname     = "app.terraform.io"
    organization = "homelab-bcochofel-com"
    workspaces {
      name = "workloads-elastic-infra"
    }
  }
}
