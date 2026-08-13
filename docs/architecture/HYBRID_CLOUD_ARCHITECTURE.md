# Hybrid Cloud Architecture — Boundary Map

The one-page map the forward plan anchors on: three trust boundaries, and for each
crossing, *who authenticates as what*, *where keys live*, and *what never crosses*.
Identity mechanics (roles, subjects, owner steps) live in
`IDENTITY_ARCHITECTURE.md` — this page only places them on the map. Design detail
per zone: `HERMES_FLEET_AND_XCORE.md` (fleet), `GITHUB_ECOSYSTEM_DESIGN.md`
(runners/connectors), `infra/README.md` (Azure stack),
`CLOUD_SHELL_AND_LOCAL_FLEET.md` (bring-up).

```
┌─ LOCAL ─────────────────────────┐   ┌─ AZURE (rg-helios-ai) ───────────────┐
│ Hermes/Xcore fleet (4 pools,    │   │ AI Foundry account + project         │
│  config/fleet/fleet-topology    │   │  (infra/modules/ai-foundry-*.bicep)  │
│  .json; boards in .helios/)     │   │ Key Vault kv-helios-* — provider     │
│ ARC runner cluster (operator's  │   │  keys (modules/keyvault.bicep)       │
│  k8s; infra/runners/)           │   │ Fleet burst VMSS (opt-in, system MI) │
│ Developer az login (device code)│   │ helios-ai-api hosting: DESIGNED ONLY │
└──────────┬──────────────────────┘   └──────────────┬───────────────────────┘
           │ ▲ keys pulled into process env only     │ ▲ RBAC: MI → Key Vault
           │ │ (load-env-from-keyvault.sh / MI)      │ │ Secrets User (data plane)
           ▼ │                                       ▼ │
┌─ GITHUB ────────────────────────┐   ┌─ ENTRA / M365 / PURVIEW ─────────────┐
│ Actions (hosted + runs-on:      │   │ Entra ID tenant: ALL Azure auth      │
│  helios-runners)                │◄──┤  terminates here (OIDC exchange,     │
│ helios-deploy.yml → OIDC, no    │   │  MI tokens, device-code login)       │
│  stored cloud secret            │   │ M365 Graph (SharePoint/Teams):       │
│ Actions vars = identifiers only │   │  scaffold only (hermes gateway, PR4) │
└─────────────────────────────────┘   │ Purview governance: design only      │
                                      └──────────────────────────────────────┘
```

## Boundary 1 — Local fleet & self-hosted runners → Azure

| Question | Answer |
|---|---|
| Who authenticates as what | Developers/operators as **themselves** (`az login` device-code — `scripts/bootstrap/connect-azure.sh`/`.ps1`); the fleet's `scale-fleet.ps1` burst call (`az vmss scale`) rides that same logged-in CLI (`HERMES_FLEET_AND_XCORE.md`, "Cloud burst"). Hub binaries use `DefaultAzureCredential` (`src/ai/HELIOS.AIHub/Configuration/SecretResolver.cs`), so the same code path is the human locally and a managed identity in Azure. |
| Where keys live | Provider API keys live in **Key Vault** (`infra/modules/keyvault.bicep`); locally they exist only in process env after sourcing `scripts/bootstrap/load-env-from-keyvault.sh` — never on disk, never in the repo (`config/aihub.json` carries env-var *names* only; CLAUDE.md hard rule). Board/lane state stays local in gitignored `.helios/fleet/`. |
| What never crosses | No credential is baked into cloud resources: the burst VMSS cloud-inits by **anonymous public clone** (`fleetRepoUrl` "Must be public — cloud-init clones anonymously and never carries credentials", `infra/main.bicep`) and gets secrets only if an operator grants its system MI `Key Vault Secrets User` (`fleetVmssPrincipalId` output). Kanban boards do not cross either — a known limitation: burst lanes seed empty boards (`infra/README.md`). |

## Boundary 2 — GitHub ↔ Azure

| Question | Answer |
|---|---|
| Who authenticates as what | `helios-deploy.yml` runs authenticate as the **`helios-github-deploy`** app via OIDC federation — subjects `repo:Yolkster64/helios-platform:ref:refs/heads/main` and `:environment:production`, deliberately no `pull_request` (`scripts/bootstrap/azure-oidc-setup.sh`; `IDENTITY_ARCHITECTURE.md` §3). Roles: `Contributor` @ RG, `Key Vault Secrets Officer` @ vault only. |
| Where keys live | **Nowhere.** No cloud secret is stored in the repo or in Actions; `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID` are Actions *variables* (identifiers). Provider keys enter deploys only as `@secure()` parameters and land in Key Vault, never in outputs (`infra/main.bicep`). |
| What never crosses | PR-triggered runs can never reach Azure (no matching federated subject; infra PR validation is offline in `infra-validate.yml`). The known-red `deploy.yml` still names a `secrets.AZURE_CLIENT_SECRET` — catalogued for deletion (`ROADMAP_MULTI_LLM.md`); nothing may copy it. |

## Boundary 3 — GitHub ↔ local runner cluster (ARC)

CI burst capacity is the operator's own Kubernetes cluster running the
`helios-runners` scale set (`infra/runners/arc-values.yaml`, 0→4, applied **by the
operator with helm — nothing in this repo's CI applies it**). Registration auth is
a GitHub App (preferred over PAT) whose credential exists solely as a pre-created
Kubernetes secret in that cluster (`infra/runners/README.md`); workflows only ever
see `runs-on: helios-runners`. ARC scale sets are the CI-lane burst target; the
Azure VMSS is the *fleet*-lane burst target — different signals, never conflated
(`infra/README.md`, "Two burst targets, deliberately";
`GITHUB_ECOSYSTEM_DESIGN.md`).

## Boundary 4 — Entra / Microsoft 365 / Purview

Every Azure crossing above already terminates in **Entra ID** — OIDC token
exchange, managed-identity tokens, and device-code logins are all Entra
operations; it is the identity plane, not a separate integration. The designed
next piece on this boundary is the `helios-ai-api` resource app (App ID URI + app
roles at an identity-aware ingress, `IDENTITY_ARCHITECTURE.md` §1).

Honest state of the rest:

| Piece | State | Evidence |
|---|---|---|
| Entra-federated deploys, MI→Key Vault chain | **Live pattern** | `azure-oidc-setup.sh`, `modules/keyvault.bicep`, `SecretResolver.cs` |
| helios-ai-api Entra ingress + hosting | **Designed only** — nothing in `infra/` hosts the API; it binds `127.0.0.1` locally (`docker-compose.yml`) | `IDENTITY_ARCHITECTURE.md` §1; helper `scripts/bootstrap/register-entra-app.ps1` |
| M365 Graph connector (SharePoint/Teams) | **Scaffold only** — the plan is to reuse the hermes-agent-github gateway's MS Graph client as the connector edge (roadmap PR4); `microsoft-ecosystem/365-integration/` is documentation scaffold, not running code | `GITHUB_ECOSYSTEM_DESIGN.md`, "Connector strategy" |
| Purview governance | **Design only** — `installer/security/purview-integration.ps1` writes local JSON config to hardcoded `C:\HELIOS` paths and belongs to the legacy/unreliable status-doc era (CLAUDE.md: trust `docs/architecture/`, not completion reports); no Purview resource exists in `infra/` | `microsoft-ecosystem/purview/README.md` (aspirational) |

When the M365/Purview pieces land, they inherit the same custody rules: Graph
access via an Entra identity (app registration with least Graph permissions, or
MI where hosted), credentials in Key Vault or nonexistent (federated), env files
carrying names only — the pattern of `config/connectors.json`, which already
routes Slack/Linear by env-var *name* with a graceful-skip contract.

## The two custody chains, end to end

**Identity chain:** GitHub run → OIDC subject → Entra federated credential →
scoped RBAC (RG/vault) · workload → system-assigned MI → `Key Vault Secrets User`
@ vault · human → device-code `az login` → their own RBAC + audit trail. Every
chain terminates in Entra; no link is a stored secret.

**Secret custody chain:** provider keys exist in exactly three places — Key Vault
(at rest), `@secure()` deploy parameters (in flight, never in history/outputs),
and process environment on a consuming host (runtime, pulled per-session). Never:
the repo, Actions secrets (for Azure auth), VMSS cloud-init, boards/logs, or
deployment outputs. The one local-dev exception is `HELIOS_API_ACCESS_KEY` for
the Docker bridge, which the ingress design demotes to exactly that
(`IDENTITY_ARCHITECTURE.md` §1).
