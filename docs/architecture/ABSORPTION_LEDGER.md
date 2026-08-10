# Upstream Absorption Ledger

The consolidated map of upstream `M0nado/helios-platform` PR history (195 PRs, #1–#295)
distilled into 18 theme epics. Each epic bundles the broad idea behind several upstream
PRs; the per-PR benchmark status lives in `config/absorption/pr-watchlist.json` and the
evidence loop is `docs/architecture/ABSORPTION_PIPELINE.md`. Upstream is read-only —
benchmark provenance, never a write target.

> **GitHub Issues**: this fork has Issues disabled (fork default; the API write to flip
> it is proxy-blocked). Once **Settings → General → Features → Issues** is enabled on
> `Yolkster64/helios-platform`, each epic below becomes one GitHub issue verbatim
> (labels in parentheses; `absorption` on all). Until then this page is the system of
> record, published to the wiki by the Wiki Sync workflow.

**Status legend** — per epic: `open` (not started), `tranche-1` (first integration pass
landed or in flight), `audit-first` (safety carve-out; documentation before any code).
Per PR (watchlist): `candidate → benchmarked → absorbed | rejected`.

---

## E1 — Unified `setup-all` control-fabric CLI (`enhancement`) — open

Ten upstream PRs circle one idea: a single `setup-all` entrypoint that brings the whole
control fabric to readiness — inventory, hardened wrappers, persisted board config —
instead of a dozen per-subsystem scripts. Ours would wrap the existing auth bootstrap,
fleet topology, and board-setup scripts (PS7 wrapping the C# CLI, per repo convention).

- PRs: #270 #271 #273 (the entrypoint, three takes), #251 #236 (inventory), #280
  (scaffold), #265 #268 (orchestration stability + persisted board config), #252
  (hardened wrappers, Windows tool discovery), #266 (build-blocker fixes), #213
  (bootstrap verify-only auth — **ported**: `--verify-only`/`-VerifyOnly` on the
  connect-github/connect-azure/cloud-shell-setup bootstrap scripts; upstream's XDG move
  was N/A — no hardcoded `~/.local` tool paths exist here)
- Extracts: one command surface; readiness inventory (dedupe with E14); persisted
  board-config artifact pattern
- Risks: competing drafts — pick one shape, credit the rest; heavy tree divergence

## E2 — XCore9 evaluation service & runtime matrix (`ai-hub`) — open

A bounded evaluation service (F# analytics, stable contracts), a governed runtime
matrix (local/Windows/Docker) with smoke evidence, and KNAA scoring telemetry feeding
policy gates — the upstream's most substantial engineering cluster, mapping onto our
fleet review pool and learning loop's Quality field.

- PRs: #222 (eval service), #223 (robust service + analytics fixes + CI), #294
  (runtime matrix), #253 (KNAA scoring telemetry)
- Extracts: service contracts, F# scoring modules, runtime-matrix definition,
  smoke-evidence pattern, scoring rubric
- Risks: pre-consolidation layout; policy gates assume upstream CI

## E3 — Hermes/XCore contracts & specialization (`ai-hub`) — open

Versioned federation contracts between Hermes fleets and XCore pools, per-pool
specialization, and canonical x-tier environment definitions — to reconcile against our
live `config/fleet/fleet-topology.json` v2 rather than replace it.

- PRs: #250 (v1 contracts + x-tier migration), #267 (specialization contracts + policy),
  #269 (governance contracts + CI collaboration gates), #205 (governed contract v1
  draft), #126 #125 (working-steps guides)
- Extracts: contract fields we lack; lane-discipline refinements
- Risks: contract divergence — ours is v2 and running

## E4 — Governed capability profiles & plan validation (`enhancement`) — open

Fail-closed capability profiles with validators, JSON-Schema validation of operator
plans, and a 50-capability backlog taxonomy — governance hardening that maps to our
fleet pools' tool allowlists (the review pool is read-only by design).

- PRs: #295 (capability profiles + validator), #292 (operator JSON Schema validation),
  #285 (knowledge discovery + capability backlog), #248 (lifecycle policy), #254
  (AI collaboration contract), #256 (experience fabric v2 contracts)
- Extracts: profile validator, schema harness (hardens config/fleet + config/absorption
  too), the capability-backlog taxonomy as roadmap seed
- Risks: security model differs; absorb taxonomy and validators, not the runtime

## E5 — Azure activation hardening: MI→KV custody, OIDC (`infra`) — open

Managed-identity→Key-Vault secret binding, token audience hardening, and immutable
plan/deploy custody — extending our OIDC + Key Vault stack with audit custody
discipline on the deploy path.

- PRs: #224 (activation custody), #260 (completion hardening), #193 (OIDC resolution
  fix), #182 (dev OIDC + what-if reconciliation), #100 (cloud auth hardening), #89
  (OIDC guards + orchestration inventory)
- Extracts: custody/audit pattern, audience-hardening checks, OIDC guard patterns
- Risks: assumes upstream pipeline; adapt to `helios-deploy.yml`

## E6 — Private Azure edge & segmented network (`infra`) — open

Governed private-edge topology and segmented networking beyond our current zero-inbound
NSG — plus the reviewed-subnet discipline for production deployments.

- PRs: #211 (private edge + segmented network), #218 (reviewed Container Apps subnet)
- Extracts: segmentation shape, subnet-review workflow pattern
- Risks: large infra surface; upstream targets Container Apps, we deploy Foundry + VMSS

## E7 — Repository integrity & submodule governance (`build-ci`) — open

A repository-integrity validator and declaration-audit replacing automated submodule
sync, with a fail-closed pinned-submodule approval gate — matching our deletion of the
inert `.gitmodules` and giving us the governance to bring submodules back safely if
ever needed.

- PRs: #215 (approval gate), #214 (integrity validator + declaration audit), #212
  (integrity validation in workflows), #217 (integrity CI on PRs), #216 (remove
  periodic sync), #246 (workflow/submodule checkout repairs)
- Extracts: one coherent integrity-validator design (dedupe #214/#212/#217)
- Risks: irrelevant until a real submodule exists — keep as dormant governance

## E8 — CI/test stabilization & test-ownership lanes (`build-ci`) — open

Unified test ownership, centralized test tool versions, stable CI lanes, and the long
tail of workflow repairs — the upstream fought the same two-era workflow zoo we have;
absorb the organizing ideas.

- PRs: #219 (ownership + versions + lanes), #244 #243 (xUnit2031 fixes), #257
  (workflow/schema stabilization), #281 #282 (entrypoint + regression fixes), #170
  (exact PS syntax validation), #116 (quality gates + summary checks), #92 #86 #85
  (portable CI + validations)
- Extracts: test-ownership map, tool-version centralization, portable-lane split
- Risks: lane names differ; our baseline-gated PS validation already covers #170's goal

## E9 — One-button launcher & packaging (`enhancement`) — open

A self-contained one-button HELIOS launcher with packaging scripts and tests — local
bring-up (build + API + fleet) as a single action, aligned with our Docker/compose and
start-fleet stories.

- PRs: #290 (launcher + packaging + tests — primary), #289 (sibling), #291 (automation
  guide covering start/levels/routing/recovery)
- Extracts: launcher UX, packaging checks, the guide's structure
- Risks: packaging targets upstream layout

## E10 — Read-only Helios.Connect CLI (`enhancement`) — open

A zero-mutation, read-only connect CLI/library with strict execution guardrails — the
guarantees (not a second CLI) complement our loopback-guarded API for safe hosted
inspection.

- PRs: #221 (CLI + core library), #229 (hardening follow-up)
- Extracts: read-only enforcement pattern, persistence guardrails
- Risks: overlaps `helios-ai status`/`routing`; absorb guarantees into existing surfaces

## E11 — Reliability evidence harness (`build-ci`) — open

An evidence harness with a development-only controlled failure injector — deliberate
exercise of fallback chains and circuit breakers, with evidence reports in the same
spirit as our absorption reports.

- PRs: #220
- Extracts: evidence report shape, dev-only injector gating
- Risks: injector must stay dev-only and fail closed

## E12 — Integration lanes & merge-train tooling (`build-ci`) — open

Stable/preview integration lanes, umbrella integration trains, consolidation reports,
and merge-automation CLI — the upstream's machinery for exactly the consolidation this
ledger performs; absorb the reporting shapes.

- PRs: #293 (stable/preview lanes), #287 (branch-intelligence exports + umbrella
  trains), #286 (five-lane reset + backlog sync), #264 (consolidation reports), #70 #69
  (merge automation + plan-runner), #66 (merge-source manifest), #64 (integration PR
  template)
- Extracts: lane definitions, consolidation-report format, integration PR template
- Risks: train branches reference upstream-only refs

## E13 — Branch intelligence & repository analytics (`ai-hub`) — open

Branch-intelligence scoring (remote-priority, remote filtering) and a
RepositoryAnalytics project — analytics that could drive which upstream work we absorb
next, slotting into our F# domain.

- PRs: #141 #134 (remote-priority), #140 (RepositoryAnalytics + Hermes default
  handling), #115 (branch integrator + docs + tests), #106 (integration runbook), #102
  (integration report)
- Extracts: priority-scoring model, analytics data model
- Risks: new projects must join `HELIOS.sln` and the root csproj glob guards

## E14 — Build graph & readiness tooling (`build-ci`) — tranche-1

Build-graph verify/readiness commands, required/optional tool split, repo-local tool
resolver, compile checkers, and result reporting — the upstream's dev-loop quality
tooling.

- PRs: #136 #138 (readiness verify — **ported**: `scripts/build/verify-readiness.ps1`,
  required/optional split, human table + `-Json`), #137 (python compile checker —
  **ported**: `compileall` gate in `python-spoke.yml` before pytest), #130 (repo-local
  tool resolver), #139 #133 #131 #135 (build-graph refinements)
- Extracts: required/optional split, resolver precedence, native-interop smoke
- Risks: build-graph itself is upstream-specific; port ideas only

## E15 — Model registry & routing validation (`ai-hub`) — tranche-1

A model registry with schema, deprecated-model replacement, and tightened
routing/fallback validation.

- PRs: #110 (**ported**: `config/schemas/model-catalog.schema.json` +
  `scripts/build/validate-model-catalog.py` wired into `dotnet-build.yml`; catalog
  refreshed to current families; `bulk_processing` routing lane), #97 #96 (fleet-model
  wiring context)
- Extracts: registry schema, current families, routing validation
- Risks: model IDs move fast; the schema is the durable part

## E16 — AIHub unified control plane: dashboards & reporting (`ai-hub`) — open

Five upstream takes on an AIHub control plane — workflows, reports, analysis agents,
dashboards, engine contracts. We already run the hub itself; mine these for dashboard
data shapes and report cadence our status-dashboard workflow lacks.

- PRs: #145 (most complete), #143 #144 (siblings), #122 #121 (command center), #128
  #127 (registries + operator tooling)
- Extracts: dashboard data shapes, report cadence
- Risks: very large PRs; absorb shapes, never the parallel implementation

## E17 — Docs & onboarding (`enhancement`) — tranche-1

Canonical setup guide, owner-first checklist, full-stack documentation, and wiki-sync
refinements — the onboarding layer.

- PRs: #210 (**ported**: `docs/PROJECT_SETUP.md` grounded in the current tree), #65
  (**ported**: `docs/OWNER_START_HERE.md` incl. the enable-Issues step), #247 (Copilot
  setup + merge readiness), #114 (full-stack docs + validators), #103 (owner-first
  governance baseline), #117 (wiki sync — compare with our newer Wiki Sync, likely
  reject)
- Extracts: guide + checklist structure, any missing wiki-sync behaviors
- Risks: none beyond staleness; docs ground in the current tree

## E18 — Windows boot security / WinRE recovery (`audit-first`) — audit-first

Guarded Windows boot security, rootkit recovery, WinRE bridges, and boot-time method
implementations. **Safety carve-out**: PR #4's safety disposition already rejected
unsigned SYSTEM WinRE scheduled tasks and related mutations. This epic documents the
threat model and the governed subset only — signed, consent-gated, human-reviewed —
and integrates no code in this pass.

- PRs: #166 (guarded boot security), #186 (environment repair consolidation), #163
  (XTier WinRE bridge), #108 (boot-time methods + simulation guards)
- Extracts: threat-model documentation only
- Risks: the carve-out is the point; nothing lands without an explicit signing and
  consent story

---

## Coverage

18 epics span **~90 distinct upstream PRs** (the remainder of the 195 are duplicates of
these themes, dependency bumps, or superseded merge-train snapshots). Tranche 1 (E14,
E15, E17 and the E1 bootstrap port) has **landed at this branch head** — every ported
file exists in the tree with its benchmark report as evidence, and branch CI validates
them; a port is only ever marked so under that rule. Every other epic holds `candidate` watchlist entries
ready for `scripts/absorption/absorb-pr.ps1`. Fleet-scale benchmarking: seed absorb
commands onto the `xcore-infra` board via the lock-aware `--enqueue` (see
ABSORPTION_PIPELINE.md).
