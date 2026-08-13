# Graph connectors & M365 Copilot — API-level reference

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* API shapes verified against Microsoft Learn (2026-08); re-verify
via the Microsoft Learn MCP before relying on a field this file does not list.

## Copilot (Graph) connectors

The repo's connector artifacts: `integrations/m365/graph-connector/connection.json`
(the external connection) and `schema.json` (the item schema).

- **Create connection**: `POST https://graph.microsoft.com/v1.0/external/connections`
  with `{id, name, description}`. `id` is immutable and referenced by the declarative
  agent (`connection_id`) — ours is `heliosplatform`; renaming means recreating.
- **Register schema**: `PATCH /external/connections/{id}/schema` with
  `baseType: "microsoft.graph.externalItem"` and a **flat** `properties` list.
  Registration is a long-running operation (minutes) — poll the operation URL before
  ingesting items; items PUT before the schema completes are rejected.
- **Property attributes**: `isSearchable` (full-text), `isQueryable` (KQL filter),
  `isRetrievable` (returned in results — anything Copilot should quote must be
  retrievable), `isRefinable` (facets; refinable properties cannot be searchable).
- **Semantic labels** connect properties to Copilot's understanding: `title`, `url`,
  `iconUrl`, `lastModifiedDateTime`, `lastModifiedBy`, `createdBy`, `createdDateTime`,
  `authors`, `containerName`, `containerUrl`, `itemPath`. `title` + `url` +
  `lastModifiedDateTime` are the practical minimum for Copilot to cite an item well;
  the declarative-agent `items_by_path`/`items_by_container_*` filters only work if
  the corresponding labels are assigned (schema 1.5 reference, connection object).
- **Permissions (application)**: `ExternalConnection.ReadWrite.OwnedBy` +
  `ExternalItem.ReadWrite.OwnedBy` — the `.OwnedBy` variants scope the app to
  connections it created; prefer them over `.All`. Admin consent required (owner
  action per `integrations/m365/README.md`).
- **Ingest items**: `PUT /external/connections/{id}/items/{itemId}` with `properties`
  (matching the schema), `content` (`text`/`html`), and `acl` (every item needs an
  ACL — `everyone` grant type for org-public docs).

## Declarative agents (M365 Copilot)

The repo's manifest: `integrations/m365/declarative-agent/declarativeAgent.json`,
written to schema **v1.5**; **v1.8 is the latest** — upgrading is a `version` bump
reviewed against the v1.8 reference (nothing we use is deprecated through 1.8).

- Required: `version` (`v1.5`), `name` (≤100 chars), `description` (≤1000),
  `instructions` (≤8000). Unrecognized properties make the whole manifest invalid —
  do not add custom fields.
- `capabilities` array allows at most one of each type. The two we use:
  - `OneDriveAndSharePoint` with `items_by_url: [{url}]` — omitting both
    `items_by_url` and `items_by_sharepoint_ids` grants **all** org SharePoint/
    OneDrive content; always scope.
  - `GraphConnectors` with `connections: [{connection_id}]` — same rule: omitting
    `connections` grants every connector in the tenant.
  - Non-`WebSearch` capabilities require a Copilot license (or metered usage) on the
    user's tenant.
- `conversation_starters`: ≤12 objects of `{title, text}`.
- Packaging: the declarative agent manifest ships inside an M365 app package (app
  manifest + agent manifest + icons, zipped) — Microsoft 365 Agents Toolkit builds
  it; upload is an owner action (admin center → Integrated apps).

## Live-verified tenant facts (2026-08-13, read-only)

Recorded in `integrations/m365/README.md`: tenant `Heli0s.onmicrosoft.com`, verified
via the signed-in tenant admin account; SharePoint search for `HELIOS`
returned 49 documents including `…sharepoint.com/Shared Documents/HELIOS/Governance/`
and a personal `Helios/Governance/{Architecture,Deployment-Evidence,Integration-Fabric}`
tree — the corpus the declarative agent grounds on today, before the connector exists.

## Entra / Graph auth for the connector app

Follow `docs/architecture/IDENTITY_ARCHITECTURE.md` §1's registration pattern
(`scripts/bootstrap/register-entra-app.ps1` prints the exact commands). Client
credentials belong in Key Vault; ingestion automation should use the GitHub OIDC →
Entra federation pattern (§3) rather than a stored client secret.
