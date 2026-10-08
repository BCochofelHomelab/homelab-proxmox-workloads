# TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

terraform {
  required_version = "> 1.9.0, < 2.0"
  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~> 0.16.5"
    }
  }
  cloud {
    hostname     = "app.terraform.io"
    organization = "homelab-bcochofel-com"
    workspaces {
      name = "workloads-elastic-cluster"
    }
  }
}
