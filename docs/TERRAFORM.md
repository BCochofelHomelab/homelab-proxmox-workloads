# Terraform — OpenTofu stacks with Terramate

[OpenTofu](https://opentofu.org) clones the Packer template
(`ubuntu-26.04-workloads`, VM 9001) into the workloads' VMs and writes
each stack's Ansible inventory. [Terramate](https://terramate.io) splits
the code into **stacks**, each with its own state, so a change to one
workload never plans or applies another.

Decoupled from Ansible by design: apply a stack, then run the Ansible
playbooks separately (no `local-exec` chaining). Always plan and review
before applying; never `destroy` from a task.

## Stacks

| Stack | Tags | VMs (IP) | Ansible inventory |
| --- | --- | --- | --- |
| `stacks/elastic/infra` | `infra`, `elastic` | `es-01`..`es-03` (`.30`–`.32`), `kibana` (`.33`), `ingest` (`.34`) | `ansible/inventory/elastic.ini` |
| `stacks/otel-demo/infra` | `infra`, `otel-demo` | `otel-demo` (`.35`) | `ansible/inventory/otel-demo.ini` |

All IPs are in `192.168.68.0/22`; `.30`–`.39` is reserved for the Elastic
stack and its demo workloads.

| VM | vCPU | RAM | OS disk | Data disk | Ansible groups |
| --- | --- | --- | --- | --- | --- |
| `es-01`, `es-02`, `es-03` | 2 | 8 GB | 50 GB | 200 GB | `elasticsearch` |
| `kibana` | 2 | 4 GB | 50 GB | — | `kibana_server`, `fleet_server` |
| `ingest` | 2 | 4 GB | 50 GB | 50 GB | `logstash`, `edot_gateway` |
| `otel-demo` | 2 | 6 GB | 50 GB | — | `otel_demo` |

Each stack's VMs are a `nodes` map in its `main.tf`: add or resize a VM
there. The data disk (`scsi1`) is created empty; Ansible formats and
mounts it where the role keeps its data.

**Lifecycles.** The `infra` stacks hold VMs, which rarely change. Elastic
configuration that changes often (ILM, Fleet policies and outputs, Kibana
spaces and dashboards) will live in separate `config` stacks under
`stacks/elastic/` (for example `stacks/elastic/fleet`), applied after
Ansible has installed the stack. Logstash pipelines are files deployed by
Ansible, not OpenTofu: managing them through Elasticsearch needs
centralized pipeline management, a paid subscription feature.

## Layout and generated code

```text
terramate.tm.hcl        # project config and globals (non-secret shared inputs)
stacks/
  infra.tm.hcl          # code generated into every stack tagged "infra"
  elastic/infra/        # stack.tm.hcl, main.tf, outputs.tf, templates/
  otel-demo/infra/
modules/vm/             # one VM: clone, cloud-init, optional data disk
```

`stacks/infra.tm.hcl` generates two files into each `infra` stack,
from the globals in `terramate.tm.hcl`:

- `_terramate_generated_backend.tf`: provider requirements and the
  HCP Terraform `cloud {}` block with the stack's workspace;
- `_terramate_generated_proxmox.tf`: the `proxmox` provider, the secret
  variables, the shared non-secret inputs as locals, and the template's
  VMID looked up by name.

Never edit a `_terramate_generated_*.tf` file: change the `.tm.hcl`
source and run `terramate generate` (the pre-commit hook does it too, and
fails until the regenerated files are staged).

A new stack: `terramate create stacks/<workload>/infra --tags infra,<workload>`,
then a `main.tf` with its `nodes` and inventory (copy an existing stack),
then `terramate generate`, and create its HCP workspace (below).

## Engine: OpenTofu with HCP Terraform state

- **State:** HCP Terraform organization `homelab-bcochofel-com`, one
  workspace per stack, named after its path:
  `stacks/elastic/infra` → `workloads-elastic-infra`. Create each
  workspace as **CLI-driven** with *Execution Mode* **Local** before its
  first `tofu:init` ([`CREDENTIALS.md`](CREDENTIALS.md)): Proxmox is
  LAN-only, so HCP only stores state.
- **Auth:** `TF_TOKEN_app_terraform_io`, your user token from
  `~/.secrets/homelab.yaml`, passed by the `tofu:*` tasks. The AI agent
  has no HCP token, so it only runs `tofu init -backend=false`,
  `tofu validate` and the linters. Don't keep a
  `~/.terraform.d/credentials.tfrc.json`: it's an ambient read-write
  credential.
- **Providers:** `bpg/proxmox` (`~> 0.116.0`) and `hashicorp/local`,
  recorded per stack in `.terraform.lock.hcl` as `registry.opentofu.org`
  entries. Bump with `tofu init -upgrade` in each stack. Core is on
  `0.111.x`; the two repos don't share state, so they can differ.
- **pre-commit uses `tofu`**: `--hook-config=--tf-path=tofu` on the
  Terraform hooks, so commits from a shell without `mise activate` don't
  fall back to `terraform` and rewrite the lock files.
- **Rollback path:** `terraform` stays pinned in `mise.toml`, as in core.

## Running it

```bash
mise run tofu:init                                # every infra stack
mise run tofu:plan                                # saves <stack>/tfplan
mise run tofu:apply                               # applies those plans

mise run tofu:plan -- stacks/elastic/infra        # one stack
mise run tofu:plan -- --tags config               # the config stacks
```

Each task runs `terramate run` inside `sops exec-env`, so the secrets
exist only in that process. Stacks run one at a time, in dependency
order, and the run stops at the first failure. `tofu:apply` applies each
stack's saved `tfplan`, exactly the plan you reviewed: no confirmation
prompt, and `tofu` refuses a plan that's stale against the state (plan
again). `tfplan` files are gitignored, since they can hold sensitive
values.

Terramate's safeguards against uncommitted and untracked files are off
(`terramate.tm.hcl`), so you can plan on a branch before committing.

For a one-off flag, run the underlying command with your key:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/bcochofel.txt sops exec-env ~/.secrets/homelab.yaml \
  'terramate -C stacks/elastic/infra run -- tofu plan -target=module.vm["es-01"]'
```

## Configuration and secrets

| What | Where |
| --- | --- |
| Proxmox endpoint, node, template; gateway, bridge, nameservers, search domain; cloud-init user; SSH **public** keys | Globals in `terramate.tm.hcl`, committed. Nothing secret: change them there and regenerate. |
| VM names, IPs, sizing, Ansible groups | Each stack's `main.tf` (`nodes`) |
| `TF_VAR_proxmox_api_token` (`terraform@pve!terraform`), `TF_VAR_cipassword`, `TF_TOKEN_app_terraform_io` | `~/.secrets/homelab.yaml`, passed by the `tofu:*` tasks ([`CREDENTIALS.md`](CREDENTIALS.md)) |

There's no `terraform.tfvars`: with several stacks it would need one copy
per stack. The VMs resolve against CoreDNS primary and secondary
(`192.168.68.2`, `.3`, from core); Pihole isn't in their resolver list.

## Proxmox privileges

`tofu apply` authenticates as `terraform@pve!terraform`, with core's
`TofuApply` role: the same identity and token as core
([`CREDENTIALS.md`](CREDENTIALS.md) step 1). This table explains its
privileges.

| Privilege | Why OpenTofu needs it |
| --- | --- |
| `VM.Allocate` | Required on the *destination* VMID for a clone: Proxmox's clone endpoint checks `VM.Clone` on the source template but `VM.Allocate` on the new VMID. A `VM.Clone`-only role fails the clone with a 403. |
| `VM.Audit` | Look up the template's VMID by name, read VM state |
| `VM.Clone` | Read/export permission on the *source* template |
| `VM.Config.CDROM` | bpg's `initialization` block reconfigures the cloud-init drive, which Proxmox checks under the CD-ROM permission |
| `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Network` | Set cores and memory, resize the cloned disk, add the data disk, attach the network device |
| `VM.Config.Cloudinit` | Write the static IP, DNS and cloud-init user |
| `VM.Config.Options` | Set description and tags |
| `VM.PowerMgmt` | Start the clone |
| `VM.GuestAgent.Audit` | Read-only guest agent commands |
| `Datastore.Allocate`, `Datastore.AllocateSpace` | Allocate the disks and cloud-init drive on `local-lvm` |
| `Datastore.Audit` | Read storage info |
| `SDN.Use` | Attach the NIC to `vmbr0` once the bridge is an SDN zone |

## Security checks and policy enforcement

Everything under `stacks/` and `modules/` is scanned by TFLint, Trivy and
Checkov on each commit and in CI (see
[`CONTRIBUTING.md`](../CONTRIBUTING.md)). Neither Trivy nor Checkov ships
checks for `bpg/proxmox`, so Proxmox-specific checks are custom, under
`policies/` (ported from core):

- `policies/checkov/proxmox_*.yaml`: UEFI firmware (MEDIUM, skip-listed
  in `checkov.yaml` until the module sets `bios = "ovmf"` and an
  `efi_disk`), guest agent enabled (MEDIUM), a `description` (LOW) and the
  `q35` machine type (LOW). Only MEDIUM and above are enforced
  (`checkov.yaml`).
- `policies/trivy/proxmox_*.rego`: the same intent as Trivy Rego checks,
  plus no hardcoded `api_token` and no `insecure = true`. They haven't
  been shown to fire with Trivy 0.72.0 (see core's
  [`TERRAFORM.md`](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/TERRAFORM.md#security-checks-and-policy-enforcement));
  Checkov is the enforcing gate.

The `terraform_checkov` hook gets an absolute `--external-checks-dir`,
because the hook `cd`s into each changed directory before running.
