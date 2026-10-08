output "ilm_policy" {
  value       = elasticstack_elasticsearch_index_lifecycle.homelab.name
  description = "ILM policy every logs, metrics and traces data stream uses"
}

output "component_templates" {
  value       = [for template in elasticstack_elasticsearch_component_template.lifecycle : template.name]
  description = "The @custom component templates that set it"
}
