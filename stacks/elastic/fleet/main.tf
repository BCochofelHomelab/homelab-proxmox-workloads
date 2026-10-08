# ----------------------------------------------------------------------------
# Fleet: where agents send data, and what they run.
#
#   agents ──mTLS──> Logstash (ingest:5044) ──> Elasticsearch   default output
#   Fleet Server (kibana:8220) ─────────────> Elasticsearch     its own policy
#
# Fleet Server only works with an Elasticsearch output, and the Basic licence
# has no per-policy outputs. So the order matters: the Fleet Server policy
# gets its integration while Elasticsearch is still the default output, and
# only then is Logstash made the default; the Fleet Server policy keeps
# Elasticsearch (depends_on below). Enrolling Fleet Server and the agents is
# Ansible's (docs/ANSIBLE.md).
# ----------------------------------------------------------------------------

locals {
  pki = "${path.module}/../../../ansible/pki"

  ca_pem               = trimspace(file("${local.pki}/elastic-ca.crt"))
  agent_client_crt_pem = trimspace(file("${local.pki}/agent-client.crt"))

  fleet_server_url = "https://192.168.68.33:8220" # kibana VM
  logstash_host    = "192.168.68.34:5044"         # ingest VM
}

# The agents' client key, decrypted with your age key (versions.tf).
data "sops_file" "agent_client_key" {
  source_file = "${local.pki}/agent-client.key.sops"
  input_type  = "raw"
}

# -- Integration packages (versions compatible with Kibana 9.5.4) -------------

resource "elasticstack_fleet_integration" "fleet_server" {
  name         = "fleet_server"
  version      = "1.6.1"
  skip_destroy = true
}

resource "elasticstack_fleet_integration" "system" {
  name         = "system"
  version      = "3.0.0"
  skip_destroy = true
}

# -- Fleet Server ---------------------------------------------------------------

resource "elasticstack_fleet_server_host" "kibana" {
  host_id = "fleet-server-kibana"
  name    = "Fleet Server (kibana)"
  hosts   = [local.fleet_server_url]
  default = true
}

# -- Outputs ----------------------------------------------------------------------

# Fleet's own default output, created by Fleet's setup (the kibana role runs
# it), adopted here: every Elasticsearch node, verified against the CA.
import {
  to = elasticstack_fleet_output.elasticsearch
  id = "fleet-default-output"
}

resource "elasticstack_fleet_output" "elasticsearch" {
  output_id = "fleet-default-output"
  name      = "Elasticsearch"
  type      = "elasticsearch"
  hosts     = ["https://192.168.68.30:9200", "https://192.168.68.31:9200", "https://192.168.68.32:9200"]

  ssl = {
    certificate_authorities = [local.ca_pem]
    verification_mode       = "full"
  }

  # Logstash becomes the default (below); Fleet Server's policy keeps this one.
  default_integrations = false
  default_monitoring   = false

  depends_on = [elasticstack_fleet_output.logstash]
}

# Every agent's output (data and monitoring): Logstash, mTLS with the agents'
# shared client certificate (ansible/pki/agent-client.*).
resource "elasticstack_fleet_output" "logstash" {
  output_id = "logstash-ingest"
  name      = "Logstash (ingest)"
  type      = "logstash"
  hosts     = [local.logstash_host]

  ssl = {
    certificate_authorities = [local.ca_pem]
    certificate             = local.agent_client_crt_pem
    key                     = trimspace(data.sops_file.agent_client_key.raw)
    verification_mode       = "full"
  }

  default_integrations = true
  default_monitoring   = true

  # Only once Fleet Server's policy has its integration (see the top).
  depends_on = [
    elasticstack_fleet_integration_policy.fleet_server,
    elasticstack_fleet_integration_policy.fleet_server_system,
  ]
}

# -- Agent policies ---------------------------------------------------------------

resource "elasticstack_fleet_agent_policy" "fleet_server" {
  policy_id            = "fleet-server-policy"
  name                 = "Fleet Server"
  namespace            = "default"
  description          = "Fleet Server on the kibana VM (homelab-proxmox-workloads, stacks/elastic/fleet)"
  monitor_logs         = true
  monitor_metrics      = true
  fleet_server_host_id = elasticstack_fleet_server_host.kibana.host_id
}

resource "elasticstack_fleet_integration_policy" "fleet_server" {
  name                = "fleet-server"
  namespace           = "default"
  description         = "Fleet Server, port 8220"
  agent_policy_id     = elasticstack_fleet_agent_policy.fleet_server.policy_id
  integration_name    = elasticstack_fleet_integration.fleet_server.name
  integration_version = elasticstack_fleet_integration.fleet_server.version
}

resource "elasticstack_fleet_integration_policy" "fleet_server_system" {
  name                = "system-fleet-server"
  namespace           = "default"
  description         = "Host logs and metrics of the kibana VM"
  agent_policy_id     = elasticstack_fleet_agent_policy.fleet_server.policy_id
  integration_name    = elasticstack_fleet_integration.system.name
  integration_version = elasticstack_fleet_integration.system.version
}

# Every other VM (Elasticsearch, Logstash, OTel Demo); enrolled by Ansible.
resource "elasticstack_fleet_agent_policy" "vms" {
  policy_id            = "homelab-vms"
  name                 = "Homelab VMs"
  namespace            = "default"
  description          = "Elastic stack and workload VMs (homelab-proxmox-workloads, stacks/elastic/fleet)"
  monitor_logs         = true
  monitor_metrics      = true
  fleet_server_host_id = elasticstack_fleet_server_host.kibana.host_id
}

resource "elasticstack_fleet_integration_policy" "vms_system" {
  name                = "system-homelab-vms"
  namespace           = "default"
  description         = "Host logs and metrics"
  agent_policy_id     = elasticstack_fleet_agent_policy.vms.policy_id
  integration_name    = elasticstack_fleet_integration.system.name
  integration_version = elasticstack_fleet_integration.system.version
}
