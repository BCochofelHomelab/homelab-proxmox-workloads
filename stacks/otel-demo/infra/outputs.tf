output "nodes" {
  value = {
    for name, vm in module.vm : name => {
      vmid = vm.vmid
      ip   = vm.ip
    }
  }
  description = "OpenTelemetry Demo VMs: name => VMID and IP"
}

output "inventory_path" {
  value       = local_file.ansible_inventory.filename
  description = "Path to the generated Ansible inventory"
}
