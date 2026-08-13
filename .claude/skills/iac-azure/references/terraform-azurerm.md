# Terraform / azurerm — the mirror stack and its provider discipline

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Generic Terraform knowledge (state, backends, module layout, CI discipline) lives in
`.claude/skills/automation-wiring/references/terraform.md`. This file covers the repo's
own Terraform surface: `infra/terraform/`, a **validate-only mirror** of
`infra/main.bicep` — Bicep remains the deployment of record (`main.tf` header comment).

## Pins as the working tree shows them

| What | Value | Source |
|---|---|---|
| `required_version` | `>= 1.3.0` (`optional()` object defaults need it) | `infra/terraform/providers.tf` |
| `hashicorp/azurerm` | `~> 4.0`, locked at **4.81.0** | `providers.tf` + `.terraform.lock.hcl` |
| `azure/azapi` | `~> 2.0`, locked at **2.12.0** | same |
| Backend | none, on purpose — `init -backend=false && validate` must work offline | `providers.tf` comment; `infra-validate.yml` `terraform-validate` job |

**Lockfile commit rule**: `~>` only bounds a range; `.terraform.lock.hcl` is what makes
CI reproducible and it **is committed** (the `infra/terraform/.gitignore` says so
explicitly, while ignoring `.terraform/`, `*.tfstate*`, `*.tfplan`). Refresh deliberately
with `terraform init -upgrade` and review the resulting diff; never delete the lockfile to
"fix" a hash error.

## azurerm 4.x notes (verified via the Learn azurerm version history)

- 4.0.0 (Aug 2024) is a major: deprecated fields/resources removed, behavioral changes —
  read HashiCorp's 4.0 upgrade guide before widening the constraint.
- 4.0 made `subscription_id` effectively required in provider config; **4.35.0
  (Jul 2025) relaxed it** — it may be omitted when `use_cli = true`. This repo's bare
  `provider "azurerm" { features {} }` relies on ambient auth (az login / `ARM_*` env),
  which is fine for `validate` but a `plan`/`apply` needs `ARM_SUBSCRIPTION_ID` set.
- Provider registration control in 4.x is `resource_provider_registrations` (successor to
  3.x `skip_provider_registration`).
- **azurerm 5.x exists** (breaking: registration default flips `legacy`→`none`,
  `skip_provider_registration` removed, ~30 deprecated resources dropped — details in
  automation-wiring's terraform.md). Stay on `~> 4.0` here until the mirror is
  re-validated against 5.x on purpose; it is not a drive-by bump.

## azapi where azurerm falls short (patterns already in main.tf)

- Foundry account / model deployments / project are typed `azapi_resource` blocks pinned
  to `Microsoft.CognitiveServices/...@2025-06-01` — the **same api-version the Bicep
  pins**, which is the point of the mirror. Keep the two in lockstep.
- The fleet VMSS uses azapi because `azurerm_orchestrated_virtual_machine_scale_set`'s
  identity block is UserAssigned-only and cannot express SystemAssigned (comment above
  `azapi_resource.fleet_vmss`).
- `response_export_values` exposes computed properties (endpoint, principalId) for
  outputs.

## plan -detailed-exitcode — the what-if analog

`terraform plan -detailed-exitcode` exits `0` = no changes, `1` = error, `2` = changes
present. This is the change-gating signal `az deployment group what-if` does **not**
provide (see `references/bicep-tooling.md`) — use it when scripting "does this PR touch
infra?" checks. CI today runs only `fmt -check` → `init -backend=false` → `validate`
(`infra-validate.yml`): no plan, because there is no backend and no credentials, and
that's deliberate. If you run plan/apply manually against the mirror, use
**`-parallelism=1`** — Bicep serializes model deployments with `@batchSize(1)` because
parallel creation races on account quota, and Terraform can't express per-resource
batching (comment above `azapi_resource.model_deployment`).

## Divergence and safety rules (main.tf comments — keep them true)

- **Never manage the same deployment from both dialects.** ARM's `uniqueString` hash is
  proprietary; the mirror uses `substr(sha1(...), 0, 13)` — deterministic but DIFFERENT,
  so resource names differ by construction.
- Secret values land in state: `azurerm_key_vault_secret` values are why `*.tfstate*` is
  gitignored; never output them, never commit a plan file.
- `count` cannot derive from a sensitive value — unwrap **emptiness checks only** with
  `nonsensitive(var.x != null && var.x != "")`, never the value itself.
- The principal running Terraform gets a conditional `Key Vault Secrets Officer` grant
  when writing secrets (RBAC-mode vault: Secrets User is read-only; without the grant the
  first apply 403s at the secret step).

## Not in the repo (candidates)

| Mechanism | Adopt when |
|---|---|
| `azurerm` remote backend (with `use_azuread_auth = true`) | The mirror ever graduates to applying real infrastructure — local/no state is only safe while it stays validate-only |
| `tflint` (+ azurerm ruleset) | The mirror grows past a single root module; today `terraform validate` + the Bicep gate cover the drift that matters |
| `terraform test` (`.tftest.hcl`) | Modules gain logic (conditionals beyond the BYO-account short-circuit) worth asserting without a cloud |
| `moved` blocks | Only needed once state exists; note them the first time a resource is renamed post-apply |
