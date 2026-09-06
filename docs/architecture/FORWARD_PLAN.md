# HELIOS Forward Plan

The sequenced go-forward plan. Builds on `ROADMAP_MULTI_LLM.md` (PR-level roadmap and
the known-red workflow inventory), the absorption ledger epics
(`ABSORPTION_LEDGER.md`), `GUI_UPGRADE_PLAN.md`, `IDENTITY_ARCHITECTURE.md`,
`HYBRID_CLOUD_ARCHITECTURE.md`, and `GOVERNANCE_PURVIEW_FABRIC.md`. Each tranche names
its **owner lane**: *Claude session* (this stewarded loop), *Copilot agent*
(assign-to-Copilot epics reviewed and merged through the multi-LLM loop), *fleet*
(Hermes/XCore batch work), or *owner* (human-only: consent, secrets, capacity).

## Operating model (proven, keep)

The multi-LLM review loop is live and has merged real work: Copilot authors from epic
issues → Claude session reviews/fixes on the `copilot/*` branch → Codex review waves
until 👍 → merge when checks are green. Same protocol in reverse for session-authored
PRs (`request_copilot_review` + Codex waves). Engine candidates and learning data stay
advisory; nothing self-executes.

## Tranche sequence

### T4 — .NET 10 platform (landed on this branch)

Retargeted to net10.0 LTS (net8.0 EOL 2026-11-10) with an allowed-to-fail
net11-preview CI lane; `src/gui` follows once the pinned Windows App SDK documents
net10 support. GA flip ~Nov 2026 as a reviewed TFM bump.
Knowledge: `csharp-orchestrator/references/dotnet-10-and-11.md`. **Owner lane:
Claude session.**

### T5 — GUI shell completion (plan of record: `GUI_UPGRADE_PLAN.md`)

P1 canonical tokens + type ramp → P2 `GET /v1/metrics` REST seam → P3 AIHub metrics
cards + Win2D sparklines → P4 Routing page → P5 Fleet page → P6 effects. Adobe asset
track (icon + theme board) in parallel. **Owner lane: Claude session dispatching
ui-designer/theme-designer/ux-reviewer/gui-perf-profiler agents; P2 is
Copilot-assignable.**

### T6 — Identity hardening to done (runbook: `IDENTITY_ARCHITECTURE.md`)

Owner executes the ingress app registration (`register-entra-app.ps1 -Apply`) and MI
grants; session wires EasyAuth/JWT validation in front of `helios-ai-api` and demotes
`HELIOS_API_ACCESS_KEY` to local dev; absorption epic E5/#18 (Key Vault custody)
closes on the same pattern. **Owner lane: owner + Claude session.**

### T7 — M365 Copilot go-live (scaffold: `integrations/m365/`)

Owner: connector app consent, connection + schema registration, agent package upload.
Session: ingestion automation for docs/absorption verdicts via the OIDC→Entra
federation pattern (no stored client secret), then a scheduled refresh workflow.
**Owner lane: owner first, then Claude session.**

### T8 — Absorption program next batch (ledger epics)

Continue the watchlist → hosted benchmark → verdict loop; Copilot-assign the next
epic batch the way #95/#96/#97 were run (E-numbered issues on the board). The
`maxConcurrentLanes` caps and the absorb-pr credential guard are now enforced —
batch runs stay inside them. **Owner lane: Copilot agent + fleet, Claude session
reviewing.**

### T9 — GitHub governance & devtools lane ("full github control")

What actually exists vs what is scriptable, honestly: board custom fields + item
wiring are real GraphQL (`scripts/board-setup/`, incl. `add-epics-to-board.ps1`);
views/templates/automation are API-impossible and documented as manual click-paths.
**Landed this tranche, in-repo**: `main` ruleset JSON
(`.github/rulesets/main.json`, required checks pinned to the truthful job-level
gates) + `scripts/github/apply-rulesets.ps1` (dry-run by default, idempotent by
ruleset name), CODEOWNERS mapping the agent lanes, Dependabot policy
(nuget/actions/pip/docker, weekly, grouped), PR + issue templates, the real status
dashboard + Pages publication pair (`status-dashboard.yml` / `pages-dashboard.yml`),
and label-gated auto-merge (`auto-merge.yml`, `automerge` label).
**Also landed, in-repo (auth & connector automation)**:
`scripts/bootstrap/auth-doctor.ps1` (report-only by default; `-Apply` adds
non-interactive repair only; the linear/slack/sharepoint/azure-devops connector
lanes are verify-only and never gate the exit code), the `auth-broker` and
`github-operator` agents, the MCP `helios_auth_status_get` tool (diagnose-only),
and the connector knowledge home (`connector-integrations` skill +
`connector-steward` agent). **Remaining owner
clicks**: run `apply-rulesets.ps1 -Apply`, enable Pages (Source: GitHub Actions),
enable "Allow auto-merge" in repo settings — click paths in
`CONNECTIONS_SETUP.md` § GitHub governance; the connector secrets and tenant
admin consent below stay owner-only — the doctor reports them, it never performs
them. Merge-queue evaluation stays deferred
until the required checks prove stable. **Owner lane: Claude session; ruleset
enablement is an owner click.**

### T10 — RL / learning experiments (advisory-first, per the E28 carve-out)

`Yolkster64/rl` (NeMo-RL lineage) is the toolkit reference. Scope: offline experiments
over the learning store's outcome data (provider win-rates → routing suggestions
surfaced in `/v1/insights`), never auto-applied — `adaptiveRouting` stays opt-in;
training runs never auto-execute. Prereq: enough recorded outcomes (learning is now
enabled record-only).
**Landed on this branch (fleet tandem learning)**: the fleet→hub learning loop —
`helios_agents` `fleet-collect`/`fleet-summary` (board outcomes recorded with
`source: "fleet-lane"`, provider `pool:<name>`), the one-command cycle
`scripts/fleet/learn-fleet.ps1` → `.helios/fleet/learning-report.json`, and the
informational weekly `fleet-learning.yml` lane (stub cycle proves wiring, not
model quality) — plus the `helios-ai fleet-plan` / MCP `helios_fleet_plan_get`
advisory (learned vs configured chain per pool × task type, scored on organic
hub history only; fleet-lane records never steer provider chains) and the
opt-in Azure learning backend (`deployLearningStorage` →
`AZURE_LEARNING_TABLE_ENDPOINT`, off by default). Design write-up:
`HERMES_FLEET_AND_XCORE.md` § Tandem learning. Owner-gated: the what-if +
deploy that turns the Azure backend on. **Owner lane: fleet + Python spoke,
human approves any routing change.**

### T11 — Purview/Fabric activation (design: `GOVERNANCE_PURVIEW_FABRIC.md`)

Blocked on owner capacity decisions by design; the trigger is data volume/audience,
not enthusiasm. **Owner lane: owner.**

## Ecosystem repos (what feeds what)

| Repo | Feeds | Tranche |
|---|---|---|
| `WindowsDeveloperConfig` | PS7 dev-box workloads; cross-llm-shell workload (roadmap PR5) | T9 |
| `ai-hub-knowledge` | Bicep knowledge-store pattern for AIHub absorption | T8 |
| `linear` (fork) | Connector reference for the one-directional Linear sync | done (runbook note in `CONNECTIONS_SETUP.md`) |
| `azure-sdk-for-net` (fork) | Source-level verification for provider/Foundry SDK claims | T4/T8 |
| `rl` (fork) | RL toolkit for advisory routing experiments | T10 |
| `monado-blade`, `helios` (predecessors) | Design mining only (see `GUI_UPGRADE_PLAN.md` provenance rule) | T5 |

## Standing owner actions (unchanged, still open)

- `LINEAR_API_KEY` + `SLACK_WEBHOOK_URL` repo secrets (connectors run dark until set).
- Disable Linear→GitHub issue sync for team John (click path in
  `CONNECTIONS_SETUP.md`) — prevents the duplicate-issue loop recurring.
- Entra consent steps as T6/T7 reach them.

## Known-red workflows

The inventory and repair status live in `ROADMAP_MULTI_LLM.md`; nothing in this plan
adds a required check that is currently red, and the net11-preview lane is explicitly
allowed-to-fail.
