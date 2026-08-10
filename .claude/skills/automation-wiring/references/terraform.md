# Terraform Reference

Aug 2026: Terraform CLI **1.15.8** (1.14.x still supported). `hashicorp/azurerm` **5.0.1**;
latest 4.x is **4.81.0**.

## Contents

- [Module layout](#module-layout) · [Version pinning](#version-pinning) · [State and backends](#state-and-backends)
- [for_each vs count](#for_each-vs-count) · [moved blocks](#moved-blocks) · [Data sources](#data-sources-vs-resources)
- [Importing](#importing-existing-infra) · [Lifecycle](#lifecycle) · [Sensitive values](#sensitive-values)
- [azurerm specifics](#azurerm-provider-specifics) · [CI discipline](#ci-discipline) · [Bicep interop](#interop-with-bicep) · [Tooling](#commands-and-linting)

## Module layout

```
infra/
  envs/dev/   main.tf backend.tf terraform.tfvars    # a ROOT module per environment
  envs/prod/  main.tf backend.tf terraform.tfvars
  modules/network/  main.tf variables.tf outputs.tf versions.tf
```

- `versions.tf` — `terraform {}` only: `required_version`, `required_providers`.
- `variables.tf` — every input with `description` and `type`. No `default` on anything
  environment-specific; a missing value should fail, not silently pick dev.
- `outputs.tf` — the module's public contract. Renames are breaking changes.

Child modules must not declare `provider` blocks or backends. A `provider` inside a module
makes the module impossible to remove cleanly — Terraform requires the provider config to
exist while its resources remain in state.

## Version pinning

```hcl
terraform {
  required_version = ">= 1.14.0, < 2.0.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # >=5.0, <6.0
    azapi   = { source = "Azure/azapi",       version = "~> 2.0" }
  }
}
```

`~> 5.0` pins the major; `~> 5.0.1` pins the patch (>=5.0.1, <5.1.0). `source` is mandatory.

**Commit `.terraform.lock.hcl`** — it is what makes builds reproducible; `~>` only bounds a
range. Refresh deliberately with `init -upgrade` and review the diff. If devs and CI differ
in OS, run `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` or CI
fails on a missing hash.

### azurerm 5.0 breaking changes

- `resource_provider_registrations` now defaults to **`none`** (was `legacy`, which
  auto-registered ~60 RPs). Upgrading 4.x→5.x on a fresh subscription fails with "resource
  provider not registered" until you set `"legacy"` or list `resource_providers_to_register`.
- `skip_provider_registration` is **removed**.
- ~30 deprecated resources removed: `azurerm_app_service`, `azurerm_function_app` (use the
  `linux_`/`windows_` variants), the PostgreSQL single-server family.
- Widespread renames: `enable_*` → `*_enabled`.
- New `features` option `preflight_enabled` calls the Azure Preflight Validation API during
  `plan`, surfacing policy violations and quota breaches before apply. Worth enabling.

Read the official 5.0 upgrade guide before bumping a live stack; that is a summary.

## State and backends

```hcl
terraform {
  backend "azurerm" {              # values cannot be interpolated — use -backend-config
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sthelistfstate"
    container_name       = "tfstate"
    key                  = "dev/aihub.tfstate"   # unique per root module per env
    use_azuread_auth     = true                  # RBAC instead of storage account keys
  }
}
```

- **Local state is a footgun.** One laptop, no locking (two applies corrupt it), no backup,
  secrets in plaintext. The first local apply against shared infra is the one that gets lost.
- The azurerm backend locks via a **blob lease**. A killed apply leaves it held;
  `terraform force-unlock <LOCK_ID>` releases it — only after confirming nothing is running.
- Enable **versioning and soft delete** on the state container. Corruption is recoverable
  if and only if you did this beforehand.

**Prefer a directory per environment over workspaces.** Workspaces share one backend key,
one provider config and one variable set, so environments differ only by scattered
`terraform.workspace` conditionals — and a wrong `workspace select` applies dev's plan to
prod with no visible difference in the command. Directories give distinct state keys, tfvars,
CI jobs, and approval gates. Workspaces are fine for ephemeral per-PR stacks.

## for_each vs count

```hcl
resource "azurerm_storage_account" "sa" {     # FRAGILE — index-keyed
  count = length(var.names)
  name  = var.names[count.index]
}
# removing names[0] shifts every index: Terraform destroys and recreates ALL of them.

resource "azurerm_storage_account" "sa" {     # SAFE — identity-keyed
  for_each = toset(var.names)
  name     = each.value
}
# addresses are sa["a"], sa["b"]; removing "a" destroys exactly one resource.
```

Use `count` only for an on/off toggle (`count = var.enabled ? 1 : 0`) — and even then
`for_each = var.enabled ? toset(["default"]) : toset([])` avoids `[0]` in every downstream
reference.

`for_each` keys must be known at **plan** time. Keying by a not-yet-created resource's ID
gives "The for_each value depends on resource attributes that cannot be determined until
apply." Key by a static name and look the ID up inside the body.

## moved blocks

Refactor without destroying. Commit these instead of running `terraform state mv` by hand —
they are reviewable, run in CI, and work for everyone who pulls.

```hcl
moved { from = azurerm_storage_account.sa[0]  to = azurerm_storage_account.sa["primary"] }
moved { from = azurerm_key_vault.kv           to = module.security.azurerm_key_vault.kv }
```

They become no-ops once every state has migrated; leaving them costs nothing. `removed`
blocks (1.7+) do the inverse — drop a resource from state without destroying it.

## Data sources vs resources

```hcl
data "azurerm_key_vault" "shared" {          # read-only; another config owns it
  name                = var.shared_kv_name
  resource_group_name = var.shared_rg
}
data "azurerm_client_config" "current" {}    # tenant_id, object_id of the caller
```

**Exactly one configuration `resource`-owns any given Azure resource; everything else reads
it as `data`.** Two configs declaring the same resource fight, each apply reverting the
other's drift. Data sources resolve during plan and fail the plan if absent — a feature: a
missing prerequisite surfaces before anything is created.

## Importing existing infra

The `import` block (1.5+) is declarative, reviewable, and plannable. Prefer it.

```hcl
import {
  to = azurerm_resource_group.main
  id = "/subscriptions/0000.../resourceGroups/rg-helios-dev"
}
resource "azurerm_resource_group" "main" { name = "rg-helios-dev", location = "eastus" }
```

```bash
terraform plan -generate-config-out=generated.tf   # scaffolds the resource block
terraform apply                                    # performs the import; then delete the block
terraform import 'azurerm_storage_account.sa["primary"]' /subscriptions/.../sthelios  # legacy form
```

Either way the import succeeds and **the next plan tells you the truth**. Expect a diff —
your HCL almost never matches reality (policy-added tags, default SKU fields,
`min_tls_version`). Reconcile the HCL *before* applying, or the first apply after import
silently rewrites live configuration.

## Lifecycle

```hcl
lifecycle {
  prevent_destroy = true                # apply ERRORS if the plan would destroy this
  ignore_changes  = [tags["CreatedBy"]] # set by policy, not by us
  create_before_destroy = true
  precondition {
    condition     = var.env != "prod" || var.enable_purge_protection
    error_message = "Purge protection is mandatory in prod."
  }
}
```

- `prevent_destroy` cannot be overridden by a flag — you must edit the code. That is the
  point. Put it on state storage, prod key vaults, and databases.
- `ignore_changes = all` hides real drift. List fields.
- `create_before_destroy` fails for globally-unique names (storage accounts, key vaults)
  unless the name is derived from something that changes too.

## Sensitive values

```hcl
variable "admin_password" { type = string, sensitive = true }   # no default; use TF_VAR_
output "connection_string" { value = azurerm_storage_account.sa.primary_connection_string, sensitive = true }
```

**`sensitive = true` only redacts CLI output. The value is stored in state as plaintext.**
This is the most misunderstood thing about Terraform. State also captures secrets you never
declared — storage keys, generated passwords, certificate private keys — every attribute the
provider reads back.

- Treat state as a secret store: encrypt the backend, restrict container RBAC to the deploy
  identity plus break-glass, log reads.
- Never commit state, post it in a ticket, or `terraform show -json` into CI logs.
- Prefer `azurerm_key_vault_secret` references and managed identity. If Terraform never sees
  the value, state never holds it.
- Feed secrets via `TF_VAR_*` env vars, not `.tfvars` files (paths reach shell history and
  sometimes CI logs):
  `export TF_VAR_admin_password="$(az keyvault secret show --vault-name kv --name pw --query value -o tsv)"`
- `nonsensitive()` should raise an eyebrow in review every time it appears.

## azurerm provider specifics

```hcl
provider "azurerm" {
  subscription_id = var.subscription_id     # REQUIRED since 4.0 (or ARM_SUBSCRIPTION_ID)
  tenant_id       = var.tenant_id
  resource_provider_registrations = "core"  # 5.x defaults to "none"

  features {                                # mandatory, appears EXACTLY ONCE; may be empty
    key_vault { purge_soft_delete_on_destroy = false, recover_soft_deleted_key_vaults = true }
    resource_group { prevent_deletion_if_contains_resources = true }
  }
}
```

Omitting `features` entirely errors as `Insufficient features blocks` — that means the block
is missing, not that a flag is wrong.

Auth order: explicit args → env vars → Azure CLI → managed identity.

| Variable | Purpose |
|---|---|
| `ARM_SUBSCRIPTION_ID` | required from 4.0 onward |
| `ARM_TENANT_ID` / `ARM_CLIENT_ID` | tenant and app/UAMI client id |
| `ARM_USE_OIDC=true` | use GitHub's OIDC token — **no client secret needed** |
| `ARM_OIDC_REQUEST_URL` / `ARM_OIDC_REQUEST_TOKEN` | auto-populated in Actions |
| `ARM_CLIENT_SECRET` | fallback only; avoid |
| `ARM_USE_MSI=true` | Azure-hosted runner with managed identity |

```yaml
permissions: { id-token: write, contents: read }
env:
  ARM_USE_OIDC: true
  ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
steps:
  - uses: hashicorp/setup-terraform@v3
    with: { terraform_version: 1.15.8, terraform_wrapper: false }
```

`terraform_wrapper: false` matters — the wrapper mangles exit codes and stdout, breaking
`plan -detailed-exitcode` and any output parsing. The **backend authenticates separately**
from the provider: add `use_oidc = true` (or `use_azuread_auth = true`) to the `backend`
block; OIDC env vars alone do not always reach it.

## CI discipline

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate    # validate without touching state
terraform init
terraform plan -out=tfplan -input=false -lock-timeout=5m
terraform show -no-color tfplan > plan.txt             # post as a PR comment
terraform apply -input=false tfplan                    # on merge only
```

- **Apply the saved plan file; never re-plan at apply time.** Otherwise what a human
  approved is not what gets applied. Pass `tfplan` as a job artifact between the two jobs.
- **Never auto-apply on a PR.** Plan on PR (read-only creds if possible), apply on merge,
  behind a GitHub environment with required reviewers for prod.
- `-input=false` everywhere; an interactive prompt in CI is a six-hour hang.
- `plan -detailed-exitcode`: `0` no changes, `1` error, `2` changes present. Use it to drive
  "does this PR change infra?" logic.
- The plan artifact is state-adjacent and contains secrets — short retention, never on a
  public run.

## Interop with Bicep

**One owner per resource.** Never declare the same Azure resource in both. Two patterns work:

1. **Terraform owns everything**, invoking Bicep as a unit via
   `azurerm_resource_group_template_deployment` (fed the ARM JSON from `bicep build`), then
   `jsondecode(output_content)`. Fragile — the deployment is opaque to `plan`.
2. **Split by layer, connect via data sources.** Bicep owns the Azure-native app platform
   (AI Foundry accounts, model deployments, App Service config); Terraform owns
   networking/identity/shared platform. Each publishes outputs the other reads.

```hcl
data "azurerm_cognitive_account" "foundry" {     # read only, never manage
  name                = var.foundry_account_name
  resource_group_name = var.foundry_rg
}
```

```bash
FOUNDRY_ID=$(az deployment group show -g "$RG" -n "$DEPLOY" \
  --query 'properties.outputs.foundryAccountId.value' -o tsv)
export TF_VAR_foundry_account_id="$FOUNDRY_ID"
```

Symptoms of a double-owned resource: alternating diffs, tags appearing and disappearing,
`plan` never reaching "no changes". Stop and decide the owner before writing more code.

## Commands and linting

```bash
terraform init -upgrade                  # refresh within constraints; review the lock diff
terraform plan -target=module.network    # emergency only; leaves state inconsistent
terraform state list / state show <addr>
terraform output -json | jq -r '.kv_uri.value'
terraform force-unlock <LOCK_ID>
terraform console                        # evaluate expressions against current state
```

- **`tflint`** with the azurerm ruleset — catches invalid SKUs, deprecated arguments, and
  unused declarations that `validate` accepts.
- **`checkov`** or **`tfsec`** (now inside Trivy) — run against the **plan JSON**
  (`terraform show -json tfplan`), not the HCL; scanning HCL misses anything computed from
  variables.
- **`terraform-docs`** to generate module READMEs from `variables.tf`/`outputs.tf`, checked
  in CI so docs cannot drift from the interface.
