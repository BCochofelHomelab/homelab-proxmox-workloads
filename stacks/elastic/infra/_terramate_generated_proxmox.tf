# TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

locals {
  bridge  = "vmbr0"
  ciuser  = "ubuntu"
  gateway = "192.168.68.1"
  nameservers = [
    "192.168.68.2",
    "192.168.68.3",
  ]
  searchdomain = "homelab.bcochofel.com"
  sshkeys      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZGQwHOs8V9ndmLn3NuQXxuD0Ht4zaz+c6/WaEMAA6S bcochofel@NUC12WSHi7"
  target_node  = "pve1"
}
provider "proxmox" {
  api_token = var.proxmox_api_token
  endpoint  = "https://192.168.68.20:8006/"
  insecure  = true
  ssh {
    agent    = true
    username = "root"
  }
}
data "proxmox_virtual_environment_vms" "template" {
  node_name = "pve1"
  filter {
    name = "name"
    values = [
      "ubuntu-26.04-workloads",
    ]
  }
}
locals {
  template_vmid = one(data.proxmox_virtual_environment_vms.template.vms).vm_id
}
