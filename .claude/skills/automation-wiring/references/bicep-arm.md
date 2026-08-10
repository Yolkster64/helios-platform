# Bicep / ARM Reference

Bicep CLI **v0.46.1** (Jul 2026) is current. Features below assume ≥ v0.30. Check
`bicep --version` in CI — linter rules and type features are version-gated.

## Contents

- [Language features](#language-features-that-matter) · [Parameter files](#parameter-files) · [Secrets](#secrets)
- [RBAC](#rbac-role-assignments) · [Idempotency traps](#idempotency-traps) · [what-if](#what-if)
- [Scopes](#deployment-scopes) · [AVM](#avm-vs-raw-resources) · [AI Foundry](#azure-ai-foundry)
- [ARM interop](#arm-json-interop) · [Validation](#validation)

## Language features that matter

```bicep
targetScope = 'resourceGroup'    // default; also subscription | managementGroup | tenant

@description('Environment short name, used in resource naming.')
@allowed(['dev', 'test', 'prod'])
param env string

@minLength(3) @maxLength(24)
param namePrefix string

@secure()                        // omitted from deployment history
param adminPassword string

@export()                        // user-defined types (>= v0.21; @export >= v0.23)
type ModelDeployment = { name: string, format: string, version: string, capacity: int }
param deployments ModelDeployment[] = []

var region  = customRegion ?? resourceGroup().location            // null-coalescing
var firstIp = nic.properties.?ipConfigurations[0].properties.privateIPAddress ?? '0.0.0.0'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: '${namePrefix}-law'
  location: region
  properties: { sku: { name: 'PerGB2018' } }
}

resource kv 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
  scope: resourceGroup(kvResourceGroup)      // cross-RG reference
}

@batchSize(1)                                // serial; default is parallel
resource models 'Microsoft.CognitiveServices/accounts/deployments@2025-09-01' = [
  for d in deployments: { /* ... */ }
]

module network 'modules/network.bicep' = {
  name: 'network-${env}'        // DEPLOYMENT name, not resource name; unique per RG per run
  params: { location: region }
}
```

- **`@batchSize(1)` is mandatory for CognitiveServices model deployments** — parallel
  creation on one account returns intermittent `409 Conflict`. Same for SQL firewall rules
  and some App Service children.
- `existing` is **not** validated at compile time. A typo'd name compiles and fails at
  deploy with a 404 on the parent operation.
- Module `name` collides across concurrent deployments into the same RG. Prefix with a
  `deploymentSuffix` parameter from the pipeline — never `utcNow()` (see below).
- `.?` guards `null` only, not array index-out-of-range.

## Parameter files

`.bicepparam` is type-checked against the template at compile time, so a renamed parameter
fails the build instead of the deploy. Drifted parameter names are the single most common
Bicep seam failure — this is the fix.

```bicep
// main.dev.bicepparam
using 'main.bicep'                  // the binding that enables type checking

param env = 'dev'
param deployments = [
  { name: 'gpt-4o-mini', format: 'OpenAI', version: '2024-07-18', capacity: 30 }
]
param adminPassword = getSecret('<subId>', '<rg>', '<kvName>', 'admin-password')
```

```bash
az deployment group create -g rg-helios-dev -f main.bicep -p main.dev.bicepparam
az bicep build-params --file main.dev.bicepparam     # emit legacy JSON if a tool needs it
```

Legacy JSON parameters are still required where a tool only accepts ARM JSON (some Azure
DevOps tasks, Terraform's `azurerm_resource_group_template_deployment`) or the file is
machine-generated. Otherwise use `.bicepparam`.

`getSecret()` is valid only in a `.bicepparam` file or as a module param, only for
`@secure()` parameters. It resolves at deploy time via the deploying identity, so the value
never lands in the file or the deployment record.

## Secrets

```bicep
resource kv 'Microsoft.KeyVault/vaults@2024-11-01' existing = { name: kvName }

module app 'modules/app.bicep' = {
  name: 'app'
  params: { connectionString: kv.getSecret('sql-connection-string') }  // ARM resolves it
}
```

- `@secure()` on every password, key, connection string, token. Non-secure params are stored
  in plaintext in deployment history, readable by anyone with `deployments/read`.
- **Never `output` a secret.** Outputs persist in the deployment record forever and are not
  redacted even when the source was `@secure()`. Give consumers the Key Vault URI and RBAC.
- App settings can reference the vault without your template seeing the value:
  `'@Microsoft.KeyVault(SecretUri=${kv.properties.vaultUri}secrets/api-key/)'`
- Set `enableRbacAuthorization: true`. Access policies are legacy and do not compose with
  role assignments.

## RBAC role assignments

```bicep
var keyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, principalId, keyVaultSecretsUser)     // deterministic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUser)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
```

- The name **must be a GUID, stable across deploys**. `guid(scope, principal, role)` is the
  canonical seed. `newGuid()` creates a duplicate every run until the 2000-per-scope cap.
- `roleDefinitionId` needs the full ARM ID — a bare GUID fails validation.
- `principalType: 'ServicePrincipal'` avoids `PrincipalNotFound` when a just-created managed
  identity has not replicated through Entra ID.
- Creating role assignments needs Owner or User Access Administrator, **not** Contributor.
  This is the usual cause of "infra deploys fine but RBAC fails".

Built-in GUIDs I'm confident about:

| Role | GUID |
|---|---|
| Owner | `8e3af657-a8ff-443c-a75c-2fe8c4bcb635` |
| Contributor | `b24988ac-6180-42a0-ab88-20f7382dd24c` |
| Reader | `acdd72a7-3385-48ef-bd42-f606fba81ae7` |
| Key Vault Secrets User | `4633458b-17de-408a-b874-0445c86b69e6` |
| Key Vault Secrets Officer | `b86a8fe4-44ce-4948-aee5-eccb2c155cd7` |
| Storage Blob Data Contributor | `ba92f5b4-2d11-453d-a403-e96b0029c9fe` |
| Storage Blob Data Reader | `2a2b9908-6ea1-4ae2-8e65-a410df84e7d1` |
| AcrPull | `7f951dda-4ed3-4680-a7ca-43fe172d538d` |

For anything else, resolve rather than guess — a wrong GUID deploys successfully and grants
the wrong thing: `az role definition list --name "Cognitive Services OpenAI User" --query "[].name" -o tsv`

## Idempotency traps

```bicep
param deployTime string = utcNow()
name: 'st${deployTime}'                                   // WRONG: new resource every deploy
name: 'st${namePrefix}${uniqueString(resourceGroup().id)}'  // RIGHT: stable
```

- `utcNow()` is only legal as a parameter default (which is why it sneaks into names). It
  changes every run → new resources → orphans and cost. Legitimate use: a `lastDeployed` tag.
- `uniqueString(resourceGroup().id)` — 13-char deterministic hash, stable for the RG's life.
  Seed on `subscription().id` for subscription-scope uniqueness. It changes if the RG is
  deleted and recreated.
- `newGuid()` has the same problem; use `guid()` with stable seeds.
- Storage account names are 3-24 chars lowercase alphanumeric — `uniqueString` overflows
  them fast. Validate length at author time; ARM's error is unhelpful.
- Deleting a resource from the template does **not** delete it in Azure under default
  `Incremental` mode. `Complete` mode does — and will delete anything in the RG not in the
  template, including another pipeline's resources. Use it only on single-owner RGs.

## what-if

```bash
az deployment group what-if -g rg-helios-dev -f main.bicep -p main.dev.bicepparam
az deployment group what-if ... --result-format ResourceIdOnly     # terse, for a PR comment
```

Change types: `Create` `Delete` `Modify` `Deploy` `NoChange` `Ignore` `NoEffect`.

- **`Modify` noise is normal.** Providers return properties they set themselves (default SKU
  tiers, `provisioningState`, computed FQDNs) and what-if reports them as diffs that never
  change. Learn your stack's usual noise so a real diff stands out.
- **It is a prediction, not a guarantee.** Nested deployments and some providers
  under-report. `Delete` entries are reliable; absence of a `Delete` is not proof.
- `NoEffect` usually means you're setting a property on the wrong API version.
- Run what-if on every PR touching `infra/`, post it as a comment, require a human read
  before apply. There is no plan file in Bicep — this is the entire safety story.

`az deployment group validate` is weaker (schema + basic policy, no diff) but fast; use it
as a syntactic gate, not a review artifact.

## Deployment scopes

| targetScope | Command | Creates |
|---|---|---|
| `resourceGroup` | `az deployment group create -g RG` | resources in one RG |
| `subscription` | `az deployment sub create -l LOC` | resource groups, sub-level policy/RBAC |
| `managementGroup` | `az deployment mg create -m MG -l LOC` | subscription placement, MG policy |
| `tenant` | `az deployment tenant create -l LOC` | management groups |

Sub/MG/tenant deployments need `-l` even though nothing regional is created — it says where
deployment *metadata* lives.

```bicep
targetScope = 'subscription'
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = { name: 'rg-helios-${env}', location: location }
module workload 'main-rg.bicep' = { name: 'workload', scope: rg, params: { location: location } }
```

`deployment()` returns the current deployment's metadata (`.name`, `.location`) — fine for
tagging, do not build resource names from it.

## AVM vs raw resources

```bicep
module kv 'br/public:avm/res/key-vault/vault:0.13.0' = {   // pin exactly, never floating
  name: 'kv'
  params: { name: kvName, location: location, enableRbacAuthorization: true }
}
```

| | Raw resources | AVM (`br/public:`) |
|---|---|---|
| CI determinism | offline after `az bicep install` | pulls from MCR at build |
| Best practice | you own it | curated: diagnostics, RBAC, private endpoints |
| Debugging | one file | nested modules, deeper what-if output |

**Raw resources for anything on the critical CI path in a registry-restricted or air-gapped
environment; AVM when you want maintained wiring and can tolerate a registry dependency.**
Mixing is fine — but do not wrap AVM in your own module to rename its parameters, which
reintroduces exactly the drift AVM prevents.

## Azure AI Foundry

Current model: a **single `Microsoft.CognitiveServices/accounts` with
`allowProjectManagement: true`**, acting as both AI-services provider and management hub,
with projects as native child resources. Confirmed GA API versions: `2025-06-01`,
`2025-09-01`, `2025-12-01`, `2026-03-01`, `2026-05-01`.

```bicep
resource foundry 'Microsoft.CognitiveServices/accounts@2025-09-01' = {
  name: accountName
  location: location
  kind: 'AIServices'                    // not 'OpenAI'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    allowProjectManagement: true        // this is what makes it a Foundry resource
    customSubDomainName: accountName    // REQUIRED for token auth and portal visibility
    disableLocalAuth: true              // force Entra auth, no API keys
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-09-01' = {
  parent: foundry
  name: projectName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: { displayName: 'Helios Agents', description: 'Agent orchestration' }
}

@batchSize(1)
resource models 'Microsoft.CognitiveServices/accounts/deployments@2025-09-01' = [
  for d in deployments: {
    parent: foundry
    name: d.name
    sku: { name: 'GlobalStandard', capacity: d.capacity }   // capacity = units of 1K TPM
    properties: {
      model: { format: d.format, name: d.name, version: d.version }
      versionUpgradeOption: 'OnceCurrentVersionExpired'
    }
  }
]
```

- Omitting `customSubDomainName` deploys successfully but breaks Entra-token auth and portal
  discovery, and **cannot be added later without recreating**.
- Model deployments must be serialized (`@batchSize(1)`).
- `sku.capacity` is quota. Exceeding regional quota fails with `InsufficientQuota` naming
  the region, not the model.
- **`Microsoft.MachineLearningServices/workspaces` with `kind: 'Hub'`/`'Project'` is the
  older hub-based model ("Foundry classic").** Don't use it for new work. Inheriting one is
  a migration project, not a template edit — resource shapes, connections, and RBAC all
  differ. I'm not certain of the current retirement date; check the Foundry docs.

## ARM JSON interop

```bash
bicep build main.bicep --outfile main.json    # Bicep -> ARM (also runs the linter)
bicep decompile main.json                     # ARM -> Bicep (best-effort)
bicep build-params main.dev.bicepparam        # -> ARM parameters JSON
```

`decompile` output is a starting point: `resource0`-style symbolic names, lost intent, and
occasionally invalid Bicep for nested copy loops. Budget time to rewrite.

Hand-edit ARM only when a marketplace/managed-app artifact demands a specific JSON shape, a
policy `deployIfNotExists` embeds a template inline, or a tool consumes
`createUiDefinition.json` alongside it.

## Validation

```bash
bicep build main.bicep --stdout > /dev/null   # compile + lint; non-zero on error
az deployment group validate -g RG -f main.bicep -p main.dev.bicepparam
az deployment group what-if  -g RG -f main.bicep -p main.dev.bicepparam
```

Commit a `bicepconfig.json` and raise defaults to `error` so CI actually fails:

```json
{ "analyzers": { "core": { "enabled": true, "rules": {
  "secure-parameter-default":          { "level": "error" },
  "outputs-should-not-contain-secrets":{ "level": "error" },
  "no-hardcoded-env-urls":             { "level": "error" },
  "no-unused-params":                  { "level": "error" },
  "no-unused-vars":                    { "level": "error" },
  "use-recent-api-versions":           { "level": "warning" }
}}}}
```

`outputs-should-not-contain-secrets` and `secure-parameter-default` are the two that catch
real incidents. `use-recent-api-versions` is noisy (it wants versions newer than most stable
templates use) — keep it at warning.

CI order that catches the most for the least time: `bicep build` (offline, seconds) →
`az deployment validate` (needs auth) → `what-if` (posts the diff) → apply.
