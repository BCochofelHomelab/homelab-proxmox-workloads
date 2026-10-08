output "fleet_server_url" {
  value       = local.fleet_server_url
  description = "Where agents reach Fleet Server"
}

output "agent_policies" {
  value = {
    fleet_server = elasticstack_fleet_agent_policy.fleet_server.policy_id
    vms          = elasticstack_fleet_agent_policy.vms.policy_id
  }
  description = "Agent policy IDs Ansible enrolls into"
}

output "outputs" {
  value = {
    default       = elasticstack_fleet_output.logstash.output_id
    elasticsearch = elasticstack_fleet_output.elasticsearch.output_id
  }
  description = "Fleet outputs: Logstash is the default; Fleet Server's policy keeps Elasticsearch"
}
