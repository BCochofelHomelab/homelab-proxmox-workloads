stack {
  name        = "elastic-fleet"
  description = "Fleet: outputs (Elasticsearch, Logstash over mTLS), Fleet Server host, agent and integration policies"
  tags        = ["config", "elastic"]
  after       = ["/stacks/elastic/cluster"]
  id          = "3bbf0dd3-c25b-4b4d-b3dd-a15c38d2ffc7"
}

globals {
  # Decrypts the agents' client key (ansible/pki/agent-client.key.sops) with
  # SOPS_AGE_KEY_FILE, your key, which the `mise run tofu:*` tasks set.
  elastic_extra_providers = {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4.1"
    }
  }
}
