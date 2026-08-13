# Fabric & Power BI — the analytics presentation layer (design)

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Microsoft claims verified against Microsoft Learn (2026-08); URLs
cited inline — re-verify via the Microsoft Learn MCP tools before relying on anything
this file does not list.

Scope: **extends** `docs/architecture/GOVERNANCE_PURVIEW_FABRIC.md` — the decision
record that owns the Fabric lane (OneLake landing zone, batch-not-eventstream
ingestion, the `helios-analytics` workspace security model, and the honest F-SKU
gate). This file adds only the layer that doc deliberately leaves out: **Power BI on
top of the designed Lakehouse** — semantic models, storage mode, report candidates,
licensing gates, and embedding. Nothing here changes the trigger: no Fabric capacity
exists today, and the free lane serves until volume or audience outgrows it.

## The data shape a semantic model would sit on

The fact record is `RoutingOutcome`
(`src/ai/HELIOS.AIHub/Learning/LearningStore.cs:7-48`): `timestamp`, `taskType`,
`provider`, `model`, `success`, `latencyMs`, `costUsd`, optional `quality` ([0,1] or
null = unrated), optional `pool` (fleet attribution), optional `source` (advisory
provenance — null means a live hub outcome). Absorption verdicts land as
`.helios/absorption/pr-*.json` (data table in `GOVERNANCE_PURVIEW_FABRIC.md`). The
hub's own aggregate view is `GET /v1/insights`
(`src/ai/HELIOS.AIHub.Api/ApiEndpoints.cs:107-130`), returning `InsightsResponse`
(`src/ai/HELIOS.AIHub.Api/ApiModels.cs:72-77`): per-taskType Python-spoke `Summary`
and `Drift` JSON, or `Available=false` with a hint.

Model shape that fits (semantic-model concepts:
<https://learn.microsoft.com/power-bi/connect-data/service-datasets-understand>):

- One fact table (outcomes), one per absorption verdicts. `provider`, `taskType`,
  `pool`, `model` are low-cardinality strings — degenerate dimensions on the fact are
  fine at this volume; a date dimension is the only real dimension table worth adding.
- Measures: win rate (`success` ratio), p50/p95 `latencyMs`, `costUsd` sum, `quality`
  average **over rated rows only** (null means unrated, not zero —
  `LearningStore.cs:31-32`).
- **`source` must be a first-class slicer, never filtered away silently.** The
  advisory contract follows the data wherever it is copied (`SKILL.md`, hard rules):
  `source`-tagged records (e.g. `absorption-benchmark`) are excluded from adaptive
  routing at the hub (`src/ai/HELIOS.AIHub/AIHub.cs:220-223`) and a report that blends
  them into provider win-rates unlabeled would launder advisory data into
  operational-looking numbers.

## Direct Lake vs import, for this shape

Learn's comparison (<https://learn.microsoft.com/fabric/fundamentals/direct-lake-overview>):
Direct Lake reads the Lakehouse delta tables from OneLake directly — a "refresh" is
*framing* (metadata only), not a data copy — but its licensing row is **Fabric
capacity (F SKUs) only**; import mode copies data into the model, needs scheduled
refresh, and runs on **any** license
(<https://learn.microsoft.com/power-bi/connect-data/service-dataset-modes-understand>).

The honest call for this program: outcomes are **tens of rows per day**
(`GOVERNANCE_PURVIEW_FABRIC.md`, "batch, not eventstream"), so import's refresh cost
is trivial — Direct Lake wins here not on volume but on **not maintaining a second
copy and refresh schedule** once the Lakehouse exists. And since the Power BI layer
only activates together with the Fabric capacity (same trigger, below), **Direct Lake
on the Lakehouse tables is the default; import is the fallback** if reports must
outlive a paused/trial capacity. Set the model's *Direct Lake behavior* property
deliberately — it controls DirectQuery fallback (same overview page) — and prefer
failing loudly over silently falling back for a dataset this small.

## Report candidates (in the order they earn their keep)

1. **Provider win-rate over time** — `success` ratio by `provider` per week, sliced
   by `taskType` and `source`; the visual twin of what `helios-ai insights` /
   `/v1/insights` answers textually (summary + drift) today.
2. **Absorption yield per epic** — verdict outcomes from `.helios/absorption/`
   grouped by epic over time; pairs with the advisory-slicer rule above since these
   are precisely the `source`-tagged rows.
3. **Fleet utilization** — outcomes per `pool` plus fleet telemetry, only meaningful
   if `scripts/fleet/` telemetry starts landing at volume (the same condition the
   GOVERNANCE doc names for eventstreams — one trigger, both features).

Each candidate duplicates a question the free lane already answers as text; the
reports justify themselves only when the *audience* widens beyond the operators who
can run `helios-ai insights`.

## Licensing gates (capabilities, not prices)

From <https://learn.microsoft.com/fabric/enterprise/licenses>:

- **Authoring**: creating Power BI items in any workspace other than My workspace
  requires a **Pro** license — the owner-author needs Pro regardless of capacity.
- **Viewing**: free-license users can view Power BI content only when the workspace
  sits on **F64 or larger** (with a workspace Viewer role); on smaller F SKUs every
  viewer needs **Pro or PPU**.
- **Direct Lake**: Fabric capacity SKUs only (Direct Lake overview, licensing row).
- **PPU** (Premium Per User): premium features per user, but PPU-published content is
  only consumable by other PPU users
  (<https://learn.microsoft.com/power-bi/enterprise/service-premium-per-user-faq>) —
  a dead end for "share with the org", occasionally right for a two-person analyst
  lane.

Implication for `helios-analytics`: the floor is a small F SKU + one Pro author, with
viewers licensed individually; **F64 is an audience-size decision, not a default**.

## Embedding, riding the identity architecture

- **Embed for your organization** (user owns data): viewers sign in interactively
  with their own Entra identity — the natural fit for an internal ops surface (a
  future WinUI shell page embedding a report parallels the delegated
  `AIHub.Access`/interactive lane in `IDENTITY_ARCHITECTURE.md` §1)
  (<https://learn.microsoft.com/power-bi/developer/embedded/embedded-analytics-power-bi>).
- **Embed for your customers** (app owns data): a **service principal** — Entra app +
  security group, the Power BI tenant admin setting enabled, and the SP added to the
  workspace; Learn explicitly recommends a **certificate over an application secret**
  (<https://learn.microsoft.com/power-bi/developer/embedded/embed-service-principal>).
  That is exactly the certificate-in-Key-Vault pattern documented for
  `helios-ops-automation` in `references/tenant-administration.md` ("Access tiers");
  custody rules per `IDENTITY_ARCHITECTURE.md` §2 — no credential in files, ever.
- **Pipeline/data-side identity**: the ingestion pipeline's connections should use a
  **Fabric workspace identity** rather than a user-owned credential
  (<https://learn.microsoft.com/fabric/security/workspace-identity>) — the same
  no-user-credentials rule the GOVERNANCE doc's security model already states.

## Trigger discipline (unchanged, restated)

The free lane — `helios-ai insights`, `GET /v1/insights`, and the Python spoke's
outcome analytics — serves until **data volume or audience** outgrows it
(`GOVERNANCE_PURVIEW_FABRIC.md`, "Honest gating"). The Power BI layer lands together
with `deployFabric` and its capacity, not before; provisioning capacity because
dashboards are pleasant is exactly the enthusiasm the decision record rules out.
Advisory stays advisory wherever the data lands — including in a semantic model.
