# ----------------------------------------------------------------------------
# OpenTelemetry Demo VM, cloned from the Packer template, plus the Ansible
# inventory for it. Ansible installs Docker and runs the demo's Docker
# Compose (minimal variant), which sends OTLP to the EDOT gateway on the
# elastic stack's ingest VM.
# ----------------------------------------------------------------------------

locals {
  # name => VM definition; see stacks/elastic/infra/main.tf. The minimal
  # demo needs about 3 GB of RAM, plus Docker and Elastic Agent.
  nodes = {
    "otel-demo" = { ip_cidr = "192.168.68.35/22", cores = 2, memory = 6144, disk = 50, data_disk = null, groups = ["otel_demo"] }
  }

  inventory_groups = distinct(flatten([for node in values(local.nodes) : node.groups]))
}

module "vm" {
  source   = "../../../modules/vm"
  for_each = local.nodes

  name          = each.key
  target_node   = local.target_node
  template_vmid = local.template_vmid
  description   = "Managed by OpenTofu (homelab-proxmox-workloads, stacks/otel-demo/infra)"
  tags          = concat(["terraform", "otel-demo"], [for group in each.value.groups : replace(group, "_", "-")])

  cores     = each.value.cores
  memory    = each.value.memory
  disk      = each.value.disk
  data_disk = each.value.data_disk

  ip_cidr        = each.value.ip_cidr
  gateway        = local.gateway
  network_bridge = local.bridge
  nameserver     = local.nameservers
  searchdomain   = local.searchdomain

  ciuser     = local.ciuser
  cipassword = var.cipassword
  sshkeys    = local.sshkeys
}

# Ansible inventory: ansible/inventory/otel-demo.ini (see the elastic stack).
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    groups = {
      for group in local.inventory_groups : group => {
        for name, node in local.nodes : name => module.vm[name].ip if contains(node.groups, group)
      }
    }
    ansible_user = local.ciuser
  })
  filename        = "${path.module}/../../../ansible/inventory/otel-demo.ini"
  file_permission = "0644"
}
