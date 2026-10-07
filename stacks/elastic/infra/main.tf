# ----------------------------------------------------------------------------
# Elastic stack VMs, cloned from the Packer template, plus the Ansible
# inventory for them. Everything else these VMs need (packages, config,
# certificates, enrollment) is Ansible's; Elastic-side configuration (ILM,
# Fleet, Kibana) lives in the elastic/* config stacks.
#
# 192.168.68.30-39 is reserved for the Elastic stack and its demo workloads.
# ----------------------------------------------------------------------------

locals {
  # name => VM definition. `groups` are the Ansible inventory groups the
  # host lands in. data_disk is mounted by Ansible where the role keeps its
  # data (Elasticsearch data, Logstash's persistent queue).
  nodes = {
    "es-01" = { ip_cidr = "192.168.68.30/22", cores = 2, memory = 8192, disk = 50, data_disk = 200, groups = ["elasticsearch"] }
    "es-02" = { ip_cidr = "192.168.68.31/22", cores = 2, memory = 8192, disk = 50, data_disk = 200, groups = ["elasticsearch"] }
    "es-03" = { ip_cidr = "192.168.68.32/22", cores = 2, memory = 8192, disk = 50, data_disk = 200, groups = ["elasticsearch"] }
    # Kibana, and the template's Elastic Agent enrolled as Fleet Server.
    "kibana" = { ip_cidr = "192.168.68.33/22", cores = 2, memory = 4096, disk = 50, data_disk = null, groups = ["kibana", "fleet_server"] }
    # Logstash (every agent's output) and the EDOT Collector gateway (OTLP).
    "ingest" = { ip_cidr = "192.168.68.34/22", cores = 2, memory = 4096, disk = 50, data_disk = 50, groups = ["logstash", "edot_gateway"] }
  }

  inventory_groups = distinct(flatten([for node in values(local.nodes) : node.groups]))
}

module "vm" {
  source   = "../../../modules/vm"
  for_each = local.nodes

  name          = each.key
  target_node   = local.target_node
  template_vmid = local.template_vmid
  description   = "Managed by OpenTofu (homelab-proxmox-workloads, stacks/elastic/infra)"
  tags          = concat(["terraform", "elastic"], [for group in each.value.groups : replace(group, "_", "-")])

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

# ----------------------------------------------------------------------------
# Ansible inventory: ansible/inventory/elastic.ini. Only the host list is
# generated; group_vars/ stays hand-authored.
# ----------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    groups = {
      for group in local.inventory_groups : group => {
        for name, node in local.nodes : name => module.vm[name].ip if contains(node.groups, group)
      }
    }
    ansible_user = local.ciuser
  })
  filename        = "${path.module}/../../../ansible/inventory/elastic.ini"
  file_permission = "0644"
}
