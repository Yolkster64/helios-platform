---
name: microsoft-ecosystem
description: Microsoft ecosystem integration for HELIOS — Entra ID identity, Microsoft 365 Copilot (Graph connectors + declarative agents), Purview governance, Fabric analytics, and the hybrid boundary between the local fleet, Azure, and the tenant. Use when wiring anything to Entra, Graph, M365 Copilot, Purview, Fabric, or when a task crosses the local↔Azure↔M365 boundary.
---

# Microsoft ecosystem integration

The decision records live in `docs/architecture/`; this skill routes to them and adds
the API-level knowledge they deliberately leave out. Ground any API claim you cannot
cite from the repo via the Microsoft Learn MCP tools (`microsoft_docs_search`,
`microsoft_code_sample_search`, `microsoft_docs_fetch`) — never from memory; Graph and
Copilot schemas move quarterly.

## Where each decision lives

| Area | Decision record | Repo ground truth |
|---|---|---|
| Entra identity, ingress app, MI→Key Vault, GitHub OIDC | `docs/architecture/IDENTITY_ARCHITECTURE.md` | `src/ai/HELIOS.AIHub.Api/ApiEndpoints.cs`, `infra/modules/keyvault.bicep`, `scripts/bootstrap/{azure-oidc-setup.*,register-entra-app.ps1}` |
| M365 Copilot (connector + declarative agent) | `integrations/m365/README.md` | `integrations/m365/graph-connector/*.json`, `integrations/m365/declarative-agent/declarativeAgent.json` |
| Purview + Fabric (design, opt-in only) | `docs/architecture/GOVERNANCE_PURVIEW_FABRIC.md` | `.helios/` data contracts in `config/aihub.json` (`learning` block) |
| Hybrid boundary map | `docs/architecture/HYBRID_CLOUD_ARCHITECTURE.md` | `config/fleet/fleet-topology.json`, `infra/main.bicep` |
| Foundry (Azure AI) provider + agents | `docs/architecture/MULTI_LLM_INTEGRATION.md` | `src/ai/HELIOS.AIHub/Providers/`, `src/mcp/HELIOS.Mcp/` |

## Hard rules (inherited, non-negotiable)

- **Tenant mutations are owner actions.** Repo code and agents may read the tenant
  (Graph `GET`, search) when authorized; anything that writes — consent grants, app
  registrations, connection creation, app uploads — is executed by the owner from a
  runbook, never by automation on its own initiative.
- **No secrets in the repo** — env-var names and Key Vault secret *names* only; Graph
  app credentials live in Key Vault per the custody chain in
  `IDENTITY_ARCHITECTURE.md`.
- **Advisory learning contract applies downstream too**: analytics copies of learning
  data (Fabric lane) never feed adaptive routing; `source`-tagged advisory records
  stay advisory wherever they land.

## Working knowledge

`references/graph-and-copilot.md` — the API-level facts: Graph connector
connection/schema endpoints and semantic labels, declarative agent manifest schema
versions and capability objects, required Graph permissions with admin-consent
gotchas, and the live-verified tenant facts this repo's artifacts were built against.

`references/m365-copilot-tools.md` — the tools/plugins layer above it: API plugin
manifests (v2.x) and the agent's `actions` array (with the identity-aware-ingress
prerequisite for any HELIOS action), Agents Toolkit packaging/sideload/org-wide
deployment, Teams/Outlook surfacing, Copilot Studio vs the manifest path, connector
enablement + KQL scoping tools, and the M365 MCP read-only lane sessions use.

`references/tenant-administration.md` — the tenant-admin layer: app-registration
governance and consent tiers, Conditional Access as measured (AADSTS50078), security
defaults vs CA, break-glass, the ops-automation access tiers (read/write/admin) that
`scripts/bootstrap/setup-tenant.ps1` grants, M365 admin center surfaces, and Purview
portal flows (labels, auto-labeling, DLP for Copilot).

`references/fabric-and-powerbi.md` — the Power BI layer over the designed
`helios-analytics` Lakehouse: semantic-model shape for the outcome records, Direct
Lake vs import, report candidates, F-SKU vs Pro/PPU gates, and embedding — extending
(never duplicating) `docs/architecture/GOVERNANCE_PURVIEW_FABRIC.md` and its opt-in
trigger.
