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
| `group_vars/kibana_server.yml` | Kibana's public URL (through core's Caddy) |
| `group_vars/logstash.yml` | The data disk's mount point, heap, the agents' port |
| `group_vars/all.sops.yaml` | Secrets for the Elastic stack, SOPS-encrypted (below) |

## Playbooks

| Playbook | Does |
| --- | --- |
| `00-bootstrap.yml` | Preflight checks (`common`), then formats and mounts each data disk (`data_disk`) before any service is installed |
| `10-elasticsearch.yml` | Elastic's APT repository (`elastic_repo`), then Elasticsearch (`elasticsearch`) on every node; waits for green; rolling restart of nodes whose configuration changed; sets the built-in `remote_monitoring_user`'s password |
| `20-kibana.yml` | Kibana (`kibana`): `kibana_system`'s password, package, certificate, keystore, configuration; waits until available |
| `30-logstash.yml` | Logstash (`logstash`): the `logstash_writer` role and user, package, certificate, the Elastic Agent pipeline; waits until it runs and listens |
| `40-fleet-server.yml` | Fleet Server (`fleet_server`): enrolls the kibana VM's agent into `fleet-server-policy`, once; waits until healthy. Needs the Fleet config stack applied |
| `50-elastic-agents.yml` | Every other VM's Elastic Agent (`elastic_agent`): enrolled into its role's policy, once; waits until connected |
| `99-healthcheck.yml` | From the controller, over TLS verified against the CA: every Elasticsearch node answers as `elastic` and runs `elastic_version`, the cluster is green with every node, Kibana is available and runs `elastic_version`. Kibana through core's Caddy is reported without failing the run. Logstash's agent pipeline runs on `elastic_version`, and its port presents a certificate that verifies against the CA |

## Secrets

`inventory/group_vars/all.sops.yaml` (every host: each one enrolls its agent with them), encrypted to
your age key only, never to the AI agent's:

| Key | For |
| --- | --- |
| `elastic_password` | The `elastic` superuser (12+ characters) |
| `kibana_system_password` | The built-in `kibana_system` user Kibana connects as (12+ characters) |
| `kibana_encryption_key` | Kibana's saved-objects encryption key (32+ characters). Fleet and alerting secrets are encrypted with it: changing or losing it makes them unreadable. Kibana's session and reporting keys are derived from it. |
| `logstash_writer_password` | The `logstash_writer` user Logstash writes to Elasticsearch as (12+ characters) |
| `remote_monitoring_password` | The built-in `remote_monitoring_user` the stack-monitoring integrations collect as (12+ characters). Ansible sets it in Elasticsearch; the Fleet config stack reads it from this file |

Create the file once, from the repo root (`.sops.yaml` applies there),
with a generated password that's never shown:

```bash
printf 'elastic_password: "%s"\n' "$(openssl rand -base64 24)" \
  | sops encrypt --filename-override ansible/inventory/group_vars/all.sops.yaml \
  > ansible/inventory/group_vars/all.sops.yaml
```

Add a key to it later, generated the same way (`mise run sops` passes
your key, needed to re-encrypt):

```bash
mise run sops -- set ansible/inventory/group_vars/all.sops.yaml \
  '["kibana_system_password"]' "\"$(openssl rand -base64 24)\""
mise run sops -- set ansible/inventory/group_vars/all.sops.yaml \
  '["kibana_encryption_key"]' "\"$(openssl rand -hex 32)\""
```

See or edit the values with `mise run sops -- ansible/inventory/group_vars/all.sops.yaml`.
For example, Logstash's or the monitoring user's:

```bash
mise run sops -- set ansible/inventory/group_vars/all.sops.yaml \
  '["logstash_writer_password"]' "\"$(openssl rand -base64 24)\""
mise run sops -- set ansible/inventory/group_vars/all.sops.yaml \
  '["remote_monitoring_password"]' "\"$(openssl rand -base64 24)\""
```

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

### The agents' client certificate

Logstash only accepts clients with a certificate from the internal CA
(mTLS). Fleet's Logstash output holds **one** client certificate that every
Elastic Agent presents, so it's issued once, by `mise run pki:agent-client`:

- `ansible/pki/agent-client.crt`: `CN=elastic-agent`, client
  authentication only, valid 2 years, committed;
- `ansible/pki/agent-client.key.sops`: its key, SOPS-encrypted to your age
  key only, committed.

The key is held in memory, piped into `sops` and never written in clear.
The task refuses to replace an existing certificate: delete both files and
run it again to renew. The Fleet config stack sets both in Fleet's
Logstash output, so the key also ends up in Fleet and in that stack's
state.

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

## Kibana

- **Package:** `kibana=<elastic_version>`, held, like Elasticsearch.
- **Elasticsearch:** connects to every node as `kibana_system`, verifying
  their certificates against the internal CA. The playbook sets
  `kibana_system`'s password in Elasticsearch (as `elastic`) when it
  doesn't authenticate yet.
- **HTTPS:** Kibana listens on `192.168.68.33:5601` with its own
  certificate from the internal CA. People use
  `https://kibana.homelab.bcochofel.com`: core's Caddy terminates TLS with
  a Let's Encrypt certificate and proxies to Kibana, trusting the internal
  CA (`homelab-proxmox-core`).
- **Secrets:** `elasticsearch.password` and the three encryption keys live
  in Kibana's keystore. Their values can't be read back, so a SHA-256 of
  what was written (`/etc/kibana/.keystore.sha256`, root-only) tells the
  next run whether they changed; then they're rewritten and Kibana
  restarts.

## Logstash

- **Package:** `logstash=1:<elastic_version>-1` (Logstash's DEB has an
  epoch), held.
- **Data:** `path.data` is `/var/lib/logstash`, the 50 GB data disk,
  which also holds the persistent queue (`logstash_queue_max_bytes`,
  20 GB): it buffers while Elasticsearch is unreachable and survives a
  restart.
- **Agents in:** the `elastic-agent` pipeline's Elastic Agent input on
  port 5044, TLS with Logstash's own certificate from the internal CA, and
  `ssl_client_authentication => required`: only clients with a certificate
  from that CA (the agents' shared one) get in.
- **Elasticsearch out:** every Elasticsearch node, verified against the
  CA, as `logstash_writer`, into the data stream each event names
  (`data_stream => true`). The integrations' ingest pipelines run in
  Elasticsearch on arrival. `logstash_writer`'s role only creates
  documents in `logs-*-*`, `metrics-*-*`, `traces-*-*`, `synthetics-*-*`
  and `profiling-*`; the playbook creates the role and user (as `elastic`)
  and resets the password when it no longer authenticates.
- **Secrets:** the writer's password reaches the pipeline as
  `${LOGSTASH_WRITER_PASSWORD}`, from `/etc/default/logstash` (root-only,
  the unit's `EnvironmentFile`), never in a pipeline file. The heap
  (`logstash_heap_size`, 1 GB) is set there too, as `LS_JAVA_OPTS`.
- **Pipelines:** files reload on change (`config.reload.automatic`), no
  restart; settings, the environment file and certificates restart it.

## Fleet Server

- **Agent flavor:** the Packer template installs Elastic Agent's default
  (*basic*) flavor, which has no server components; Fleet Server needs the
  *servers* flavor, chosen at install time (`--install-servers`). So on the
  Fleet Server host the role reinstalls the agent once, from Elastic's
  tarball at `elastic_version` (SHA-512 and signature checked against
  Elastic's key, like the template's install), enrolling as Fleet Server in
  the same `elastic-agent install` command. The other VMs keep the
  template's agent.
- **Idempotency:** decided from what's there, not from a marker file: no
  `fleet-server` component → reinstall; installed but not `HEALTHY` →
  re-enroll (`--force`); healthy → nothing.
- **Policy:** `fleet-server-policy`, created by `stacks/elastic/fleet`; the
  playbook stops with a pointer to it if the policy doesn't exist yet.
- **Service token:** a fresh `elastic/fleet-server` service token at each
  enrollment (created as `elastic`, named `<host>-fleet-server`), in
  `/etc/fleet-server/service-token` (root-only), never on the command line.
  The agent stores that *path* and Fleet Server reads the file at every
  start, so it stays there.
- **TLS:** listens on `https://192.168.68.33:8220` with a certificate from
  the internal CA (`/etc/fleet-server/certs`, root-only), and verifies
  Elasticsearch against the CA. A new certificate restarts the agent.
- **Kibana:** the `kibana` role runs Fleet's setup (`POST /api/fleet/setup`),
  and turns off Kibana's legacy self-monitoring
  (`monitoring.kibana.collection.enabled: false`), whose `_monitoring/bulk`
  API is deprecated for removal in 10.0.

## Elastic Agents

- **Agent:** the one the Packer template installed (tarball,
  Fleet-upgradable, basic flavor), on every VM but Fleet Server's.
- **Policy per role** (`elastic_agent_policy_id`, `stacks/elastic/fleet`):
  `elasticsearch-nodes` (es-01..03, `group_vars/elasticsearch.yml`),
  `logstash` (ingest, `group_vars/logstash.yml`), `homelab-vms`
  (everything else, `group_vars/all.yml`). Role-specific integrations
  (stack monitoring) go on these policies.
- **Enrollment:** the policy's enrollment token from Fleet's API (read as
  `elastic`), `elastic-agent enroll --url https://192.168.68.33:8220`,
  trusting Fleet Server's certificate through the internal CA
  (`/etc/elastic-agent/ca.crt`). The token is on the command line for the
  few seconds `enroll` runs: it has no file option.
- **Idempotency:** an agent that reports `is_managed` and a healthy Fleet
  state (`elastic-agent status`) is left alone; otherwise it's enrolled
  (`--force`). Moving an enrolled agent to another policy is done in Fleet
  (*Assign to new policy*), not by changing `elastic_agent_policy_id`.
- **Data path:** every policy's default output is Logstash
  (`logstash-ingest`): the agent sends over mTLS with the shared client
  certificate, Logstash writes to Elasticsearch.
- **Health check:** Fleet's agent list has an `online` agent for every host
  in the inventory, Fleet Server's included.

## The AI agent

The agent can lint and syntax-check (`ansible-lint`,
`ansible-playbook --syntax-check`) and read the playbooks; it can't run
them. Running one asks you first (`.claude/settings.json`), and
`ansible:site`, `pki:init` and every decrypting `sops` command are denied
to it. Neither `all.sops.yaml` nor the CA key is encrypted to its key
(`mise run boundary:check`).
