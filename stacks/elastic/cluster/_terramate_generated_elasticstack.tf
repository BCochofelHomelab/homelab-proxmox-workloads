# TERRAMATE: GENERATED AUTOMATICALLY DO NOT EDIT

provider "elasticstack" {
  elasticsearch {
    ca_file = "${path.module}/../../../ansible/pki/elastic-ca.crt"
    endpoints = [
      "https://192.168.68.30:9200",
      "https://192.168.68.31:9200",
      "https://192.168.68.32:9200",
    ]
  }
  kibana {
    ca_certs = [
      "${path.module}/../../../ansible/pki/elastic-ca.crt",
    ]
    endpoints = [
      "https://192.168.68.33:5601",
    ]
  }
  fleet {
    ca_certs = [
      "${path.module}/../../../ansible/pki/elastic-ca.crt",
    ]
    endpoint = "https://192.168.68.33:5601"
  }
}
