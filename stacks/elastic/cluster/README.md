# stacks/elastic/cluster

Elasticsearch cluster configuration: the `homelab-30d` ILM policy (hot 7 days, cold until day 30, then deleted) and the `logs@custom`, `metrics@custom`, `traces@custom` component templates that apply it. See [`docs/TERRAFORM.md`](../../../docs/TERRAFORM.md#retention-stackselasticcluster).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | > 1.9.0, < 2.0 |
| <a name="requirement_elasticstack"></a> [elasticstack](#requirement\_elasticstack) | ~> 0.16.5 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_elasticstack"></a> [elasticstack](#provider\_elasticstack) | 0.16.5 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [elasticstack_elasticsearch_component_template.lifecycle](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/elasticsearch_component_template) | resource |
| [elasticstack_elasticsearch_index_lifecycle.homelab](https://registry.terraform.io/providers/elastic/elasticstack/latest/docs/resources/elasticsearch_index_lifecycle) | resource |

## Inputs

No inputs.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_component_templates"></a> [component\_templates](#output\_component\_templates) | The @custom component templates that set it |
| <a name="output_ilm_policy"></a> [ilm\_policy](#output\_ilm\_policy) | ILM policy every logs, metrics and traces data stream uses |
<!-- END_TF_DOCS -->
