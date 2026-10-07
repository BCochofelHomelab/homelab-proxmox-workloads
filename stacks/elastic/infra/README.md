# stacks/elastic/infra

Elastic stack VMs (Elasticsearch, Kibana + Fleet Server, ingest) and `ansible/inventory/elastic.ini`. See [`docs/TERRAFORM.md`](../../../docs/TERRAFORM.md).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | 2.9.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement\_proxmox) | ~> 0.116.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.0 |
| <a name="provider_proxmox"></a> [proxmox](#provider\_proxmox) | 0.116.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_vm"></a> [vm](#module\_vm) | ../../../modules/vm | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [local_file.ansible_inventory](https://registry.terraform.io/providers/hashicorp/local/2.9.0/docs/resources/file) | resource |
| [proxmox_virtual_environment_vms.template](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/data-sources/virtual_environment_vms) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cipassword"></a> [cipassword](#input\_cipassword) | cloud-init user password | `string` | n/a | yes |
| <a name="input_proxmox_api_token"></a> [proxmox\_api\_token](#input\_proxmox\_api\_token) | Proxmox API token, form user@realm!tokenid=secret (terraform@pve!terraform) | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_inventory_path"></a> [inventory\_path](#output\_inventory\_path) | Path to the generated Ansible inventory |
| <a name="output_nodes"></a> [nodes](#output\_nodes) | Elastic stack VMs: name => VMID and IP |
<!-- END_TF_DOCS -->
