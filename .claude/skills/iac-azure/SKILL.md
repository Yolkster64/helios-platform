---
name: iac-azure
description: Infrastructure-as-code conventions for HELIOS — Bicep first (ARM JSON legacy, Terraform interop), Azure AI Foundry deployment parameters, what-if discipline, and Key Vault secret flow. Use when touching infra/, deployment workflows, or any Azure resource definition.
---

# IaC — Azure for HELIOS

**Source of truth**: `infra/main.bicep` + `infra/main.bicepparam`. Modern Foundry
account+project model (`Microsoft.CognitiveServices/accounts@2025-06-01`) — the hub-based
"Foundry classic" model (`MachineLearningServices/workspaces` + capability host) is
deprecated; its parameter mapping lives in `infra/README.md`.

## Bicep rules

- Raw resources over AVM registry modules in this repo — keeps `bicep build` offline and
  deterministic in CI (`infra-validate.yml` needs no subscription).
- Pin api-versions; current pins: accounts/projects/deployments `2025-06-01`,
  Key Vault `2024-11-01`, role assignments `2022-04-01`.
- Stable naming: `uniqueString(resourceGroup().id)` — never `utcNow()` in resource names
  (mints new resources every deploy; the legacy quickstart had this bug).
- Model deployments are data, not resources you hand-edit: the typed
  `additionalModelDeployments` array in `main.bicepparam` is where models are added or
  resized (`{name, modelName?, format?, version, skuName?, capacity?}`); the primary
  quintet (`modelName/modelFormat/modelVersion/modelSkuName/modelCapacity`) is preserved
  for compatibility. Deployments run `@batchSize(1)` — capacity changes race otherwise.
- **Autoscaling**: `capacity` on a `GlobalStandard` deployment is thousands of
  tokens-per-minute. Scale by editing the param and re-deploying (idempotent); no
  resource recreation. Runner autoscaling is separate — ARC `minRunners`/`maxRunners`
  (see GITHUB_ECOSYSTEM_DESIGN.md).
- Secrets: `@secure()` params in, Key Vault secrets out, **never** in outputs, never in
  `.bicepparam` committed values. RBAC-mode vault; grant `Key Vault Secrets User`.

## Workflow discipline

1. `bicep build infra/main.bicep --stdout` locally (or `helios_infra_validate` via MCP).
2. PR → `infra-validate.yml` compiles + lints (offline, always green-able).
3. Merge/dispatch → `helios-deploy.yml`: OIDC login, **what-if on dispatch**, deploy on
   main; skips gracefully when `AZURE_CLIENT_ID` secrets are absent.
4. Never `az deployment group create` from a laptop against prod without a what-if first.

## ARM JSON & Terraform

- ARM JSON is read-only legacy: decompile with `bicep decompile` rather than editing.
- Terraform appears only where a sibling system already uses it; for new HELIOS Azure
  resources, Bicep wins. If Terraform must consume our outputs, read them via
  `azurerm_resource_group_template_deployment` outputs or a data source — do not
  duplicate resource definitions in both tools.

## Which LLM

| Work | Route |
|---|---|
| Reviewing template changes for security/idempotency | `security_analysis` → Claude |
| Generating a new module from a resource spec | `code_generation` → Codex/GPT |
| Explaining a what-if diff | `long_context_analysis` → Claude |

## Reference material

Generic Bicep/Terraform depth lives in `.claude/skills/automation-wiring/references/`;
the files here are the HELIOS layer:

- `references/bicep-tooling.md` — the validation ladder as CI runs it, what-if exit-code
  truth (`--no-pretty-print` for machine-readable gating), the missing-bicepconfig.json
  gap, AVM addressing and why this repo stays raw, deployment stacks as a candidate.
- `references/terraform-azurerm.md` — the validate-only mirror's pins (azurerm `~> 4.0`,
  lockfile at 4.81.0), azurerm 4.x/5.x notes, `plan -detailed-exitcode` as the what-if
  analog, azapi-where-azurerm-falls-short patterns, divergence safety rules.
