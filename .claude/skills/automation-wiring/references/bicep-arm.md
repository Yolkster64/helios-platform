# Bicep / ARM Reference

Bicep CLI **v0.46.1** (Jul 2026); assume >= v0.30 below. Check `bicep --version` in CI — linter rules and type features are version-gated.

## Contents

- [Language features](#language-features-that-matter) · [Parameter files](#parameter-files) ·
  [Secrets](#secrets) · [RBAC](#rbac-role-assignments)
- [Idempotency traps](#idempotency-traps) · [what-if](#what-if) · [Scopes](#deployment-scopes) ·
  [AVM](#avm-vs-raw-resources)
- [AI Foundry](#azure-ai-foundry) · [ARM interop](#arm-json-interop) · [Validation](#validation)

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
  name: '${namePrefix}-law', location: region, properties: { sku: { name: 'PerGB2018' } }
}
resource kv 'Microsoft.KeyVault/vaults@2024-11-01' existing = { name: kvName, scope: resourceGroup(kvRg) }
module network 'modules/network.bicep' = { name: 'network-${env}', params: { location: region } }
```

- **`@batchSize(1)` above a resource loop serializes it** (default is parallel); mandatory for
  CognitiveServices model deployments and SQL firewall rules, where parallel creation on one
  parent returns intermittent `409 Conflict`.
- `existing` (optionally `scope:`-d to another RG) is **not** validated at compile time; a typo'd
  name compiles and 404s at deploy. `.?` guards `null` only, not index-out-of-range.
- A module's `name` is the *deployment* name and collides across concurrent deployments into one
  RG. Suffix it from a pipeline parameter — never `utcNow()` (see below).

## Parameter files

`.bicepparam` is type-checked against the template at compile time, so a renamed parameter fails
the build, not the deploy. Drifted parameter names are the most common Bicep seam failure; this is
the fix.

```bicep
using 'main.bicep'                  // main.dev.bicepparam — enables the type checking
param env = 'dev'
param deployments = [
  // Pick a GA model: Azure rejects new deployments of 'Deprecating' models,
  // and preflight fails on models whose regional quota is 0 — check with
  // `az cognitiveservices model list` / `usage list` first.
  { name: 'gpt-5-mini', format: 'OpenAI', version: '2025-08-07', capacity: 30 }
]
param adminPassword = getSecret('<subId>', '<rg>', '<kvName>', 'admin-password')
```

```bash
az deployment group create -g rg-helios-dev -f main.bicep -p main.dev.bicepparam
az bicep build-params --file main.dev.bicepparam    # emit legacy JSON if a tool needs it
```

Legacy JSON parameters remain necessary where a tool only accepts ARM JSON (some Azure DevOps
tasks, Terraform's `azurerm_resource_group_template_deployment`). `getSecret()` works only in a
`.bicepparam` or as a module param, and only for `@secure()` parameters — it resolves at deploy
time as the deploying identity, so the value never lands in the file.

## Secrets

```bicep
resource kv 'Microsoft.KeyVault/vaults@2024-11-01' existing = { name: kvName }
module app 'modules/app.bicep' = {                 // ARM resolves getSecret at deploy time
  name: 'app', params: { connectionString: kv.getSecret('sql-connection-string') }
}
```

- `@secure()` on every password, key, connection string, token. Non-secure params sit in plaintext
  in deployment history, readable by anyone with `deployments/read`.
- **Never `output` a secret.** Outputs persist in the deployment record forever and are not
  redacted even when the source was `@secure()`. Give consumers the vault URI and RBAC.
- App settings reference the vault without the template seeing the value:
  `'@Microsoft.KeyVault(SecretUri=${kv.properties.vaultUri}secrets/api-key/)'`
- Set `enableRbacAuthorization: true`; access policies are legacy and don't compose with RBAC.

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
  canonical seed; `newGuid()` adds a duplicate every run until the 2000-per-scope cap.
- `principalType: 'ServicePrincipal'` avoids `PrincipalNotFound` when a just-created managed
  identity has not replicated through Entra ID.
- `roleDefinitionId` needs the full ARM ID; a bare GUID fails validation.
- Assignments need Owner or User Access Administrator, **not** Contributor — the usual cause of
  "infra deploys fine but RBAC fails".

Built-in GUIDs I'm confident about: Owner `8e3af657-a8ff-443c-a75c-2fe8c4bcb635`, Contributor
`b24988ac-6180-42a0-ab88-20f7382dd24c`, Reader `acdd72a7-3385-48ef-bd42-f606fba81ae7`, Key Vault
Secrets User `4633458b-17de-408a-b874-0445c86b69e6`, Key Vault Secrets Officer
`b86a8fe4-44ce-4948-aee5-eccb2c155cd7`, Storage Blob Data Contributor
`ba92f5b4-2d11-453d-a403-e96b0029c9fe`, AcrPull `7f951dda-4ed3-4680-a7ca-43fe172d538d`. Resolve
anything else rather than guessing — a wrong GUID deploys fine and grants the wrong thing:
`az role definition list --name "Cognitive Services OpenAI User" --query [].name -o tsv`

## Idempotency traps

```bicep
param deployTime string = utcNow()   // legal ONLY as a param default
name: 'st${deployTime}'                                     // WRONG: new resource every deploy
name: 'st${namePrefix}${uniqueString(resourceGroup().id)}'  // RIGHT: stable
```

- `utcNow()` is only legal as a parameter default, which is why it sneaks into names. It changes
  every run → new resources → orphans and cost. Legitimate use: a `lastDeployed` tag.
- `uniqueString(resourceGroup().id)` — 13-char deterministic hash, stable for the RG's life (seed
  on `subscription().id` at that scope; it changes if the RG is deleted and recreated).
  `newGuid()` has `utcNow()`'s problem; use `guid()`. Storage account names are 3-24 lowercase
  alphanumeric, which `uniqueString` overflows fast.
- Deleting a resource from the template does **not** delete it in Azure under default
  `Incremental` mode. `Complete` mode does — and deletes anything in the RG not in the template,
  including another pipeline's resources. Use it only on single-owner RGs.

## what-if

`az deployment group what-if -g RG -f main.bicep -p main.dev.bicepparam` — add
`--result-format ResourceIdOnly` for a terse PR comment. Change types: `Create` `Delete`
`Modify` `Deploy` `NoChange` `Ignore` `NoEffect`.

- **`Modify` noise is normal** — providers return properties they set themselves (default SKU
  tiers, `provisioningState`, computed FQDNs). Learn your stack's usual noise.
- **It is a prediction, not a guarantee.** Nested deployments and some providers under-report;
  `Delete` entries are reliable, absence of one is not proof. `NoEffect` usually means you're
  setting a property on the wrong API version.
- Run what-if on every PR touching `infra/`, post it as a comment, require a human read before
  apply. Bicep has no plan file — this is the entire safety story.

## Deployment scopes

`resourceGroup` → `az deployment group create -g RG` (resources in one RG) ·
`subscription` → `az deployment sub create -l LOC` (resource groups, sub-level policy/RBAC) ·
`managementGroup` → `az deployment mg create -m MG -l LOC` (subscription placement, MG policy) ·
`tenant` → `az deployment tenant create -l LOC` (management groups).

Sub/MG/tenant deployments need `-l` even though nothing regional is created — it says where
deployment *metadata* lives. `deployment()` returns that metadata: fine for tagging, never for
resource names. A subscription-scope template creates the RG and hands it down: `module workload
'main-rg.bicep' = { name: 'workload', scope: rg }`.

## AVM vs raw resources

```bicep
module kv 'br/public:avm/res/key-vault/vault:0.13.0' = {   // pin exactly, never floating
  name: 'kv', params: { name: kvName, location: location, enableRbacAuthorization: true }
}
```

Raw resources are offline-deterministic after `az bicep install`, one file to debug, and yours to
maintain. AVM modules pull from MCR at build time and deepen what-if output, but arrive with
curated diagnostics, RBAC, and private-endpoint wiring. **Raw resources on the critical CI path in
registry-restricted or air-gapped environments; AVM when you want maintained wiring and tolerate a
registry dependency.** Mixing is fine — but never wrap AVM in your own module to rename its
parameters, which reintroduces exactly the drift AVM prevents.

## Azure AI Foundry

Current model: a **single `Microsoft.CognitiveServices/accounts` with `allowProjectManagement:
true`** acting as both AI-services provider and management hub, with projects as native child
resources. Confirmed GA API versions: `2025-06-01`, `2025-09-01`, `2025-12-01`, `2026-03-01`,
`2026-05-01`.

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
  }
}
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-09-01' = {
  parent: foundry
  name: projectName
  location: location
  properties: { displayName: 'Helios Agents' }   // add identity if the project calls Azure
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
- `sku.capacity` is quota; exceeding it fails `InsufficientQuota`, naming the region not the model.
- **`Microsoft.MachineLearningServices/workspaces` with `kind: 'Hub'`/`'Project'` is the older
  hub-based model ("Foundry classic").** Not for new work; inheriting one is a migration project,
  not a template edit. I'm unsure of its current retirement date — check the Foundry docs.

## ARM JSON interop

`bicep build main.bicep --outfile main.json` goes Bicep → ARM (and runs the linter);
`bicep decompile main.json` goes back. `decompile` output is a starting point: `resource0`-style symbolic names, lost intent, and
occasionally invalid Bicep for nested copy loops — budget time to rewrite. Hand-edit ARM only when
a marketplace/managed-app artifact demands a specific JSON shape, a policy `deployIfNotExists`
embeds a template inline, or a tool consumes `createUiDefinition.json`.

## Validation

`bicep build main.bicep --stdout > /dev/null` compiles and lints offline, exiting non-zero on
error — the cheapest gate. Commit a `bicepconfig.json` and raise the defaults to `error` so CI
actually fails:

```json
{ "analyzers": { "core": { "enabled": true, "rules": {
  "secure-parameter-default":           { "level": "error" },
  "outputs-should-not-contain-secrets": { "level": "error" },
  "no-hardcoded-env-urls":              { "level": "error" },
  "no-unused-params":                   { "level": "error" }
}}}}
```

The first two catch real incidents. `use-recent-api-versions` is noisy — it wants versions newer
than most stable templates use — leave it at `warning`. CI order that catches the most for the
least time: `bicep build` (offline, seconds) → `az deployment group validate` (needs auth) →
`what-if` (posts the diff) → apply.
