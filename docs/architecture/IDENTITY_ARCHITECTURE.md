# Entra Identity Architecture — Runbook

Who authenticates as what across the platform, and the standing rule every new
integration inherits: **no long-lived cloud credential anywhere**. A stored client
secret in the repo or in CI is a standing incident waiting for a leak; federated
identity and managed identity remove the secret entirely. The repo already lives this
rule in one place (`scripts/bootstrap/azure-oidc-setup.sh` + `helios-deploy.yml`,
§3) — this runbook makes it the pattern for everything else.

Companions: `infra/README.md` ("OIDC identity" — the deployed GitHub→Azure
federation), `HYBRID_CLOUD_ARCHITECTURE.md` (the boundary map that references this
doc), `CLOUD_SHELL_AND_LOCAL_FLEET.md` (developer device-code auth flows).
Steps a human with elevated Entra rights must run are marked **[owner]**; CI never
holds those rights.

## Identity inventory

| Identity | Type | Roles / scopes | Status |
|---|---|---|---|
| `helios-github-deploy` | App registration + SP, **federated (no secret)** | `Contributor` @ `rg-helios-ai` (RG only); `Key Vault Secrets Officer` @ `kv-helios-jcut` (vault only) | Live pattern — created by `scripts/bootstrap/azure-oidc-setup.sh` / `.ps1`, consumed by `.github/workflows/helios-deploy.yml` |
| Foundry account identity | System-assigned MI (`infra/modules/ai-foundry-account.bicep`, `identity: SystemAssigned`) | None granted by the templates | Exists when `infra/main.bicep` is deployed |
| Fleet VMSS identity | System-assigned MI (`infra/modules/fleet-vmss.bicep`) | None by default; grant `Key Vault Secrets User` against the `fleetVmssPrincipalId` output if cloud lanes must read provider keys (`infra/main.bicep` outputs, `infra/README.md`) | Opt-in (`deployFleetVmss`, off by default) |
| Operator (human `az login`) | Entra user, device-code flow | `principalId` param → `Azure AI User` @ Foundry account + `Key Vault Secrets User` @ vault (`infra/modules/ai-foundry-account.bicep`, `infra/modules/keyvault.bicep`) | Interactive `azure-up` path; CI never passes `principalId` (`infra/README.md`) |
| `helios-ai-api` resource app | App registration exposing App ID URI + app roles | It *is* the resource — callers hold its roles | **Designed** (§1); helper: `scripts/bootstrap/register-entra-app.ps1` |
| helios-ai-api hosting workload | System-assigned MI on whatever hosts the API | `Key Vault Secrets User` @ vault (§2) | **Designed** — no hosted deployment of the API exists in `infra/` today |
| ARC runner registration | GitHub App (preferred) or PAT, held only as a Kubernetes secret in the operator's cluster | GitHub-side repo registration, no Azure rights | Operator-applied, never by CI (`infra/runners/README.md`) |

## 1. Identity-aware ingress for `helios-ai-api`

### Today: loopback + shared key, by design local-only

`src/ai/HELIOS.AIHub.Api/ApiEndpoints.cs` (`AuthorizeApiRequest`) implements the
current contract:

- Loopback callers pass with no credential (`IPAddress.IsLoopback` check).
- A remote caller must send the value of `HELIOS_API_ACCESS_KEY` as the
  `X-HELIOS-Api-Key` header, compared with
  `CryptographicOperations.FixedTimeEquals`.
- **When `HELIOS_API_ACCESS_KEY` is unset, every remote request gets 401** —
  remote access is disabled, not open.

`docker-compose.yml` keeps the same posture: the API binds `127.0.0.1:5170`
("Loopback-only by default. Put an identity-aware reverse proxy in front before
changing this to a non-loopback host address") and sets a development-only default
key (`local-compose-only`) purely because Docker's bridge is not seen as loopback.
`CLAUDE.md` and `MULTI_LLM_INTEGRATION.md` ("REST orchestration API") both document
that hosted use still needs identity-aware ingress — a single static key is a
shared secret with no caller identity, no revocation granularity, and no audit
trail. This section is that ingress design.

### Design: Entra resource app + app roles, validated at the ingress

One app registration represents the API (the *resource* app). Callers — human or
workload — obtain Entra tokens **for** it and present them at the ingress; the API
process itself does not change.

**App registration `helios-ai-api`:**

- **App ID URI**: `api://<appId>` (the always-unique default; a vanity URI such as
  `api://helios-ai-api` works if the tenant allows it). Set
  `api.requestedAccessTokenVersion = 2` so access tokens are v2 (`aud` = the app's
  client ID).
- **App roles** (`allowedMemberTypes: ["User","Application"]`), mapped to the
  endpoint surface in `MULTI_LLM_INTEGRATION.md` ("REST orchestration API"):

  | Role value | Grants | Endpoints |
  |---|---|---|
  | `AIHub.Read` | Observe hub state; no provider spend | GET `/v1/status`, `/v1/routing`, `/v1/learning`, `/v1/insights`, `/v1/metrics`, `/v1/engines` |
  | `AIHub.Invoke` | Orchestration — can spend provider quota/money | POST `/v1/ask`, `/v1/route`, `/v1/tandem`, `/v1/compare`, `/v1/engines/recommend` (recommend itself is offline/deterministic, but it shares the orchestration verb surface) |
  | `AIHub.Learning.Write` | Advisory outcome ingestion (provenance-required) | POST `/v1/learning` |

  One delegated scope `AIHub.Access` (admin-consent-only) covers interactive
  callers such as a future WinUI shell signing in a user. `GET /healthz` stays
  anonymous — it is liveness and touches no hub state (`ApiEndpoints.cs`).

**Token validation happens at the ingress, not in Kestrel** — the API code keeps
its current behavior and the deployment chooses one of:

- **Container Apps built-in auth (EasyAuth)** — the auth sidecar sits in the same
  replica and forwards to the app over localhost, so Kestrel sees loopback and its
  existing bypass correctly trusts the sidecar's gating. Configure the Microsoft
  provider with the app registration, allowed audiences `<appId>` and
  `api://<appId>`, and unauthenticated action 401. Role→route mapping is read from
  the `X-MS-CLIENT-PRINCIPAL` claims header.
- **Reverse proxy with JWT validation** (YARP / nginx / Envoy) on the *same host*,
  forwarding only validated traffic to `127.0.0.1:5170` (exactly the topology the
  `docker-compose.yml` comment prescribes). Validate: issuer
  `https://login.microsoftonline.com/<tenantId>/v2.0`, audience = the app's client
  ID (v2 tokens), signature via the tenant's OIDC metadata, and the `roles` claim
  against the route table above.

**The API key is demoted to local-dev only.** Hosted configuration leaves
`HELIOS_API_ACCESS_KEY` unset — which, per `AuthorizeApiRequest`, means any request
that reaches Kestrel *without* going through the loopback proxy gets 401
unconditionally. The key remains only for the local Docker-bridge case
(`docker-compose.yml`). In-process enforcement of the `roles` claim (so the app
does not fully trust its proxy) is a deliberate follow-up, tracked with the hosted
deployment itself; nothing in `infra/` hosts the API today.

### [owner] Registration steps (no live calls here)

`scripts/bootstrap/register-entra-app.ps1` prints every command below with the
exact JSON payloads (dry-run by default; `-Apply` executes). Requires **Application
Developer** (or the tenant default that lets users register apps); the *consent and
assignment* steps additionally require **Cloud Application Administrator** or
Global Admin — those are the clicks CI can never make.

az CLI path:

```bash
az ad app create --display-name helios-ai-api --sign-in-audience AzureADMyOrg \
  --app-roles @app-roles.json --query appId --output tsv        # roles JSON: see the helper
az ad app update --id <appId> --identifier-uris "api://<appId>"
az ad app update --id <appId> --set api.requestedAccessTokenVersion=2
az rest --method PATCH \
  --url "https://graph.microsoft.com/v1.0/applications(appId='<appId>')" \
  --headers Content-Type=application/json --body @oauth2-scope.json   # delegated AIHub.Access
az ad sp create --id <appId>
```

Portal path: **Entra ID → App registrations → New registration** (single tenant) →
**Expose an API** (set App ID URI, add the `AIHub.Access` scope, admin-consent
only) → **App roles** (create the three roles above) → Enterprise application →
**Properties → Assignment required = Yes** (unassigned identities in the tenant
must not get tokens).

**[owner] Granting a caller a role** (per client identity — a workload MI or a
client app registration):

```bash
az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals/<resourceSpObjectId>/appRoleAssignedTo" \
  --headers Content-Type=application/json \
  --body '{"principalId":"<callerSpObjectId>","resourceId":"<resourceSpObjectId>","appRoleId":"<roleGuid>"}'
```

Grant the *least* role: a dashboard gets `AIHub.Read` and breaks only its own
panels if narrowed wrongly; nothing but an orchestration client ever needs
`AIHub.Invoke`, because that role spends provider quota.

## 2. Managed identity → Key Vault: the secret custody chain

### The contract already in the repo

- `config/aihub.json` carries **env-var names and Key Vault secret names only**
  (`apiKeyEnv` / `apiKeySecretName`: `openai-api-key`, `anthropic-api-key`,
  `github-models-token`) — never values (`CLAUDE.md` hard rule; the file's own
  `$comment`).
- `src/ai/HELIOS.AIHub/Configuration/SecretResolver.cs` resolves each secret as:
  env var → Key Vault at `AZURE_KEY_VAULT_URI` via **`DefaultAzureCredential`** →
  `null` (the provider surfaces as `Unconfigured`, never a startup crash).
- `infra/modules/keyvault.bicep` provisions the vault with
  `enableRbacAuthorization: true` (RBAC, not legacy access policies), writes the
  provider secrets only when non-empty `@secure()` params are passed, and never
  outputs a secret (`infra/main.bicep`, "Outputs — never output secrets").

`DefaultAzureCredential` is what makes one binary honest across environments: in
Azure it uses the workload's **managed identity**; in CI it picks up the OIDC
federation from `azure/login`; on a developer box it uses the human's own
`az login` (device-code flows in `scripts/bootstrap/connect-azure.sh` / `.ps1`),
so access rides the human's real permissions and audit trail.

### The RBAC grant pattern

Hosted workloads read provider keys via managed identity — no `*_API_KEY` env vars
on the box at all, only `AZURE_KEY_VAULT_URI` (a URI, not a credential). The role
is **`Key Vault Secrets User`** (`4633458b-17de-408a-b874-0445c86b69e6`) — data-plane
read of secret *contents*, nothing else; note that `Contributor` on the vault does
**not** grant secret reads. `infra/modules/keyvault.bicep` already encodes the
canonical assignment:

```bicep
resource secretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(vault.id, principalId, keyVaultSecretsUserRoleId)   // deterministic → idempotent redeploys
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
  }
}
```

Rules that pattern carries (and that any copy must keep):

- **Deterministic assignment name** — `guid(scope, principalId, roleId)`, so
  redeployment updates in place instead of erroring on a duplicate.
- **Vault scope, not RG or subscription** — the identity can read these secrets
  and nothing else.
- When assigning to a **just-created** managed identity, add
  `principalType: 'ServicePrincipal'` to avoid `PrincipalNotFound` while Entra
  replicates (the module currently omits it because `principalId` is the
  operator's user object ID on the interactive path; add it when wiring an MI).
- **RBAC is eventually consistent**: a deploy that grants a role and immediately
  reads a secret can fail once. Retry/order rather than sleep — the exact pattern
  `scripts/bootstrap/azure-oidc-setup.sh` (`ensure_role`, 5 attempts with backoff)
  already implements for the same reason.

Worked example already wired: `infra/main.bicep` outputs `fleetVmssPrincipalId`
precisely so an operator can grant the burst VMSS's system-assigned MI
`Key Vault Secrets User` when cloud fleet lanes must read provider keys
(`infra/README.md`, "Fleet burst capacity"; `HERMES_FLEET_AND_XCORE.md` setup
runbook step 2: workers get an MI with `Key Vault Secrets User` rather than a
shared static key). The designed helios-ai-api hosting workload (§1) follows
identically: system-assigned MI, `Key Vault Secrets User` at vault scope, env
carries `AZURE_KEY_VAULT_URI` only.

Human/dev fallback (not for hosted use): after `az login`, **source**
`scripts/bootstrap/load-env-from-keyvault.sh` to pull the three provider secrets
into process env vars — values land in process memory only, never on disk
(`CLOUD_SHELL_AND_LOCAL_FLEET.md`, "Secrets policy holds throughout").

## 3. GitHub OIDC federation — the established zero-stored-secret pattern

This is already deployed and is **the pattern all new automation must copy**.
Three parts must agree exactly, or `azure/login` fails with an opaque
`AADSTS700213`:

1. **Federated credentials on `helios-github-deploy`** (created re-runnably by
   `scripts/bootstrap/azure-oidc-setup.sh`, PowerShell twin `azure-oidc-setup.ps1`;
   issuer `https://token.actions.githubusercontent.com`, audience
   `api://AzureADTokenExchange`) for exactly these subjects:

   | Subject | Used by |
   |---|---|
   | `repo:Yolkster64/helios-platform:ref:refs/heads/main` | `helios-deploy.yml` on push to `main` / dispatch **from** `main` — a dispatch from a topic branch presents that branch's ref and fails login |
   | `repo:Yolkster64/helios-platform:environment:production` | Any job that declares `environment: production` — it presents this subject *instead of* the branch one |

   There is deliberately **no `repo:...:pull_request` subject**: this principal
   holds deploy rights, and a PR can modify workflow code — trusting the generic
   PR subject would hand any PR with `id-token: write` a path to those rights. The
   setup script even deletes that credential if an earlier revision created it
   (`azure-oidc-setup.sh`; rationale block also in `infra/README.md`). If PR jobs
   ever need Azure, create a **separate read-only identity** for them.

2. **The workflow declares the token permission** —
   `.github/workflows/helios-deploy.yml`:
   `permissions: { id-token: write, contents: read }`. Without `id-token: write`
   the OIDC token is never issued.

3. **`azure/login@v2` gets identifiers, not secrets** — `client-id` / `tenant-id`
   / `subscription-id` from Actions **variables** (`vars.AZURE_CLIENT_ID` etc.;
   the legacy `secrets.*` location still works as a fallback). The workflow skips
   gracefully when they are unset rather than going red, and pins
   `audience: api://AzureADTokenExchange` so the token exchange audience is explicit.

Least privilege on the Azure side (why these roles and no more,
`infra/README.md` "OIDC identity"):

- `Contributor` @ `rg-helios-ai` **only** — enough for
  `az deployment group create` of `infra/main.bicep`; cannot create RGs, touch
  other workloads, or assign roles. Narrower breaks template deployment itself.
- `Key Vault Secrets Officer` @ `kv-helios-jcut` **only** — `main.bicep`
  conditionally writes `Microsoft.KeyVault/vaults/secrets` on an RBAC-mode vault,
  and ARM authorizes those writes against *data-plane* RBAC, so `Contributor`
  alone fails Forbidden the moment a secure param (`anthropicApiKey`, …) is
  passed.

Rotation/revocation: **there is no secret to rotate**. Revoke by deleting the app
(`az ad app delete --id <AZURE_CLIENT_ID>`); re-establish by re-running the setup
script and updating the `AZURE_CLIENT_ID` variable.

Deploy custody notes: `helios-deploy.yml` stores sealed, allowlisted records
(manifest inputs, summary fields, and digests) instead of raw what-if/deploy payload
dumps. Checksums provide tamper-evident integrity for retained artifacts, but
authenticated provenance still comes from GitHub/Azure identity and run metadata.

**Anti-pattern, in-repo:** the known-red `.github/workflows/deploy.yml` still
references `secrets.AZURE_CLIENT_SECRET` — a stored client secret, the exact thing
this architecture eliminates. It is an all-echo fake deployment catalogued for
replacement/deletion in `ROADMAP_MULTI_LLM.md` ("Known-red workflow inventory");
nothing new may depend on it or copy its auth shape.

**[owner]** The federation bootstrap itself is the one elevated moment: run
`azure-oidc-setup.sh` as a human who can create app registrations (Application
Developer or the tenant default) *and* assign roles on the two scopes (Owner or
User Access Administrator on `rg-helios-ai`).

## 4. Threat table — what each identity boundary buys

| Threat | Boundary that contains it | Why it holds |
|---|---|---|
| **Leaked PAT** | Deploy path has no PAT at all (OIDC, §3). ARC runner registration prefers a GitHub App; either credential lives only as a Kubernetes secret in the operator's cluster, never in the repo or CI (`infra/runners/README.md`) | Nothing to find in the repo/Actions; a cluster-held GitHub App key scopes to runner registration, not to a human's whole account |
| **Exfiltrated env file / process env** on a workload | MI → Key Vault custody chain (§2) | Env holds `AZURE_KEY_VAULT_URI` (not a credential) and no provider keys; an attacker gains a durable secret only if they can *execute* as the workload, and MI token use is logged against that workload's identity — a shrunken, audited blast radius vs. a key that works from anywhere forever |
| **Workflow compromise via malicious PR** | No `pull_request` federated subject (§3) | The PR run's OIDC token carries the `pull_request` subject, which matches no credential → token exchange fails (`AADSTS700213`); PR infra validation stays offline in `infra-validate.yml` |
| **Stolen `HELIOS_API_ACCESS_KEY`** | Ingress design (§1): hosted config leaves the key unset | Remote-to-Kestrel requests then 401 unconditionally (`ApiEndpoints.AuthorizeApiRequest`); remote authorization moves to per-caller Entra roles, individually revocable |
| **Deployment-history snooping** | Bicep secret hygiene | Secrets enter as `@secure()` params (omitted from history) and are never output (`infra/main.bicep`, `infra/modules/keyvault.bicep`) |
| **Leaked `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID`** | They are identifiers, not secrets (§3) | Useless without an OIDC token whose subject matches a federated credential — which only runs of `helios-deploy.yml` from `main` (or `environment: production` jobs) can mint |
| **Compromised deploy identity** (worst case for §3) | RG-scoped `Contributor` + vault-scoped `Secrets Officer` | Cannot escalate: no role assignment rights, no subscription reach, no other RG |

## Verification

```bash
az role assignment list --assignee <AZURE_CLIENT_ID> --all -o table      # deploy identity grants
az ad app federated-credential list --id <AZURE_CLIENT_ID> \
  --query "[].subject" -o tsv                                            # subjects (expect main + environment only)
az role assignment list --assignee <workload-MI-principalId> --all -o table
```

Then run the real caller: dispatch `Helios Platform Deploy` **from `main`** with
`what_if=true` as a read-only rehearsal (`infra/README.md`); for the ingress
design, the smoke check is a token-less request to a hosted `/v1/status`
expecting 401 and a role-bearing token expecting 200 — the deny path is part of
the test, not just the allow path.
