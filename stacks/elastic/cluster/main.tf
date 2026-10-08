# ----------------------------------------------------------------------------
# Elasticsearch cluster configuration: retention for every logs, metrics
# and traces data stream (Elastic Agent integrations and OTel data alike).
#
#   hot   0-7 days   written and searched; rolls over daily (or at 50 GB)
#   cold  7-30 days  read-only, lower recovery priority
#   then deleted
#
# Ages count from each backing index's rollover, so data is kept 30 days
# plus up to one day in the write index.
#
# The three nodes are identical (every data tier), so "cold" doesn't move
# data to other hardware: migrate is off.
# ----------------------------------------------------------------------------

resource "elasticstack_elasticsearch_index_lifecycle" "homelab" {
  name = "homelab-30d"

  hot {
    min_age = "0ms"
    set_priority {
      priority = 100
    }
    rollover {
      max_age                = "1d"
      max_primary_shard_size = "50gb"
    }
  }

  cold {
    min_age = "7d"
    set_priority {
      priority = 0
    }
    readonly {}
    migrate {
      enabled = false
    }
  }

  delete {
    min_age = "30d"
    delete {}
  }
}

# Elastic's built-in and Fleet integration index templates compose the
# optional <type>@custom component template after their own settings, so
# setting the policy there applies it to every data stream of that type
# created or rolled over from now on.
resource "elasticstack_elasticsearch_component_template" "lifecycle" {
  for_each = toset(["logs", "metrics", "traces"])

  name = "${each.key}@custom"

  template {
    settings = jsonencode({
      "index.lifecycle.name" = elasticstack_elasticsearch_index_lifecycle.homelab.name
    })
  }

  metadata = jsonencode({
    managed_by  = "opentofu"
    description = "homelab-proxmox-workloads stacks/elastic/cluster"
  })
}
