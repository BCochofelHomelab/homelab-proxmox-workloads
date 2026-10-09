# Credentials

The homelab is two repositories:

- [`homelab-proxmox-core`](https://github.com/BCochofelHomelab/homelab-proxmox-core):
  the stack, the base infrastructure everything else runs on.
- `homelab-proxmox-workloads` (this repo): the workloads running on top
  of it.

Both use the same Proxmox node, the same identities and the same secret
files, so the credential setup is done **once**, in core, and this repo
reuses it. The full guide, with the reasoning behind the model, is core's
[`docs/CREDENTIALS.md`](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md).
This doc only lists what's shared and covers what's specific to this repo.

## Shared with core: set up once

The step numbers are core's. Other docs here refer to them the same way
(for example "`CREDENTIALS.md` step 6").

| Step | What | Done in core |
| --- | --- | --- |
| 1 | Proxmox roles, users and API tokens: `packer`, `terraform`, `ai-agent` | [Proxmox: roles, users, tokens](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#1-proxmox-roles-users-tokens) |
| 2 | HCP Terraform: your user token (`TF_TOKEN_app_terraform_io`), and no token for the AI agent | [HCP Terraform: workspace and tokens](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#2-hcp-terraform-workspace-and-tokens) |
| 4 | Age keys: yours (`~/.config/sops/age/bcochofel.txt`) and the AI agent's (`ai-agent.txt`), none at SOPS's default path | [Age keys](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#4-age-keys) |
| 5 | `~/.secrets/homelab.yaml` (read-write, your key only), `~/.secrets/homelab-ro.yaml` (read-only, also the `ai-agent` key) and `~/.secrets/ai-agent-git.yaml` (the machine user's token, also the `ai-agent` key) | [Secret files](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#5-secret-files) |
| 6 | The AI agent uses only the `ai-agent` key (`.claude/settings.json`) | [The AI agent uses only the `ai-agent` key](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#6-the-ai-agent-uses-only-the-ai-agent-key) |
| 7 | Verify the credentials and the boundary | [Verify the credentials and the boundary](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#7-verify-the-credentials-and-the-boundary) |
| 8 | MCP servers for the AI agent (Proxmox, GitHub, Terraform), `.mcp.json`. The Elasticsearch one is this repo's ([below](#elasticsearch-mcp-ai-agent)) | [MCP servers for the AI agent](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#8-mcp-servers-for-the-ai-agent) |
| 9 | The AI agent's GitHub identity: the machine user `bcochofel-ai-agent` and its token, for both repos (organization side: [`GITHUB.md`](GITHUB.md)) | [The AI agent's GitHub identity](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#9-the-ai-agents-github-identity) |
| 10 | The devcontainer (here: [`DEVCONTAINER.md`](DEVCONTAINER.md)) | [The devcontainer](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#10-the-devcontainer) |

If core is already set up on this machine, there's nothing to redo for
these: the same files and keys work from this repo. Both GitHub tokens
already cover both repos: the read-only one in `homelab-ro.yaml` (the
GitHub MCP server) and the machine user's in `ai-agent-git.yaml`.

## Specific to this repo

Step 3 in core (Cloudflare) is core's own, per-repo secret. Anything like
it here is created for this repo only, so either repo's credentials can be
revoked without touching the other.

### HCP Terraform workspaces

State lives in the same HCP Terraform organization,
`homelab-bcochofel-com`, with **one workspace per stack**, named after the
stack's path (`terramate.tm.hcl`, `hcp_workspace`):

| Stack | Workspace |
| --- | --- |
| `stacks/elastic/infra` | `workloads-elastic-infra` |
| `stacks/otel-demo/infra` | `workloads-otel-demo-infra` |
| `stacks/elastic/cluster` | `workloads-elastic-cluster` |
| `stacks/elastic/fleet` | `workloads-elastic-fleet` |

Create each one as in core's step 2 before its first `tofu:init`:
**CLI-driven**, then *Settings → General → Execution Mode* → **Local**
(Proxmox is LAN-only; HCP only stores state). `tofu init` would otherwise
create a missing workspace with the organization's default execution
mode: check that default is Local (*Organization settings → General →
Default Execution Mode*). The token is the same `TF_TOKEN_app_terraform_io`
from `~/.secrets/homelab.yaml`, and the Proxmox token and cloud-init
password are core's `TF_VAR_proxmox_api_token` and `TF_VAR_cipassword`.
`mise run creds:check` checks the token can read every workspace above.

### Elasticsearch API key (config stacks)

The `config` stacks (ILM, Fleet, Kibana; [`TERRAFORM.md`](TERRAFORM.md))
authenticate with one Elasticsearch API key, which Kibana and Fleet
accept too. It's **yours**, used by OpenTofu when you run
`mise run tofu:plan` / `tofu:apply` on them: read-write, in
`~/.secrets/homelab.yaml` as `ELASTICSEARCH_API_KEY`, never in
`homelab-ro.yaml`. It is **not** the AI agent's key: the agent's Elastic
access (the Elastic MCP) gets its own read-only key.

1. In Kibana, as `elastic`: *Stack Management → API keys → Create API
   key*, name `tofu-config-stacks`, type *User API key*, no expiration, and leave
   *Control security privileges* off: the key then has `elastic`'s own
   privileges, which these stacks need (index templates, ILM, Fleet,
   Kibana spaces).
2. Copy the **Encoded** value (shown once), then add it:

   ```bash
   mise run secrets:edit -- homelab.yaml
   ```

   ```yaml
   ELASTICSEARCH_API_KEY: "<encoded value>"
   ```

3. `mise run creds:check` checks it authenticates against `es-01`.

Revoke it in the same Kibana page; a new key is the same three steps.

### Elasticsearch MCP (AI agent)

The AI agent reads Elasticsearch through `mcp-server-elasticsearch`
(`.mcp.json`, server `elasticsearch`) with its **own read-only** API key,
`ES_API_KEY` in `~/.secrets/homelab-ro.yaml`, the file the `ai-agent` key
opens. Like the other MCP servers, it starts through `sops exec-env`, so
the key exists only in that process.

| Privilege | For the server's tools |
| --- | --- |
| cluster `monitor` | Cluster-level read (health, stats) |
| indices `*`: `read` | `search`, `esql` |
| indices `*`: `view_index_metadata` | `get_mappings` |
| indices `*`: `monitor` | `list_indices`, `get_shards` (the `_cat` APIs) |

Nothing that writes, deletes, or touches security, ILM, templates or
Fleet. Restricted system indices are excluded (`*` doesn't match them).

1. Create the key in Kibana *Dev Tools*, logged in as `elastic`:

   ```text
   POST /_security/api_key
   {
     "name": "ai-agent-elastic-mcp",
     "role_descriptors": {
       "ai-agent-read-only": {
         "cluster": ["monitor"],
         "indices": [
           { "names": ["*"], "privileges": ["read", "view_index_metadata", "monitor"] }
         ]
       }
     },
     "metadata": { "purpose": "Elastic MCP for the AI agent (homelab-proxmox-workloads .mcp.json)" }
   }
   ```

2. Copy the response's `encoded` value and add it to the read-only file:

   ```bash
   mise run secrets:edit -- homelab-ro.yaml
   ```

   ```yaml
   ES_API_KEY: "<encoded value>"
   ```

3. Check it:
   - `mise run creds:check`: the key can list indices (HTTP 200);
   - `mise run boundary:check`, on WSL **and** in the devcontainer: a write
     with it (creating an index) is refused (HTTP 403).

**TLS:** the server has no CA option, only one that skips verification,
which isn't used. Its Elasticsearch client uses the system's OpenSSL,
which honours `SSL_CERT_FILE`: `.mcp.json` sets it to
`ansible/pki/elastic-ca.crt` (from the repository's root), so it trusts the
internal CA and nothing else. It connects to `es-01`
(`https://192.168.68.30:9200`).

### Inventory secrets

Secrets only Ansible uses, for this repo only, go in
`ansible/inventory/group_vars/<group>.sops.yaml` (committed, encrypted).
The repo's `.sops.yaml` encrypts them to your public key only, never to
the `ai-agent` key: a service password or API token has no read-only
form.

Create one from the repo root, where `.sops.yaml` applies; SOPS opens your
editor and encrypts on save:

```bash
sops ansible/inventory/group_vars/<group>.sops.yaml
sops filestatus ansible/inventory/group_vars/<group>.sops.yaml   # {"encrypted":true}
```

Edit it later with your key:

```bash
mise run sops -- ansible/inventory/group_vars/<group>.sops.yaml
```

| File | Keys | Used by |
| --- | --- | --- |
| `all.sops.yaml` (every host) | `elastic_password`, `kibana_system_password`, `kibana_encryption_key`, `logstash_writer_password`, `edot_writer_password`, `remote_monitoring_password` (also read by `stacks/elastic/fleet`) | Elasticsearch, Kibana, Logstash, the EDOT Collector ([`ANSIBLE.md`](ANSIBLE.md#secrets)) |

### The agents' client key

`ansible/pki/agent-client.key.sops` is the key of the client certificate
every Elastic Agent presents to Logstash, encrypted to your key only.
Created by `mise run pki:agent-client`
([`ANSIBLE.md`](ANSIBLE.md#the-agents-client-certificate)).

### Internal CA key

`ansible/pki/elastic-ca.key.sops` is the private key of the CA that signs
every Elastic certificate, encrypted to your key only (`.sops.yaml`).
Create it, and the CA certificate, once with `mise run pki:init`
([`ANSIBLE.md`](ANSIBLE.md#internal-ca)). Ansible decrypts it on your
machine only to sign a host's certificate request; it's never copied to
a VM.

## Checks

The same tasks as in core, run from this repo:

| Task | Checks |
| --- | --- |
| `mise run secrets:check` | Every `~/.secrets` file opens with the right key, and only with it. |
| `mise run creds:check` | Every credential authenticates. Here: the Proxmox tokens, the HCP token (every workspace above), the read-only GitHub token, the machine user's token (push but not admin on both repos), and that each `group_vars/*.sops.yaml` and the CA key open with your key. |
| `mise run boundary:check` | The `ai-agent` key opens `homelab-ro.yaml` and nothing else, including every `group_vars/*.sops.yaml` and the CA key here; `.git/config` runs no code; CODEOWNERS never names the machine user. Run it on WSL and in the devcontainer, where it also proves git and `gh` act as `bcochofel-ai-agent` ([`DEVCONTAINER.md`](DEVCONTAINER.md#prove-the-boundary)). |

All three print `ok`/`FAIL`, never a value.
