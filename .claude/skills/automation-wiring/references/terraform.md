# Terraform Reference

Aug 2026: Terraform CLI **1.15.8** (1.14.x still supported); `hashicorp/azurerm` **5.0.1**, latest 4.x **4.81.0**.

## Contents

- [Module layout](#module-layout) · [Version pinning](#version-pinning) · [State](#state-and-backends) · [for_each vs count](#for_each-vs-count) · [moved](#moved-blocks) · [Data sources](#data-sources-vs-resources)
- [Importing](#importing-existing-infra) · [Lifecycle](#lifecycle) · [Sensitive values](#sensitive-values) · [azurerm](#azurerm-provider-specifics) · [CI](#ci-discipline) · [Bicep interop](#interop-with-bicep) · [Tooling](#commands-and-linting)

## Module layout

`infra/envs/{dev,prod}/` — a ROOT module per environment (`main.tf backend.tf terraform.tfvars`);
`infra/modules/network/` — reusable child (`main.tf variables.tf outputs.tf versions.tf`).

`versions.tf` holds the `terraform {}` block only. `variables.tf` gives every input a `description`
and `type`, with **no `default` on anything environment-specific** — a missing value should fail, not
silently pick dev. `outputs.tf` is the module's public contract, so renames are breaking. Child
modules must not declare `provider` blocks or backends: a `provider` inside a module makes the module
impossible to remove cleanly, since Terraform requires that config to exist while resources remain.

## Version pinning

```hcl
terraform {
  required_version = ">= 1.14.0, < 2.0.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # >=5.0, <6.0
  }
}
```

`~> 5.0` pins the major; `~> 5.0.1` pins the patch (>=5.0.1, <5.1.0); `source` is mandatory.
**Commit `.terraform.lock.hcl`** — it is what makes builds reproducible, since `~>` only bounds a
range. Refresh deliberately with `init -upgrade` and review the diff. If devs and CI differ in OS run
`terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`, or CI fails on a missing hash.

### azurerm 5.0 breaking changes

`resource_provider_registrations` defaults to **`none`** (was `legacy`, which auto-registered ~60
RPs), so 4.x→5.x on a fresh subscription fails "resource provider not registered" until you set
`"legacy"` or list `resource_providers_to_register`; `skip_provider_registration` is **removed**.
~30 deprecated resources are gone (`azurerm_app_service`, `azurerm_function_app` — use the
`linux_`/`windows_` variants — and PostgreSQL single-server), plus widespread `enable_*` → `*_enabled`
renames. New `features` option `preflight_enabled` runs the Azure Preflight Validation API during
`plan`, surfacing policy violations and quota breaches early. Read the official upgrade guide first.

## State and backends

```hcl
backend "azurerm" {                # values cannot be interpolated — use -backend-config
  resource_group_name  = "rg-tfstate"
  storage_account_name = "sthelistfstate"
  container_name       = "tfstate"
  key                  = "dev/aihub.tfstate"   # unique per root module per env
  use_azuread_auth     = true                  # RBAC instead of storage account keys
}
```

- **Local state is a footgun:** one laptop, no locking (two applies corrupt it), no backup, secrets
  in plaintext. The first local apply against shared infra is the one that gets lost.
- The azurerm backend locks via a **blob lease**; a killed apply leaves it held, and `terraform
  force-unlock <LOCK_ID>` releases it — only after confirming nothing is running. Enable **versioning
  and soft delete** on the container: corruption is recoverable only if you did so beforehand.
- **Prefer a directory per environment over workspaces.** Workspaces share one backend key, provider
  config and variable set, so environments differ only by scattered `terraform.workspace`
  conditionals — and a wrong `workspace select` applies dev's plan to prod with nothing visible in
  the command. Directories give distinct state keys, tfvars, CI jobs and approval gates.

## for_each vs count

```hcl
resource "azurerm_storage_account" "sa" {   # SAFE — identity-keyed: addresses are sa["a"],
  for_each = toset(var.names)               # sa["b"], so removing "a" destroys exactly one.
  name     = each.value                     # With count/count.index instead, removing
}                                           # names[0] reindexes and RECREATES ALL of them.
```

Use `count` only for an on/off toggle (`count = var.enabled ? 1 : 0`) — and even then
`for_each = var.enabled ? toset(["default"]) : toset([])` avoids `[0]` in every downstream reference.
`for_each` keys must be known at **plan** time; keying by a not-yet-created resource's ID gives "The
for_each value depends on resource attributes that cannot be determined until apply." Key by a static
name and look the ID up inside the body.

## moved blocks

```hcl
moved {
  from = azurerm_storage_account.sa[0]        # count index -> for_each key
  to   = azurerm_storage_account.sa["primary"]
}
```

Commit `moved` blocks instead of running `terraform state mv` by hand: they are reviewable, run in CI,
and work for everyone who pulls. They become no-ops once every state has migrated, so leaving them
costs nothing; the same block moves a resource into a module (`to = module.sec.azurerm_key_vault.kv`).
`removed` blocks (1.7+) do the inverse — drop a resource from state without destroying it.

## Data sources vs resources

```hcl
data "azurerm_key_vault" "shared" {          # read-only; another config owns it
  name                = var.shared_kv_name
  resource_group_name = var.shared_rg
}
```

(`data "azurerm_client_config" "current" {}` gives the caller's `tenant_id` and `object_id`.)
**Exactly one configuration `resource`-owns any given Azure resource; everything else reads it as
`data`.** Two configs declaring the same resource fight, each apply reverting the other's drift. Data
sources resolve during plan and fail it if absent — a missing prerequisite surfaces before creation.

## Importing existing infra

The `import` block (1.5+) is declarative, reviewable, and plannable. Prefer it to `terraform import`.

```hcl
import {
  to = azurerm_resource_group.main
  id = "/subscriptions/0000.../resourceGroups/rg-helios-dev"
}
```

```bash
terraform plan -generate-config-out=generated.tf   # scaffolds the resource block
terraform apply                                    # imports; then delete the import block
terraform import 'azurerm_storage_account.sa["primary"]' /subscriptions/.../st   # legacy
```

Either way the import succeeds and **the next plan tells you the truth**. Expect a diff — your HCL
almost never matches reality (policy-added tags, default SKU fields, `min_tls_version`). Reconcile it
*before* applying, or the first apply after import silently rewrites live configuration.

## Lifecycle

```hcl
lifecycle {
  prevent_destroy       = true                 # apply ERRORS if the plan would destroy this
  ignore_changes        = [tags["CreatedBy"]]  # set by policy, not by us
  create_before_destroy = true
  precondition {                               # fail the plan, not the deploy
    condition     = var.env != "prod" || var.enable_purge_protection
    error_message = "Purge protection is mandatory in prod."
  }
}
```

`prevent_destroy` cannot be overridden by a flag — you must edit the code, which is the point; put it
on state storage, prod key vaults, and databases. `ignore_changes = all` hides real drift, so list
fields. `create_before_destroy` fails for globally-unique names (storage accounts, key vaults) unless
the name is derived from something that changes too.

## Sensitive values

Mark the variable **and every output derived from it** `sensitive = true`, give it no `default`, and
supply the value through `TF_VAR_admin_password`. Then understand the limit:

**`sensitive = true` only redacts CLI output. The value is stored in state as plaintext.** This is
the most misunderstood thing about Terraform. State also captures secrets you never declared —
storage keys, generated passwords, certificate private keys — every attribute the provider reads back.

- Treat state as a secret store: encrypt the backend, restrict container RBAC to the deploy identity
  plus break-glass, log reads. Never commit state or pipe `terraform show -json` into CI logs.
- Prefer `azurerm_key_vault_secret` references and managed identity: if Terraform never sees the
  value, state never holds it. `nonsensitive()` should raise an eyebrow in review every time.
- Feed secrets via `TF_VAR_*` env vars, not `.tfvars` files (paths reach shell history and CI logs):
  `export TF_VAR_admin_password="$(az keyvault secret show --vault-name kv -n pw --query value -o tsv)"`

## azurerm provider specifics

```hcl
provider "azurerm" {
  subscription_id = var.subscription_id     # REQUIRED since 4.0 (or ARM_SUBSCRIPTION_ID)
  resource_provider_registrations = "core"  # 5.x defaults to "none"
  features {                                # mandatory, appears EXACTLY ONCE; may be empty
    key_vault { recover_soft_deleted_key_vaults = true }
    resource_group { prevent_deletion_if_contains_resources = true }
  }
}
```

Omitting `features` errors as `Insufficient features blocks` — the block is missing, not a flag wrong.
Auth order: explicit args → env vars → Azure CLI → managed identity. `ARM_SUBSCRIPTION_ID` is required
from 4.0; `ARM_TENANT_ID`/`ARM_CLIENT_ID` name the tenant and app/UAMI; **`ARM_USE_OIDC=true` uses
GitHub's OIDC token with no client secret** (`ARM_OIDC_REQUEST_URL`/`_TOKEN` are auto-populated in
Actions); `ARM_USE_MSI=true` suits an Azure-hosted runner; `ARM_CLIENT_SECRET` is a fallback to avoid.
In Actions grant `id-token: write`, set those as job `env:`, and pin the setup action:

```yaml
  - uses: hashicorp/setup-terraform@v3
    with: { terraform_version: 1.15.8, terraform_wrapper: false }
```

`terraform_wrapper: false` matters — the wrapper mangles exit codes and stdout, breaking
`plan -detailed-exitcode` and any output parsing. The **backend authenticates separately** from the
provider: add `use_oidc = true` (or `use_azuread_auth = true`) to the `backend` block; OIDC env vars
alone do not always reach it.

## CI discipline

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate    # validate without touching state
terraform init && terraform plan -out=tfplan -input=false -lock-timeout=5m
terraform show -no-color tfplan > plan.txt             # post as a PR comment
terraform apply -input=false tfplan                    # on merge only
```

- **Apply the saved plan file; never re-plan at apply time** — otherwise what a human approved is not
  what gets applied. Pass `tfplan` as an artifact between the plan and apply jobs; it is
  state-adjacent and contains secrets, so use short retention and never a public run.
- **Never auto-apply on a PR.** Plan on PR (read-only creds if possible), apply on merge, behind a
  GitHub environment with required reviewers for prod. `-input=false` everywhere; an interactive
  prompt in CI is a six-hour hang.
- `plan -detailed-exitcode`: `0` no changes, `1` error, `2` changes — drives "does this PR touch infra?"

## Interop with Bicep

**One owner per resource.** Never declare the same Azure resource in both. Two patterns work.
**(1) Terraform owns everything**, invoking Bicep as a unit via
`azurerm_resource_group_template_deployment` (fed the ARM JSON from `bicep build`), then
`jsondecode(output_content)` — fragile, because the deployment is opaque to `plan`. **(2) Split by
layer, connect via data sources** — Bicep owns the Azure-native app platform (AI Foundry accounts,
model deployments, App Service config), Terraform owns networking, identity and shared platform.

```hcl
data "azurerm_cognitive_account" "foundry" {     # read only, never manage
  name                = var.foundry_account_name
  resource_group_name = var.foundry_rg
}
```

Hand the Bicep side's outputs over explicitly: `export TF_VAR_foundry_account_id=$(az deployment group
show -g "$RG" -n "$DEPLOY" --query properties.outputs.foundryAccountId.value -o tsv)`. Symptoms of a
double-owned resource: alternating diffs, tags appearing and disappearing, `plan` never reaching "no
changes". Stop and decide the owner before writing more code.

## Commands and linting

```bash
terraform init -upgrade                  # refresh within constraints; review the lock diff
terraform plan -target=module.network    # emergency only; leaves state inconsistent
terraform state list ; terraform state show <addr> ; terraform force-unlock <LOCK_ID>
terraform output -json | jq -r '.kv_uri.value' ; terraform console
```

**`tflint`** with the azurerm ruleset catches invalid SKUs, deprecated arguments, and unused
declarations that `validate` accepts. Run **`checkov`** or **`tfsec`** (now inside Trivy) against the
**plan JSON** (`terraform show -json tfplan`), not the HCL — scanning HCL misses anything computed
from variables. **`terraform-docs`** builds module READMEs from `variables.tf`/`outputs.tf`; run in CI.
