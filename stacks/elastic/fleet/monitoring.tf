# ----------------------------------------------------------------------------
# Stack monitoring: the agents collect Elasticsearch, Kibana and Logstash
# metrics and logs (Kibana's Stack Monitoring app, the integrations'
# dashboards), each on its role's policy. Not Elasticsearch's legacy
# self-collection (xpack.monitoring.collection.enabled stays off).
#
# Credentials: the built-in remote_monitoring_user, whose password Ansible
# sets from ansible/inventory/group_vars/all.sops.yaml; read here from the
# same file (your age key), so it lives in one place.
# ----------------------------------------------------------------------------

data "sops_file" "ansible_secrets" {
  source_file = "${local.pki}/../inventory/group_vars/all.sops.yaml"
}

locals {
  remote_monitoring = {
    username = "remote_monitoring_user"
    password = data.sops_file.ansible_secrets.data["remote_monitoring_password"]
  }
}

resource "elasticstack_fleet_integration" "monitoring" {
  for_each = {
    elasticsearch = "1.23.3"
    kibana        = "2.9.0"
    logstash      = "2.11.3"
  }

  name         = each.key
  version      = each.value
  skip_destroy = true
}

# Every Elasticsearch node collects its own node-level metrics (scope node)
# and reads its own logs.
resource "elasticstack_fleet_integration_policy" "elasticsearch_monitoring" {
  name                = "elasticsearch-monitoring"
  namespace           = "default"
  description         = "Stack monitoring: each node's metrics (https://localhost:9200) and logs"
  agent_policy_id     = elasticstack_fleet_agent_policy.agents["elasticsearch-nodes"].policy_id
  integration_name    = elasticstack_fleet_integration.monitoring["elasticsearch"].name
  integration_version = elasticstack_fleet_integration.monitoring["elasticsearch"].version

  inputs = {
    "elasticsearch-elasticsearch/metrics" = {
      enabled = true
      vars = jsonencode({
        hosts    = ["https://localhost:9200"]
        username = local.remote_monitoring.username
        password = local.remote_monitoring.password
        scope    = "node"
        ssl      = "certificate_authorities: [\"/etc/elasticsearch/certs/ca.crt\"]"
      })
    }
    "elasticsearch-logfile" = {
      enabled = true
    }
  }
}

# Kibana listens on the kibana VM's address only, not localhost.
resource "elasticstack_fleet_integration_policy" "kibana_monitoring" {
  name                = "kibana-monitoring"
  namespace           = "default"
  description         = "Stack monitoring: Kibana's metrics (https://192.168.68.33:5601) and logs"
  agent_policy_id     = elasticstack_fleet_agent_policy.fleet_server.policy_id
  integration_name    = elasticstack_fleet_integration.monitoring["kibana"].name
  integration_version = elasticstack_fleet_integration.monitoring["kibana"].version

  inputs = {
    "kibana-kibana/metrics" = {
      enabled = true
      vars = jsonencode({
        hosts    = ["https://192.168.68.33:5601"]
        username = local.remote_monitoring.username
        password = local.remote_monitoring.password
        ssl      = "certificate_authorities: [\"/etc/kibana/certs/ca.crt\"]"
      })
    }
    "kibana-http/metrics" = {
      enabled = true
      vars = jsonencode({
        hosts    = ["https://192.168.68.33:5601"]
        username = local.remote_monitoring.username
        password = local.remote_monitoring.password
        ssl      = "certificate_authorities: [\"/etc/kibana/certs/ca.crt\"]"
      })
    }
    "kibana-logfile" = {
      enabled = true
    }
  }
}

# Logstash's monitoring API is on localhost:9600, without authentication.
# The stack-monitoring streams are off by default in the package; Kibana's
# Stack Monitoring app needs them.
resource "elasticstack_fleet_integration_policy" "logstash_monitoring" {
  name                = "logstash-monitoring"
  namespace           = "default"
  description         = "Stack monitoring: Logstash's metrics (http://localhost:9600) and logs"
  agent_policy_id     = elasticstack_fleet_agent_policy.agents["logstash"].policy_id
  integration_name    = elasticstack_fleet_integration.monitoring["logstash"].name
  integration_version = elasticstack_fleet_integration.monitoring["logstash"].version

  inputs = {
    "logstash-cel" = {
      enabled = true
    }
    "logstash-logstash/metrics" = {
      enabled = true
      streams = {
        "logstash.stack_monitoring.node"       = { enabled = true }
        "logstash.stack_monitoring.node_stats" = { enabled = true }
      }
    }
    "logstash-logfile" = {
      enabled = true
    }
  }
}
