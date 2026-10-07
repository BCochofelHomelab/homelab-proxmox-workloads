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
| 5 | `~/.secrets/homelab.yaml` (read-write, your key only) and `~/.secrets/homelab-ro.yaml` (read-only, also the `ai-agent` key) | [Secret files](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#5-secret-files) |
| 6 | The AI agent uses only the `ai-agent` key (`.claude/settings.json`) | [The AI agent uses only the `ai-agent` key](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#6-the-ai-agent-uses-only-the-ai-agent-key) |
| 7 | Verify the credentials and the boundary | [Verify the credentials and the boundary](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#7-verify-the-credentials-and-the-boundary) |
| 8 | MCP servers for the AI agent (Proxmox, GitHub, Terraform), `.mcp.json` | [MCP servers for the AI agent](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#8-mcp-servers-for-the-ai-agent) |
| 9 | The devcontainer (here: [`DEVCONTAINER.md`](DEVCONTAINER.md)) | [The devcontainer](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/CREDENTIALS.md#9-the-devcontainer) |

If core is already set up on this machine, there's nothing to redo for
these: the same files and keys work from this repo, and the GitHub PAT in
`homelab-ro.yaml` already covers both repos.

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

Create each one as in core's step 2 before its first `tofu:init`:
**CLI-driven**, then *Settings → General → Execution Mode* → **Local**
(Proxmox is LAN-only; HCP only stores state). `tofu init` would otherwise
create a missing workspace with the organization's default execution
mode, which is Remote. The token is the same `TF_TOKEN_app_terraform_io`
from `~/.secrets/homelab.yaml`, and the Proxmox token and cloud-init
password are core's `TF_VAR_proxmox_api_token` and `TF_VAR_cipassword`.
`mise run creds:check` checks the token can read every workspace above.

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
| `elastic.sops.yaml` (group `elastic`) | `elastic_password` | Elasticsearch ([`ANSIBLE.md`](ANSIBLE.md#secrets)); later Kibana and Logstash add theirs |

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
| `mise run secrets:check` | Both `~/.secrets` files open with the right key, and only with it. |
| `mise run creds:check` | Every credential authenticates. Here: the Proxmox tokens, the HCP token (every workspace above), the GitHub PAT, and that each `group_vars/*.sops.yaml` and the CA key open with your key. |
| `mise run boundary:check` | The `ai-agent` key opens `homelab-ro.yaml` and nothing else, including every `group_vars/*.sops.yaml` and the CA key here. Run it on WSL and in the devcontainer. |

All three print `ok`/`FAIL`, never a value.
