stack {
  name        = "elastic-cluster"
  description = "Elasticsearch cluster configuration: ILM, @custom component templates"
  tags        = ["config", "elastic"]
  after       = ["/stacks/elastic/infra"]
  id          = "1b70a325-c33a-404d-91bd-52c15e89c151"
}
