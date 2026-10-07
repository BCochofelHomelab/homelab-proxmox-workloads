# Ansible

Configures the VMs the OpenTofu stacks create
([`TERRAFORM.md`](TERRAFORM.md)). Services are installed from Elastic's
signed APT repository as DEB packages, pinned and held at
`elastic_version`; Elastic Agent comes from the Packer template (tarball,
Fleet-upgradable) and is only enrolled here.

```bash
mise run ansible:site                     # every playbook, in order
mise run ansible:site -- --tags <tag>     # extra ansible-playbook args after --
```

`ansible:site` runs `ansible-playbook playbooks/site.yml` from `ansible/`
with your age key (`ANSIBLE_SOPS_AGE_KEYFILE`), which decrypts the
inventory secrets and the CA key only while a task needs them.

## Inventory

`ansible/inventory/` holds one generated file per OpenTofu stack
(`elastic.ini`, `otel-demo.ini`, gitignored) and the hand-authored
`group_vars/`.

| Group | Hosts | From |
| --- | --- | --- |
| `elasticsearch` | `es-01`, `es-02`, `es-03` | `stacks/elastic/infra` |
| `kibana_server`, `fleet_server` | `kibana` | `stacks/elastic/infra` |
| `logstash`, `edot_gateway` | `ingest` | `stacks/elastic/infra` |
| `elastic` | every host above | `stacks/elastic/infra` |
| `otel_demo` (in `otel_demo_stack`) | `otel-demo` | `stacks/otel-demo/infra` |

| File | Holds |
| --- | --- |
| `group_vars/all.yml` | `elastic_version` (every Elastic package), the APT repository, the CA paths, the Elasticsearch ports and endpoints |
| `group_vars/elasticsearch.yml` | Cluster name, heap, the data disk's mount point |
| `group_vars/elastic.sops.yaml` | Secrets for the Elastic stack, SOPS-encrypted (below) |

## Playbooks

| Playbook | Does |
| --- | --- |
| `00-bootstrap.yml` | Preflight checks (`common`), then formats and mounts each data disk (`data_disk`) before any service is installed |
| `10-elasticsearch.yml` | Elastic's APT repository (`elastic_repo`), then Elasticsearch (`elasticsearch`) on every node; waits for green; rolling restart of nodes whose configuration changed |
| `99-healthcheck.yml` | From the controller, over TLS verified against the CA: every node answers as `elastic`, runs `elastic_version`, and the cluster is green with every node |

## Secrets

`inventory/group_vars/elastic.sops.yaml` (group `elastic`), encrypted to
your age key only, never to the AI agent's:

```yaml
elastic_password: <the elastic superuser's password, 12+ characters>
```

Create it from the repo root, where `.sops.yaml` applies:

```bash
sops ansible/inventory/group_vars/elastic.sops.yaml
```

and edit it later with `mise run sops -- ansible/inventory/group_vars/elastic.sops.yaml`.
Later playbooks add their own keys to the same file (Kibana's
`kibana_system` password and encryption keys, Logstash's credentials).

## Internal CA

Every Elastic component speaks TLS with certificates from one internal CA:

- `ansible/pki/elastic-ca.crt`: the CA certificate, committed.
- `ansible/pki/elastic-ca.key.sops`: its private key, SOPS-encrypted to
  your age key only (`.sops.yaml`), committed.

Both are created **once** with `mise run pki:init` (it refuses to replace
an existing CA): `openssl` pipes the key straight into `sops`, so it never
touches the disk in clear. Commit both files.

The `elastic_pki` role gives each host its own certificate: the private
key is generated on the host and never leaves it; its CSR is signed on the
controller with the CA key, decrypted by the `community.sops` lookup for
that task only. Certificates are valid for 2 years, carry the host's
short name, FQDN, `localhost` and its IPs, and are re-issued when they
expire within 30 days (re-run the playbook).

Clients outside the cluster trust `ansible/pki/elastic-ca.crt`, for
example `curl --cacert ansible/pki/elastic-ca.crt -u elastic https://192.168.68.30:9200`.

## Elasticsearch

- **Package:** `elasticsearch=<elastic_version>` from Elastic's APT
  repository (key verified by fingerprint), held with `apt-mark hold` so
  `apt upgrade` and unattended-upgrades never change it. Bump
  `elastic_version` and re-run the playbook to upgrade: the nodes restart
  one at a time.
- **Data:** `path.data` is `/var/lib/elasticsearch`, the 200 GB data disk.
- **Security:** TLS on the transport and HTTP layers with the node's
  certificate from the internal CA (`/etc/elasticsearch/certs/`). The DEB's
  own security auto-configuration (its generated certificates and keystore
  entries) is removed. The `elastic` user's password is
  `elastic_password`, set as `bootstrap.password` before the first start.
  Changing it later is an API call (`_security/user/elastic/_password`),
  not a re-run.
- **Heap and memory:** `es_heap_size` (4 GB of 8 GB), locked in RAM
  (`bootstrap.memory_lock`, systemd `LimitMEMLOCK=infinity`).

### Cluster formation and restarts

On a brand-new cluster (no node has a `/var/lib/elasticsearch/_state`),
`elasticsearch.yml` gets `cluster.initial_master_nodes` and all three nodes
start together. Once the cluster has formed, the next run drops that
setting, as Elastic requires, which triggers one rolling restart.

A node that's already running is never restarted in the parallel play. If
its package, configuration, certificate or heap changed, the
`Rolling restart` play restarts it alone (`serial: 1`): it waits for
green, allocates primaries only, restarts, waits for the node to rejoin,
re-enables allocation and waits for green before the next node.

To start over with an empty cluster, stop Elasticsearch on every node and
empty `/var/lib/elasticsearch` on all of them; the next run bootstraps a
new cluster.

## The AI agent

The agent can lint and syntax-check (`ansible-lint`,
`ansible-playbook --syntax-check`) and read the playbooks; it can't run
them. Running one asks you first (`.claude/settings.json`), and
`ansible:site`, `pki:init` and every decrypting `sops` command are denied
to it. Neither `elastic.sops.yaml` nor the CA key is encrypted to its key
(`mise run boundary:check`).
