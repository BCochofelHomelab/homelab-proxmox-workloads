# GitHub

The `BCochofelHomelab` organization and both of its repositories are set
up and documented in one place, core's
[`docs/GITHUB.md`](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/GITHUB.md): the organization settings,
the `sre-team` and `sre-lead` teams, the per-repository rulesets, the AI
agent's machine user and its token, the GitHub CLI, and the
[red button](https://github.com/BCochofelHomelab/homelab-proxmox-core/blob/main/docs/GITHUB.md#red-button-stopping-the-ai-agent)
that stops the AI agent. A change to any of them is recorded there.

This repository follows it exactly:

- **Rulesets:** its own `protected-default` (pull request, one code-owner
  approval, admin bypass for pull requests only) and `protected-tags`,
  configured as described there.
- **CODEOWNERS:** [`.github/CODEOWNERS`](../.github/CODEOWNERS) assigns
  every file to `@BCochofelHomelab/sre-lead`. Never `sre-team`: the
  machine user is in it, so its approval would count.
- **The machine user:** `bcochofel-ai-agent` has Write here through
  `sre-team`, with the same token as in core. It's used only in this
  repo's devcontainer ([`DEVCONTAINER.md`](DEVCONTAINER.md)).
