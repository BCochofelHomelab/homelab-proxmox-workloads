# Terramate project root: orchestrates the OpenTofu stacks under stacks/
# and generates the code every stack of a kind shares (stacks/*.tm.hcl).
# See docs/TERRAFORM.md.

terramate {
  required_version = "~> 0.17.0"

  config {
    git {
      default_branch = "main"
    }

    # `terramate run` refuses to run with uncommitted or untracked files by
    # default. Plans are made on a feature branch while editing, before
    # committing, so those two checks are off; the plan is still reviewed
    # before `tofu:apply`.
    disable_safeguards = ["git-uncommitted", "git-untracked"]

    # TFLint's terraform_comment_syntax wants `#`, not `//`, in .tf files.
    generate {
      hcl_magic_header_comment_style = "#"
    }
  }
}

# Non-secret inputs shared by every infra stack. Secrets
# (TF_VAR_proxmox_api_token, TF_VAR_cipassword, TF_TOKEN_app_terraform_io)
# never live here: they come from ~/.secrets/homelab.yaml through the
# `mise run tofu:*` tasks (docs/CREDENTIALS.md).
globals {
  hcp_organization = "homelab-bcochofel-com"
  # One HCP workspace per stack, named after its path:
  # stacks/elastic/infra -> workloads-elastic-infra.
  hcp_workspace = "workloads-${tm_replace(tm_trimprefix(terramate.stack.path.relative, "stacks/"), "/", "-")}"

  proxmox = {
    endpoint = "https://192.168.68.20:8006/"
    insecure = true # self-signed certificate
    node     = "pve1"
    template = "ubuntu-26.04-workloads" # packer/ubuntu-26.04, VM 9001
  }

  network = {
    gateway = "192.168.68.1"
    bridge  = "vmbr0"
    # CoreDNS primary and secondary (homelab-proxmox-core). Pihole isn't a
    # resolver for these VMs.
    nameservers  = ["192.168.68.2", "192.168.68.3"]
    searchdomain = "homelab.bcochofel.com"
  }

  # cloud-init user on every clone; matches the template's user and
  # Ansible's remote user.
  ciuser = "ubuntu"
  # Public keys only: nothing to encrypt.
  sshkeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZGQwHOs8V9ndmLn3NuQXxuD0Ht4zaz+c6/WaEMAA6S bcochofel@NUC12WSHi7",
  ]
}
