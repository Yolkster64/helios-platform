# Data governance & analytics: Purview and Fabric (design)

Design + runbook only. **No Purview account and no Fabric capacity exist for this
platform today**; nothing in this document deploys anything. Both lanes are opt-in by
construction (a `deployPurview` / `deployFabric` Bicep parameter defaulting to `false`
lands together with its module only when the owner asks for the deployment). This doc
is the decision record those modules will implement.

## What HELIOS produces that needs governing

| Data | Where it lives | Sensitivity |
|---|---|---|
| Learning-store outcomes (task type, provider, success, latency, truncated output text) | `.helios/learning/outcomes.jsonl` locally (gitignored); Azure Table Storage when `learning.mode: azure` (`config/aihub.json`) | Output text can embed fragments of prompts — treat as internal; never public |
| AIHub/API logs | process stdout / hosting logs | Provider names, latencies; no keys (config carries env-var names only — CLAUDE.md hard rule) |
| Absorption reports | `.helios/absorption/pr-*.json` (gitignored), hosted-workflow artifacts | Build/test output of *untrusted upstream code* — treat contents as untrusted text |
| Governance evidence docs | SharePoint `…/HELIOS/Governance/` tree (live, verified — see `integrations/m365/README.md`) | The M365 side; already inside tenant compliance boundary |

## Purview lane (classification & catalog)

1. **Scope**: register the Azure Storage account backing the `azure` learning mode and
   the Key Vault (`infra/`) as Purview data sources; scan on a weekly schedule.
   Classification targets: free-text columns of the outcomes table (potential prompt
   fragments) → internal-only sensitivity label; everything keyed (provider, task
   type, booleans) is non-sensitive telemetry.
2. **M365 side**: the SharePoint governance tree gets sensitivity labels via the
   normal M365 Purview portal (owner action) — relevant because that tree is Copilot
   grounding material (`integrations/m365/`); a label there flows into what Copilot
   will surface.
3. **Deployment shape (when opted in)**: one `Microsoft.Purview/accounts` resource,
   system-assigned MI, `deployPurview bool = false` param in `infra/main.bicep`,
   Reader + Storage Blob Data Reader role assignments for the scan MI — identity per
   `docs/architecture/IDENTITY_ARCHITECTURE.md`, secrets per the Key Vault custody
   chain (no keys in Bicep outputs, ever).
4. **Explicitly out**: classifying the *repo* (public GitHub is the boundary there —
   secret scanning + push protection already cover it).

## Fabric lane (analytics landing zone)

1. **OneLake as landing zone**: learning outcomes and absorption verdicts land in a
   Fabric Lakehouse for analysis (provider win-rates over time, absorption yield per
   epic). Source of truth stays the hub (`/v1/learning`, `/v1/insights` —
   `src/ai/HELIOS.AIHub.Api`); Fabric is a downstream copy, advisory like everything
   in the learning contract (`source: "absorption-benchmark"` records stay excluded
   from adaptive routing regardless of where they are analyzed).
2. **Ingestion choice: batch, not eventstream.** Outcomes are low-volume JSONL
   (tens/day); a scheduled batch copy (Data Pipeline reading the Table/JSONL) is the
   right cost shape. An eventstream is justified only if fleet telemetry
   (`scripts/fleet/`) starts emitting per-task events at volume — revisit then, not
   before.
3. **Security model**: one `helios-analytics` workspace; Entra security group for
   readers; a service principal (or workspace identity) with least privilege for the
   pipeline; no user-owned credentials in any pipeline definition. Workspace roles:
   Admin = owner only, Member = none, Viewer = the readers group.
4. **Honest gating**: Fabric requires an F-SKU capacity (real monthly cost). Until
   the owner provisions one, the analytics story is served free by
   `helios-ai insights` / `GET /v1/insights` and the Python spoke's outcome
   analytics (`src/ai/python`). The Fabric lane starts when data volume or audience
   outgrows those — that trigger, not enthusiasm, unlocks `deployFabric`.

## Owner-action checklist (when this lane activates)

- [ ] Provision Purview account (or confirm M365 Purview suffices — likely at
      current scale) and register the storage sources.
- [ ] Apply sensitivity labels to the SharePoint governance tree.
- [ ] Provision Fabric capacity + `helios-analytics` workspace; create the readers
      security group.
- [ ] Ask for the `deployPurview`/`deployFabric` Bicep modules — they are written
      then, with what-if evidence, not speculatively now.
