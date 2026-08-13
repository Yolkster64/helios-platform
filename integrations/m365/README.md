# Microsoft 365 Copilot integration (scaffold + runbook)

Repo-side artifacts that connect HELIOS to Microsoft 365 Copilot: a **Copilot (Graph)
connector** definition that indexes HELIOS governance/status documents into M365
search and Copilot grounding, and a **declarative agent** manifest (the HELIOS
operator agent for Copilot). Everything here is a repo artifact — **no tenant
mutation happens from this repo**; every step that changes the tenant is an owner
action marked below.

## Live verification (read-only, 2026-08-13)

Tenant reachability and corpus existence were verified via authorized read-only
Graph calls (no mutations):

- `GET /me` → resolved the signed-in tenant admin account
  (tenant `Heli0s.onmicrosoft.com`).
- SharePoint search for `HELIOS` → **49 documents**, including a governed
  documentation tree that is exactly the corpus worth indexing:
  - Site: `https://heli0s.sharepoint.com/Shared Documents/HELIOS/Governance/`
    (e.g. `HELIOS_PR1_Governance_Evidence_2026-08-10.md`)
  - OneDrive: `.../Documents/Helios/Governance/{Architecture, Deployment-Evidence,
    Integration-Fabric}` (e.g. `HELIOS_CONNECT_ARCHITECTURE.md`,
    `HELIOS_AZURE_ENTERPRISE_AGENT_FLEET.md`)

SharePoint/OneDrive content is *already* Copilot-groundable without a connector;
the connector below adds the **repo-side** corpus (docs/, absorption reports,
board status) that never lands in SharePoint.

## 1. Copilot connector (`graph-connector/`)

- `connection.json` — the external connection (`POST /external/connections`).
- `schema.json` — the item schema (`PATCH /external/connections/{id}/schema`),
  a flat property list with semantic labels (`title`, `url`,
  `lastModifiedDateTime`, `iconUrl`) so Copilot can cite items properly.

**Owner runbook (order matters; schema registration can take several minutes):**

1. Entra app registration with **application** permissions
   `ExternalConnection.ReadWrite.OwnedBy` + `ExternalItem.ReadWrite.OwnedBy`;
   grant admin consent. (Use the identity pattern in
   `docs/architecture/IDENTITY_ARCHITECTURE.md`; client credentials belong in
   Key Vault, never in this repo.)
2. `POST https://graph.microsoft.com/v1.0/external/connections` with
   `connection.json`.
3. `PATCH https://graph.microsoft.com/v1.0/external/connections/heliosplatform/schema`
   with `schema.json`; poll the operation until `completed`.
4. Ingest items (`PUT .../items/{itemId}`) — the natural sources are
   `docs/architecture/*.md`, `.helios/absorption/*.json` verdicts, and epic/board
   status. Ingestion automation is a follow-up lane (a scheduled workflow using
   the OIDC→Entra federation pattern); do not hand-sync.
5. In the M365 admin center, enable the connection for Copilot
   (Search & intelligence → Data sources).

## 2. Declarative agent (`declarative-agent/`)

`declarativeAgent.json` — schema **v1.5** manifest for the "HELIOS Operator"
agent: instructions scoped to HELIOS operations, grounded in (a) the verified
SharePoint governance tree and (b) the `heliosplatform` connector above.
Schema v1.8 is the latest; upgrading is a `version` bump reviewed against the
v1.8 reference (no field here is deprecated in 1.6–1.8).

**Owner runbook:**

1. Package it as an M365 app (Microsoft 365 Agents Toolkit / Teams Toolkit:
   app manifest + this declarative agent manifest + icons in one zip).
2. Upload via admin center (Integrated apps → Upload custom app) or sideload
   for a single user; assign to the operators group.
3. The `GraphConnectors` capability activates only after the connector
   (section 1) is live; until then the agent grounds on SharePoint alone.

## Boundaries

- **No secrets in this directory, ever** — IDs and display names only.
- Tenant changes (consent, connection creation, app upload) are owner actions;
  agents/automation in this repo may *read* (as verified above) but never write
  to the tenant without an explicit owner-approved task.
- The agent's instructions forbid it from claiming execution ability: it is a
  knowledge/status agent in M365; execution stays in the hub
  (`helios-ai`/MCP) where the audit trail lives.
