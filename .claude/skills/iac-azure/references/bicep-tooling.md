# Bicep tooling — validation, what-if truth, and the linter gap

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Generic Bicep language/authoring knowledge lives in
`.claude/skills/automation-wiring/references/bicep-arm.md`. This file covers the
toolchain as THIS repo runs it, plus verified facts about the commands it depends on.

## The validation ladder (cheapest first)

| Step | Command | Where it runs |
|---|---|---|
| 1. Compile + lint (offline) | `az bicep install && az bicep build --file infra/main.bicep --stdout` and `az bicep build-params --file infra/main.bicepparam --stdout` | `infra-validate.yml`, local, MCP `helios_infra_validate` |
| 2. ARM-mirror freshness | recompile, canonical-JSON compare against `infra/arm/main.json` | `infra-validate.yml` `arm-freshness` job |
| 3. Preflight validate (needs auth) | `az deployment group validate` | manual only — deliberately NOT in `infra-validate.yml`, which must stay fork/PR-deterministic |
| 4. what-if (needs auth) | `az deployment group what-if -g rg-helios-ai --template-file infra/main.bicep --parameters infra/main.bicepparam` | `helios-deploy.yml` dispatch (default `what_if: true`) |
| 5. Deploy | `az deployment group create …` | `helios-deploy.yml` on main push, or dispatch with `what_if: false` |

The ARM mirror gate strips `metadata._generator` recursively before comparing, so a Bicep
CLI version bump alone never turns it red; when `main.bicep` changes, regenerate with
`bicep build infra/main.bicep --outfile infra/arm/main.json` and commit.

## what-if exit-code truth

Verified against the `az deployment group what-if` reference (Microsoft Learn):

- The exit code reflects **command success only**. There is no exit-code signal for
  "changes detected" — no analog of `terraform plan -detailed-exitcode`. A green what-if
  step means the command ran, not that the stack is unchanged.
- To gate or report on changes programmatically, pass **`--no-pretty-print`** and parse
  the JSON (the documented way to "programmatically inspect for changes"); the
  human-readable default is for eyes only.
- Useful switches: `--result-format ResourceIdOnly` (terse PR-comment form),
  `--exclude-change-types` (filter e.g. `NoChange Ignore`), `--confirm-with-what-if`/`-c`
  on `az deployment group create` (interactive gate — not for CI).
- `--validation-level` (CLI ≥ 2.76.0): `Provider` (full, needs deploy permissions),
  `ProviderNoRbac` (full validation, read permissions only — the right level for
  restricted CI identities), `Template` (static only, skips preflight).
- `Modify` noise is normal (provider-computed properties); `Delete` entries are reliable,
  their absence is not proof — what-if is a prediction (automation-wiring's bicep-arm.md
  covers interpretation in depth).

## bicepconfig.json — honest gap

The repo has **no `bicepconfig.json`**, so `az bicep build` runs default linter levels:
most rules are warnings and only compile errors fail step 1. That means
`secure-parameter-default` or `outputs-should-not-contain-secrets` violations would pass
CI today; the protection is convention (`@secure()` params in, never in outputs —
SKILL.md) plus review. Candidate: commit a `bicepconfig.json` next to `infra/main.bicep`
raising the security rules to `error` (rule block in automation-wiring's bicep-arm.md,
"Validation"). Leave `use-recent-api-versions` at `warning` — this repo pins api-versions
deliberately (SKILL.md pin list) and that rule would nag every pinned resource.

## AVM — addressing, and why this repo stays raw

Azure Verified Modules are addressed
`br/public:avm/res/<service>/<resource>:<exact-version>` (e.g.
`br/public:avm/res/key-vault/vault:0.13.0`) — always an exact version, never floating.
This repo deliberately uses **raw resources** instead (`infra/main.bicep`,
`infra/modules/*.bicep`): AVM restores from MCR at build time, which would break
`infra-validate.yml`'s offline determinism and add a registry dependency to every PR.
Adopt AVM only for genuinely new resource families where curated RBAC/private-endpoint
wiring outweighs that (and then vendor or cache the module for CI). Do not rewrite the
existing Foundry/Key Vault/VMSS modules onto AVM — the Terraform mirror
(`infra/terraform/main.tf`) tracks their exact shapes.

## Not in the repo (candidates)

- **Deployment stacks** (`az stack group create --template-file … --action-on-unmanage
  deleteResources|deleteAll|detachAll --deny-settings-mode none|denyDelete|…`, CLI ≥
  2.61.0; verified via Learn). Plain deployments never delete removed resources; stacks
  do, and can deny out-of-band edits/deletes. Adopt if `infra/main.bicep` starts shedding
  resources routinely (today's stack is additive) — and note what-if for stacks is its
  own command family (`az stack-whatif group show`). Deleting via
  `--action-on-unmanage deleteAll` removes managed resource groups wholesale; start with
  `deleteResources`.
- **Template specs** — publish/version `main.bicep` for consumption outside the repo; no
  current consumer.
- **PSRule for Azure** — policy-as-tests over compiled ARM; adopt when a compliance
  requirement names specific baselines, not before (another registry/module dependency).
