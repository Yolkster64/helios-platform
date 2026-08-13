# M365 Copilot tools & plugins — the actions/packaging layer

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* API shapes verified against Microsoft Learn (2026-08); Learn URLs
are cited inline — re-verify via the Microsoft Learn MCP before relying on a field
this file does not list.

Scope: `references/graph-and-copilot.md` covers the **grounding** layer (connector
connection/schema endpoints, declarative agent capability objects, permissions).
This file covers the layer above it: API plugins (actions), Agents Toolkit packaging
and deployment, surfacing behavior, the Copilot Studio alternative, and the
connector *tools* around the agent. Nothing here duplicates that file — read it
first.

## Actions: API plugins on a declarative agent

The declarative agent manifest's `actions` array is the tool surface: each entry is
`{id, file}` where `file` is a path to an **API plugin manifest** inside the same app
package
(<https://learn.microsoft.com/microsoft-365/copilot/extensibility/declarative-agent-manifest-1.8>).
Our manifest (`integrations/m365/declarative-agent/declarativeAgent.json`) has **no
`actions` today, deliberately** — the HELIOS Operator is a knowledge/status agent
whose instructions forbid claiming execution ability (`integrations/m365/README.md`,
"Boundaries").

Plugin manifest facts (the **latest schema is v2.4**,
<https://learn.microsoft.com/microsoft-365/copilot/extensibility/plugin-manifest-2.4>):

- OpenAPI-based: `runtimes: [{type: "OpenApi", auth, spec}]` where `spec.url` points
  at (or `spec.api_description` inlines) the OpenAPI description of the REST API
  Copilot may call; `functions` describe the operations and their response
  rendering.
- Auth carries **no secrets**: `auth.type` is `None`, `OAuthPluginVault`, or
  `ApiKeyPluginVault`, with a `reference_id` resolved from registration done outside
  the manifest — consistent with this repo's no-secrets rule
  (<https://learn.microsoft.com/microsoft-365/copilot/extensibility/plugin-manifest-2.2>).
- v2.2 added `security_info`/`data_handling` attestation per function
  (`ResourceStateUpdate` marks actions needing explicit user confirmation); v2.3
  added `LocalPlugin` runtimes for Office add-in functions
  (<https://learn.microsoft.com/microsoft-365/copilot/extensibility/plugin-manifest-2.3>).
- API plugins are only supported **as actions within declarative agents**, not as
  standalone Copilot plugins
  (<https://learn.microsoft.com/microsoft-365/copilot/extensibility/agents-are-apps>).

**What a HELIOS action could honestly expose — and the hard prerequisite.** The only
candidate API is `helios-ai-api`, and it is **loopback-only by design** (`CLAUDE.md`;
`src/ai/HELIOS.AIHub.Api/ApiEndpoints.cs` per `IDENTITY_ARCHITECTURE.md` §1): no
tenant-reachable endpoint exists today, so there is nothing a plugin's `spec.url`
could point at. The identity-aware ingress of
`docs/architecture/IDENTITY_ARCHITECTURE.md` §1 (Entra resource app + app roles,
EasyAuth/JWT validation in front of the API — FORWARD_PLAN.md tranche T6) must land
**first**; the plugin's `OAuthPluginVault` registration would then target that
resource app, and a status/read action maps to the `AIHub.Read` role. Do not design
an action against `AIHub.Invoke` casually — that role spends provider quota/money
(§1's role table), and `ResourceStateUpdate`-class actions belong in the hub where
the audit trail lives, not behind a chat turn.

## Microsoft 365 Agents Toolkit: packaging & deployment

The declarative agent ships as a **Microsoft 365 app package** — a zip containing
`manifest.json` (the app manifest), the declarative agent JSON it references via
`copilotAgents.declarativeAgents[].file` (exactly one declarative agent per app
manifest today), any plugin manifests + OpenAPI files, and two icons: `color.png`
192×192 and `outline.png` 32×32 (required for validation even though Copilot only
displays the color one)
(<https://learn.microsoft.com/microsoft-365/copilot/extensibility/agents-are-apps>).
Agents Toolkit builds and provisions this package; Responsible AI validation runs at
sideload/publish time
(<https://learn.microsoft.com/microsoft-365/copilot/extensibility/publish>).

- **Versioning**: the app manifest `version` is semver `MAJOR.MINOR.PATCH`; bump it
  on every repackaged upload — it is what distinguishes an update from a re-upload
  (agents-are-apps, "App manifest" table).
- **Sideload (test loop)**: requires the tenant to allow custom app upload — Teams
  admin center → Teams apps → Setup policies → **Upload custom apps = On**
  (<https://learn.microsoft.com/microsoft-365/copilot/agent-essentials/agent-policies/agent-sideload>).
  Toolkit's Lifecycle → Provision does the sideload for the signed-in dev account.
- **Org-wide**: upload the zip in the admin center (Integrated apps → Upload custom
  app, or Agents → All agents → Add agent), choosing the *available-to* audience
  (Publish) and optionally a *preinstalled* audience (Deploy) — start with a test
  group, then the operators group per our runbook
  (<https://learn.microsoft.com/microsoft-365/admin/manage/agent-registry>;
  `integrations/m365/README.md` §2).
- Both are **owner actions** (tenant mutations) per this skill's hard rules; the
  repo holds only the manifests.

## Teams/Outlook surfacing & conversation starters

Once uploaded and assigned, the HELIOS Operator appears in the agent list of the
Copilot surfaces — the right pane of Microsoft 365 Copilot chat (Teams, the
Microsoft 365 Copilot app, Outlook) — with the same chat UI as Copilot itself
(<https://learn.microsoft.com/microsoft-365/copilot/extensibility/overview-declarative-agent>).
Selecting the agent shows its `conversation_starters` as clickable prompt cards on
the agent's start screen; ours are the four in
`integrations/m365/declarative-agent/declarativeAgent.json:20-37` (platform status,
absorption verdicts, architecture, governance evidence). Limits (≤12 starters,
`{title, text}`) are in `references/graph-and-copilot.md`. Starters are hints only —
they prefill a prompt, they don't constrain what users may ask.

## Copilot Studio vs the manifest path this repo took

This repo builds the agent **pro-code**: a hand-authored manifest under source
control, reviewed in PRs. That is the Agents Toolkit path in Microsoft's tool
comparison
(<https://learn.microsoft.com/microsoft-365/copilot/extensibility/declarative-agent-tool-comparison>):

- **Low-code (Copilot Studio) wins when** the agent needs Power Platform
  connectors for plug-and-play API integration, Dataverse-resident knowledge,
  drag-and-drop authoring by non-developers, or Power Platform ALM/DLP governance.
  For knowledge specifically: Copilot connectors index-then-answer with citations;
  Power Platform connectors fetch live data / take actions without copying data —
  the decision guide is
  <https://learn.microsoft.com/microsoft-copilot-studio/knowledge-graph-vs-power-platform-connectors>.
- **The manifest path wins when** you need source control, PR review, CI, and early
  access to new manifest features — exactly this repo's operating model, where the
  agent definition is reviewed like any other artifact.
- **Migration note**: agents built with Agents Toolkit **cannot be imported into
  Copilot Studio** (tool-comparison page, Agents Toolkit cons) — moving to Studio
  means re-authoring instructions/knowledge scoping there, not converting the JSON.
  Keep `declarativeAgent.json` the source of record unless a Power-Platform-side
  requirement (Dataverse, premium connectors, multi-step workflows) forces the
  switch.

## Copilot connector tools around the agent

The connector's API mechanics live in `references/graph-and-copilot.md`; the tools
layer on top:

- **Admin-center enablement is a distinct step**: after the connection + schema are
  registered via Graph, the connection must be enabled for Copilot in the M365 admin
  center (Search & intelligence → Data sources) before the agent's
  `GraphConnectors` capability returns anything (`integrations/m365/README.md`,
  owner runbook step 5; connector setup lives in the admin center per
  <https://learn.microsoft.com/microsoft-365/copilot/connectors/overview>).
- **KQL scoping inside the agent manifest**: each `GraphConnectors` connection
  object takes an optional `additional_search_terms` KQL query filtered against the
  connection's schema fields (they must be `isQueryable`), plus
  `items_by_path`/`items_by_container_name`/`items_by_container_url` filters that
  only work when the corresponding semantic labels are assigned
  (<https://learn.microsoft.com/microsoft-365/copilot/extensibility/declarative-agent-manifest-1.8>;
  label rules in `references/graph-and-copilot.md`). Use `additional_search_terms`
  to keep the HELIOS agent scoped (e.g. to governance/absorption items) if the
  `heliosplatform` connection later ingests broader content.
- **Item-level ACLs are the security boundary**: every ingested item carries an
  `acl`, and Copilot/Search honor it per user — grounding never widens access
  (ingest contract in `references/graph-and-copilot.md`;
  <https://learn.microsoft.com/microsoft-365/copilot/connectors/overview>).

## The M365 MCP read lane this program actually uses

Operationally, sessions in this program reach the tenant through the authorized
claude.ai **Microsoft 365 connector** (MCP) — the read-only lane that produced the
live verification recorded in `integrations/m365/README.md` ("Live verification":
`GET /me`, SharePoint search → 49 documents) and the measured-state row in
`docs/architecture/ENTERPRISE_AI_CONNECTIONS.md` §0. Use it to *verify* tenant
state (corpus existence, search results, connection visibility) before and after
owner runbook steps. It does not change the hard rule: **tenant mutations —
consent, connection creation, schema registration, app upload — are owner actions**
(`SKILL.md`, "Hard rules"); the MCP lane is for reads and evidence, not
administration.
