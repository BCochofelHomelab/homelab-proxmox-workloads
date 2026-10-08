# stacks/elastic/fleet

Fleet: the Logstash output (default, mTLS) and Fleet's Elasticsearch output, the Fleet Server host, and the `fleet-server-policy` and `homelab-vms` agent policies. See [`docs/TERRAFORM.md`](../../../docs/TERRAFORM.md#fleet-stackselasticfleet).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_elasticstack"></a> [elasticstack](#requirement\_elasticstack) | ~> 0.16.5 |
| <a name="requirement_sops"></a> [sops](#requirement\_sops) | ~> 1.4.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_elasticstack"></a> [elasticstack](#provider\_elasticstack) | 0.16.5 |
| <a name="provider_sops"></a> [sops](#provider\_sops) | 1.4.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [elasticstack_fleet_agent_policy.fleet_server](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_agent_policy) | resource |
| [elasticstack_fleet_agent_policy.vms](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_agent_policy) | resource |
| [elasticstack_fleet_integration.fleet_server](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_integration) | resource |
| [elasticstack_fleet_integration.system](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_integration) | resource |
| [elasticstack_fleet_integration_policy.fleet_server](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_integration_policy) | resource |
| [elasticstack_fleet_integration_policy.fleet_server_system](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_integration_policy) | resource |
| [elasticstack_fleet_integration_policy.vms_system](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_integration_policy) | resource |
| [elasticstack_fleet_output.elasticsearch](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_output) | resource |
| [elasticstack_fleet_output.logstash](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_output) | resource |
| [elasticstack_fleet_server_host.kibana](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/fleet_server_host) | resource |
| [sops_file.agent_client_key](https://registry.terraform.io/providers/carlpett/sops/latest/docs/data-sources/file) | data source |

## Inputs

No inputs.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_agent_policies"></a> [agent\_policies](#output\_agent\_policies) | Agent policy IDs Ansible enrolls into |
| <a name="output_fleet_server_url"></a> [fleet\_server\_url](#output\_fleet\_server\_url) | Where agents reach Fleet Server |
| <a name="output_outputs"></a> [outputs](#output\_outputs) | Fleet outputs: Logstash is the default; Fleet Server's policy keeps Elasticsearch |
<!-- END_TF_DOCS -->
