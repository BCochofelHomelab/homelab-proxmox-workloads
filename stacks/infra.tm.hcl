# Code generated into every stack tagged "infra" (Proxmox VMs): backend,
# providers, the template lookup and the shared inputs. Stacks only hold
# their own VMs and inventory. Edit here, then `terramate generate`; never
# edit the generated files (_terramate_generated_*.tf, variables.tf) by hand.

generate_hcl "_terramate_generated_backend.tf" {
  condition = tm_contains(terramate.stack.tags, "infra")

  content {
    terraform {
      required_version = "> 1.9.0, < 2.0"

      required_providers {
        proxmox = {
          source  = "bpg/proxmox"
          version = "~> 0.116.0" # patch releases only: bpg iterates fast
        }
        local = {
          source  = "hashicorp/local"
          version = "2.9.0"
        }
      }

      # HCP Terraform, state only (workspace execution mode Local): Proxmox
      # is LAN-only. OpenTofu has no default hostname for the cloud backend.
      cloud {
        hostname     = "app.terraform.io"
        organization = global.hcp_organization

        workspaces {
          name = global.hcp_workspace
        }
      }
    }
  }
}

# Named variables.tf (not _terramate_generated_*), as TFLint's
# terraform_standard_module_structure expects; still generated.
generate_hcl "variables.tf" {
  condition = tm_contains(terramate.stack.tags, "infra")

  content {
    # Secrets: TF_VAR_* from ~/.secrets/homelab.yaml (`mise run tofu:*`).
    variable "proxmox_api_token" {
      type        = string
      description = "Proxmox API token, form user@realm!tokenid=secret (terraform@pve!terraform)"
      sensitive   = true
    }

    variable "cipassword" {
      type        = string
      description = "cloud-init user password"
      sensitive   = true
    }
  }
}

generate_hcl "_terramate_generated_proxmox.tf" {
  condition = tm_contains(terramate.stack.tags, "infra")

  content {
    # Non-secret inputs, from the globals in terramate.tm.hcl.
    locals {
      target_node  = global.proxmox.node
      gateway      = global.network.gateway
      bridge       = global.network.bridge
      nameservers  = global.network.nameservers
      searchdomain = global.network.searchdomain
      ciuser       = global.ciuser
      sshkeys      = tm_join("\n", global.sshkeys)
    }

    provider "proxmox" {
      endpoint  = global.proxmox.endpoint
      api_token = var.proxmox_api_token
      insecure  = global.proxmox.insecure

      # Only some operations (file uploads) need SSH; cloning and cloud-init
      # go through the API.
      ssh {
        agent    = true
        username = "root"
      }
    }

    # The template's VMID, looked up by name.
    data "proxmox_virtual_environment_vms" "template" {
      node_name = global.proxmox.node

      filter {
        name   = "name"
        values = [global.proxmox.template]
      }
    }

    locals {
      template_vmid = one(data.proxmox_virtual_environment_vms.template.vms).vm_id
    }
  }
}
