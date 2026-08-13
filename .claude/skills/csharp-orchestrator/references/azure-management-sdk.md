# Azure management-plane SDK (Azure.ResourceManager) — working API knowledge

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

The automated-Azure lane: what the `Azure.ResourceManager.*` packages do for HELIOS,
verified against the `azure-sdk-for-net` fork source (an ecosystem repo per
`docs/architecture/FORWARD_PLAN.md` — **consume from NuGet, verify from the fork**:
binaries always come from nuget.org; the fork exists so API claims are grounded in real
source instead of remembered signatures). Fork paths below are relative to the fork
root. Live repo usage: `src/ai/HELIOS.AIHub/Providers/AzureResourceService.cs` behind
the `helios_azure_inventory_get` MCP tool (`src/mcp/HELIOS.Mcp/HeliosAzureTools.cs`).

## Which packages matter, and why

| Package | HELIOS use | Fork source root |
|---|---|---|
| `Azure.ResourceManager` | Core: `ArmClient`, resource-identifier model, generic resource/RG/subscription reads, LRO plumbing (`ArmOperation`) — everything `AzureResourceService` needs | `sdk/resourcemanager/Azure.ResourceManager/src/` |
| `Azure.ResourceManager.Resources` | Deployments: `ArmDeploymentResource` incl. **what-if** — the next step of this lane (pinned in `Directory.Packages.props`, not yet referenced) | `sdk/resources/Azure.ResourceManager.Resources/src/` (NOT under `sdk/resourcemanager/`) |
| `Azure.ResourceManager.CognitiveServices` | Typed Foundry account surface (`CognitiveServicesAccountResource/-Data/-Collection` — the AIServices account `infra/main.bicep` provisions) | `sdk/cognitiveservices/Azure.ResourceManager.CognitiveServices/src/Generated/` |
| `Azure.ResourceManager.Search` | Typed search service (`SearchServiceResource/-Data`) | `sdk/search/Azure.ResourceManager.Search/src/Generated/` |
| `Azure.ResourceManager.KeyVault` | Typed vault (`KeyVaultResource/-Data`) — management plane only; secret VALUES stay in `Azure.Security.KeyVault.Secrets` (data plane) | `sdk/keyvault/Azure.ResourceManager.KeyVault/src/Generated/` |

Adopt the typed provider packages **only when reading provider-specific properties**
(SKUs, endpoints, network rules). Pure identity inventory — id/name/type/location —
comes from the core package's `GenericResource`, which is why `AzureResourceService`
references `Azure.ResourceManager` alone.

## ArmClient and the resource-identifier model

- Constructors: `ArmClient(TokenCredential)` / `(TokenCredential, string
  defaultSubscriptionId)` / `(TokenCredential, string, ArmClientOptions)`
  (`sdk/resourcemanager/Azure.ResourceManager/src/ArmClient.cs:47-69`).
- `GetDefaultSubscriptionAsync(ct)` → `SubscriptionResource` (first subscription unless
  a default id was given — `ArmClient.cs:214`); `GetSubscriptions()` →
  `SubscriptionCollection` with `GetAsync(subscriptionId, ct)`
  (`ArmClient.cs:161`, `src/Resources/Generated/SubscriptionCollection.cs:79`).
  `SubscriptionData` carries `SubscriptionId`/`DisplayName`
  (`src/Resources/Generated/SubscriptionData.cs:86-89`).
- **Identifier-first navigation, no GET**: every resource type has a static
  `CreateResourceIdentifier(...)` and `ArmClient` has a matching
  `Get<Type>Resource(ResourceIdentifier)` that builds the typed client *without a
  network call* — data loads lazily on first use.
  `SubscriptionResource.CreateResourceIdentifier(subscriptionId)`
  (`src/Resources/Generated/SubscriptionResource.cs:29`),
  `ResourceGroupResource.CreateResourceIdentifier(subscriptionId, name)`
  (`src/Resources/Generated/ResourceGroupResource.cs:31`),
  `GetSubscriptionResource`/`GetResourceGroupResource`
  (`src/Resources/Generated/Extensions/ArmClient.cs:141,165`).
- `ResourceIdentifier` (Azure.Core, `sdk/core/Azure.Core/src/ResourceIdentifier.cs`)
  parses any ARM id into `SubscriptionId` (:326), `ResourceGroupName` (:341),
  `ResourceType` (:306), `Name` (:311) — how `AzureResourceService` attributes a
  subscription-level resource scan to groups client-side.
- Reads used by the inventory lane (all return `AsyncPageable<T>`, which pages
  transparently — **bound total enumeration yourself**, same rule as the Foundry
  `GetAgentsAsync` pageable in `provider-sdks.md`):
  - `SubscriptionResource.GetResourceGroups().GetAllAsync(filter, top, ct)`
    (`src/Resources/Generated/SubscriptionResource.cs:316`,
    `src/Resources/Generated/ResourceGroupCollection.cs:271`).
  - `SubscriptionResource.GetGenericResourcesAsync(filter, expand, top, ct)` — one
    call for the whole subscription (`src/Resources/Custom/SubscriptionResource.cs:29`);
    the same method exists per-group on `ResourceGroupResource`
    (`src/Resources/Custom/ResourceGroupResource.cs:31`) but costs one HTTP call per
    group.
  - `GenericResourceData : TrackedResourceExtendedData`
    (`src/Resources/Generated/GenericResourceData.cs:20`) inherits `Id`/`Name`/
    `ResourceType` (`src/Common/Generated/Models/ResourceData.cs:37-41`) and
    `Tags`/`Location` (`src/Common/Generated/Models/TrackedResourceData.cs:46-48`).
- **LRO pattern**: mutating/heavy operations return `ArmOperation` /
  `ArmOperation<T>` (`src/ArmOperation.cs`, `src/ArmOperationOfT.cs`) and take a
  `WaitUntil` first parameter — `WaitUntil.Completed` blocks (polls) until done,
  `WaitUntil.Started` returns immediately with `WaitForCompletionAsync` available.

## Deployment what-if (`Azure.ResourceManager.Resources`) — verified shape

What-if is ARM's read-only dry run: a POST that reports the changes a deployment
*would* make without making them. The full surface, from the fork:

- `ArmDeploymentResource.WhatIfAsync(WaitUntil waitUntil, ArmDeploymentWhatIfContent
  content, CancellationToken ct)` → `ArmOperation<WhatIfOperationResult>`
  (`sdk/resources/Azure.ResourceManager.Resources/src/Generated/ArmDeploymentResource.cs:670`;
  sync twin at `:795`). The method dispatches on the id's scope — tenant, management
  group, subscription, or resource group (`Deployments_WhatIf*` REST ops listed at
  `:606-654`).
- The deployment resource **does not need to exist**: build the id with
  `ArmDeploymentResource.CreateResourceIdentifier(string scope, string deploymentName)`
  (`ArmDeploymentResource.cs:32`) and hydrate with
  `GetArmDeploymentResource(this ArmClient, ResourceIdentifier)`
  (`src/Generated/Extensions/ResourcesExtensions.cs:228`). Existing deployments list
  via `GetArmDeployments(this ResourceGroupResource)` (`ResourcesExtensions.cs:733`;
  subscription/tenant/management-group overloads at `:1198`, `:1738`, `:359`).
- Request model: `ArmDeploymentWhatIfContent(ArmDeploymentWhatIfProperties)` plus
  optional `Location` (required at tenant/management-group scope)
  (`src/Generated/Models/ArmDeploymentWhatIfContent.cs:52,77`);
  `ArmDeploymentWhatIfProperties(ArmDeploymentMode mode)` derives from
  `ArmDeploymentProperties` (`ArmDeploymentWhatIfProperties.cs:14-18`), whose
  `Template` and `Parameters` are **`BinaryData` holding ARM JSON**
  (`ArmDeploymentProperties.cs:125,160`) — a Bicep file must go through
  `bicep build` first; there is no Bicep-in, and `TemplateLink` (`:128`) is the
  URI alternative.
- Result: `WhatIfOperationResult { Status, Error, Changes, PotentialChanges,
  Diagnostics }` (`src/Generated/Models/WhatIfOperationResult.cs:75-87`); each
  `WhatIfChange` carries `ResourceId`, `ChangeType` (Create/Modify/Delete/…),
  `Before`/`After` (`BinaryData`) and a `Delta` of property changes
  (`src/Generated/Models/WhatIfChange.cs`).

**Why HELIOS has not wrapped it yet** (the documented next step after
`helios_azure_inventory_get`): the wrapper itself is read-only and clean, but a
truthful tool needs (1) `bicep build` to turn `infra/main.bicep` into the ARM JSON
`BinaryData`, (2) values for main.bicep's `@secure()` parameters — which must not
transit an MCP argument surface casually — and (3) LRO polling. Ship it as its own
reviewed PR; `Azure.ResourceManager.Resources` 1.11.2 is already pinned centrally for
it.

## Credential chain and the management-/data-plane split

- Same `DefaultAzureCredential` chain and traps as the rest of the hub — see
  `provider-sdks.md` ("Credential-chain trap"): the chain resolves **lazily at the
  first REST call**, so `ArmClient` construction never fails for missing credentials.
  A fully exhausted chain throws `CredentialUnavailableException`, which derives from
  `AuthenticationFailedException` — catch the base type to cover both
  (`sdk/core/Azure.Core/src/Identity/CredentialUnavailableException.cs:21`,
  `AuthenticationFailedException.cs:21`; at fork HEAD these live in Azure.Core and are
  type-forwarded from Azure.Identity — `sdk/identity/Azure.Identity/src/TypeForwarders.cs` —
  but in the pinned `Azure.Identity` 1.21.0 package they are Azure.Identity types, so
  `using Azure.Identity;` is still correct). `AzureResourceService` converts that to
  its Unauthenticated result, mirroring `SecretResolver`'s auth-is-a-state rule.
- **One credential, two planes.** `Azure.ResourceManager.*` is the management
  (control) plane: ARM endpoint, `https://management.azure.com/.default` token
  audience, RBAC roles like Reader/Contributor on scopes.
  `Azure.AI.Agents.Persistent`, `Azure.AI.OpenAI`, `Azure.Security.KeyVault.Secrets`,
  `Azure.Data.Tables` are **data plane**: per-service endpoints and audiences, roles
  like *Azure AI User* or *Key Vault Secrets User*. The same `DefaultAzureCredential`
  instance serves both — each SDK requests its own scope — but RBAC is granted per
  plane: management Reader does NOT confer data-plane access, and vice versa. That is
  why `helios_azure_inventory_get` can succeed while `helios_foundry_agent_list` 403s
  (or the reverse) under one login.

## Versioning / GA discipline

- **Pin stable, never preview, for management packages.** Current pins
  (`Directory.Packages.props`): `Azure.ResourceManager` **1.14.0**,
  `Azure.ResourceManager.Resources` **1.11.2** — the latest stable lines on nuget.org
  as of 2026-08.
- The fork's HEAD is dev: core csproj says `1.15.0-beta.1` with
  `ApiCompatVersion 1.14.0`; Resources says `1.12.0-beta.2` /
  `ApiCompatVersion 1.11.2` (each package's `src/*.csproj`). `ApiCompatVersion` is the
  shipped stable the source is compat-checked against — when source-verifying an API
  for code built on the NuGet pin, confirm it isn't newer than that line (the APIs
  cited above all predate it).
- `Azure.ResourceManager.Resources.Deployments`
  (`sdk/resources/Azure.ResourceManager.Resources.Deployments/`, `1.0.0-beta.2` at
  fork HEAD) is a preview split-out of the deployment types. **Do not adopt it**: the
  same `ArmDeploymentResource` surface ships stable inside
  `Azure.ResourceManager.Resources` 1.11.2.
