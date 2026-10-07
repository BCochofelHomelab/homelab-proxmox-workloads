# ----------------------------------------------------------------------------
# vm — clone one VM from the Packer template, with static-IP cloud-init,
# and optionally a second data disk. Generic across any VM role: roles
# differ only in sizing, tags and the Ansible groups the stack puts them in.
# Ported from homelab-proxmox-core's module, plus data_disk.
# ----------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  vm_id       = var.vmid
  node_name   = var.target_node
  description = var.description
  tags        = var.tags

  # Clone from the Packer-built template
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  # Resize the cloned disk. bpg manages the disk that came from the template;
  # we set the target size here (must be >= template disk size).
  disk {
    interface    = "scsi0"
    datastore_id = var.datastore_id
    size         = var.disk
    discard      = "on"
    ssd          = true
  }

  # Optional second disk, not part of the template: provisioned empty at
  # var.data_disk GB. Ansible formats and mounts it where the role keeps
  # its data (e.g. /var/lib/elasticsearch), so data can grow without the
  # OS disk's LVM root being the limit.
  dynamic "disk" {
    for_each = var.data_disk == null ? [] : [var.data_disk]

    content {
      interface    = "scsi1"
      datastore_id = var.datastore_id
      size         = disk.value
      file_format  = "raw"
      discard      = "on"
      ssd          = true
      iothread     = true
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # Static IP via cloud-init (sourced from tfvars — single source of truth)
  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_cidr
        gateway = var.gateway
      }
    }

    dns {
      servers = var.nameserver
      domain  = var.searchdomain
    }

    user_account {
      username = var.ciuser
      password = var.cipassword
      keys     = compact(split("\n", var.sshkeys))
    }
  }

  # Don't let Terraform fight cloud-init / agent over the reported IP after boot
  lifecycle {
    ignore_changes = [
      initialization[0].user_account[0].password,
    ]
  }
}
