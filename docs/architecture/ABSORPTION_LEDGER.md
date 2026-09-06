# Upstream Absorption Ledger

The consolidated map of upstream `M0nado/helios-platform` PR history (195 PRs, #1–#295)
distilled into 40 theme epics: E1–E18 cover the recent era (#151–#295), E19–E40 the
early era (#1–#151). Each epic bundles the broad idea behind several upstream
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

## E5 — Azure activation hardening: MI→KV custody, OIDC (`infra`) — tranche-1

Managed-identity→Key-Vault secret binding, token audience hardening, and immutable
plan/deploy custody — extending our OIDC + Key Vault stack with audit custody
discipline on the deploy path.

- PRs: #224 (activation custody), #260 (completion hardening), #193 (OIDC resolution
  fix), #182 (dev OIDC + what-if reconciliation), #100 (cloud auth hardening), #89
  (OIDC guards + orchestration inventory)
- Extracts: custody/audit pattern, audience-hardening checks, OIDC guard patterns
- Risks: assumes upstream pipeline; adapt to `helios-deploy.yml`
- Landed (tranche-1): `helios-deploy.yml` pins the OIDC audience
  `api://AzureADTokenExchange` on `azure/login`, names each deployment per run, and
  seals the what-if plan / apply result into a SHA-256-checksummed, retained artifact
  with a run-identity manifest (immutable plan/deploy custody). The invariants
  (audience hardening, OIDC guard, no stored client secret, custody artifact) are
  enforced by `scripts/validation/validate_deploy_custody.py` via the
  `deploy-hardening-contract.yml` workflow. The MI→KV custody chain itself is the
  already-wired `Key Vault Secrets User` grant in `infra/modules/keyvault.bicep`
  (`docs/architecture/IDENTITY_ARCHITECTURE.md` §2).

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
  tool resolver — **ported**: `scripts/build/tool-resolver.ps1` + readiness/setup-all
  reporting), #139 #133 #131 #135 (build-graph refinements)
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

## E19 — USB quick-start installer & customization (`enhancement`) — open

The founding PRs: a bootable quick-start USB installer and the customization &
configuration infrastructure around it — HELIOS's WinPE-era origin as a Windows
deployment tool, before the AI hub existed. The customization-profile idea is the
part worth mining; the installer targets a tree that no longer exists.

- PRs: #1 (the quick-start USB installer itself), #2 (customization & configuration
  infrastructure around it)
- Extracts: customization-profile shape, quick-start UX outline
- Risks: WinPE/USB era predates the current tree; expect nothing to apply verbatim

## E20 — Orchestration backbone & Hermes autosetup (`ai-hub`) — open

The first orchestration layer: a HELIOS/HERMES backbone with Azure CLI bootstrap,
later joined by an autosetup generator producing scripts, a manifest, and a workflow
— the direct ancestor of today's fleet topology and bootstrap scripts.

- PRs: #61 (orchestration backbone + Azure CLI bootstrap), #105 (Hermes autosetup
  generator: scripts, manifest, workflow)
- Extracts: autosetup manifest shape; bootstrap steps our connect scripts lack
- Risks: superseded by fleet-topology.json v2 and the current bootstrap; deltas only

## E21 — Consolidation automation: manifests, plan-runner, merge CLI (`build-ci`) — open

The early era's branch-consolidation machinery: merge-source manifests, a
plan-runner, a merge-automation CLI, manifest validation with build/test discovery,
and the first umbrella consolidation — the same idea E12 revisits in the recent era.
Absorb one coherent design across both epics.

- PRs: #69 (manifest + plan-runner + docs), #70 (merge-automation CLI + branch
  consolidation guide), #66 (MERGE_SOURCE_MANIFEST + register inputs), #93 (manifest
  validation + build/test discovery), #59 (first umbrella: AIHub, C# environment,
  WinUI3 USB wizard, integration manifests)
- Extracts: manifest schema, plan-runner sequencing, validation checks — deduped with
  E12, which lists #69/#70/#66 from the recent-era side
- Risks: two eras of drafts; pick one shape, credit both

## E22 — Deep-AI automation orchestrator & integration planner (`ai-hub`) — open

A "deep automation" cluster: an automatic AI & Azure integration planner with
profiles, a deep-AI orchestrator with inventory/workflow/docs, control-plane
scripts, and submodule consolidation tooling. The planner profiles and inventory
model are the durable ideas; the orchestrators are era-specific.

- PRs: #71 (integration planner with profiles), #72 (deep-AI orchestrator: inventory
  + workflow + docs), #73 (deep AI & workflow automation), #77 (automation workflows
  + control-plane scripts + submodule consolidation tooling), #68 (SRE Agent
  deployment automation docs and assets)
- Extracts: planner profile shape, inventory model; submodule tooling defers to E7's
  governance
- Risks: orchestrators assume the early tree; nothing here may auto-execute

## E23 — Local AIHub X-Tier control modules (`ai-hub`) — open

Local X-Tier control modules inside the AIHub — the earliest appearance of the
x-tier concept that E3's canonical environment definitions later formalize. Evaluate
against the live fleet topology, not as new modules.

- PRs: #74 (local AIHub X-Tier control modules)
- Extracts: x-tier module boundaries as context for E3's contracts
- Risks: predates the Hermes/XCore contract era; likely superseded by E3

## E24 — Workflow modernization & action-pin upgrades (`build-ci`) — open

The early era's workflow hygiene: pipeline stabilization and linting, actions
upgraded to v4, standardized CI/CD, an autonomous preflight workflow with
cache/monitoring improvements, and removal of deprecated pins.

- PRs: #75 (stabilize pipelines + workflow linting), #82 (actions v4 + platform
  automation + standardized CI/CD), #83 (action-version bumps + github-system
  workflow + consolidation tooling), #107 (autonomous preflight workflow +
  cache/monitoring), #142 (remove deprecated action pins)
- Extracts: preflight and cache/monitoring patterns our workflows lack
- Risks: our workflows are already newer; mine for gaps only

## E25 — .NET inventory & automerge readiness (`build-ci`) — open

A .NET inventory plus automerge readiness checks, with orchestrator unit tests wired
into CI — readiness-as-a-gate ahead of any automatic merge; cousin to E14's
verify-readiness and E21's merge automation.

- PRs: #76 (.NET inventory + automerge readiness checks + orchestrator unit tests
  in CI)
- Extracts: readiness criteria and inventory fields to fold into verify-readiness
- Risks: automerge stays off the table — checks only; nothing merges automatically

## E26 — Phase-docs consolidation & AI-path hardening (`enhancement`) — open

Four takes on one combined change: consolidate the phase docs, harden the AI Hub's
HTTP paths, fix IntelligentCache locking, and run an AI-performance-security scan.
The cache-locking and HTTP-hardening fixes are the valuable part if that code still
exists anywhere relevant; otherwise only the doc-consolidation pattern survives.

- PRs: #78 #79 #80 #81 (quadruplet: phase-doc consolidation + AI Hub HTTP-path
  hardening + IntelligentCache locking fix + AI-Performance-Security scan)
- Extracts: cache-locking and HTTP-hardening fixes if the code survives anywhere
  relevant; else the doc-consolidation pattern only
- Risks: four competing drafts — diff before absorbing; the touched code may be gone

## E27 — Portable core CI: Linux lanes & guardrails (`build-ci`) — open

Making the core build and test on Linux: portable-core CI coverage, portable tests,
hardened script/JSON validation, a portable Ubuntu job with guardrails, and skip
logic for tests that would rebuild the full core or hit missing ProjectReference
targets — the direct ancestor of our Linux-first `HELIOS.sln` lane.

- PRs: #85 (fix Linux CI coverage for portable core), #86 (portable core + portable
  tests + script/JSON validation hardening), #92 (portable Ubuntu CI job +
  guardrails + validations), #94 (skip Linux tests that would rebuild the full
  core), #62 (skip tests when ProjectReference targets missing)
- Extracts: portable-lane split and skip guards (E8 lists #85/#86/#92 too; dedupe)
- Risks: our HELIOS.sln exclusion policy already encodes the lesson; guard details
  only

## E28 — ltrain local training entrypoint (`ai-hub`) — open

A local training entrypoint (`ltrain`) — the one early PR reaching toward on-box
model training. Training runtimes are evaluate-carefully per repo policy: catalog
the entrypoint as an advisory engine candidate and nothing more.

- PRs: #87 (ltrain local training entrypoint)
- Extracts: entrypoint UX as an advisory engine-catalog entry only
- Risks: training runtimes are evaluate-carefully; advisory catalog only, never
  auto-execute

## E29 — `helios azure` command family & persisted config (`infra`) — open

A `helios azure` command family with Azure CLI/PowerShell validation and persisted
HELIOS Azure config, plus the surrounding bootstrap-and-runbook cluster — the early
era's answer to what our connect-azure and cloud-shell bootstrap scripts do today.

- PRs: #88 (helios azure commands + CLI/PS validation + persisted config), #100
  (cloud auth + dev bootstrap hardening), #102 (branch integration report + Azure
  CLI bootstrap), #104 (automation bootstrap + Copilot Studio runbook + action
  template), #106 (branch integration runbook + CLI session bootstrap)
- Extracts: persisted-config shape, validation checks our bootstrap lacks
- Risks: #100 also serves E5 and #102/#106 serve E13 — this epic owns the command
  family; dedupe the rest

## E30 — Early Azure infra & deploy-artifact evolution (`infra`) — open

The first Bicep: an infrastructure/main.bicep with a deploy workflow that builds and
packages an artifact, then modernized CI with tightened scans, release-branch
condition fixes, a required Bicep-build CI gate with local helper, and the
"Enterprise Deployment Manager v5" capstone. Our infra/ stack supersedes most of it;
mine the deploy-artifact packaging ideas.

- PRs: #90 (first main.bicep + deploy workflow build/package artifact), #98
  (modernize CI + tighten scans + Azure infra: Bicep + deploy flow), #99 (fix Azure
  deploy release-branch conditions), #129 (require Bicep build in CI + local helper
  — ours already does), #150 (HELIOS Enterprise Deployment Manager v5)
- Extracts: deploy-artifact packaging steps our helios-deploy.yml lacks
- Risks: our infra/ stack supersedes most of this; packaging ideas only

## E31 — Deep-automation remote redaction hardening (`enhancement`) — open

Hardened redaction of remote data in the deep-automation path. Security-adjacent:
the redaction rules themselves are the durable artifact, regardless of what became
of the automation they guarded (E22).

- PRs: #91 (harden deep automation remote redaction)
- Extracts: the redaction rules — patterns and what counts as sensitive
- Risks: the host automation is gone; port the rules into our logging/telemetry
  paths

## E32 — Minimal-platform scorecard & API tests (`build-ci`) — open

A minimal-platform scorecard plus minimal API tests wired into a CI test step —
lightweight platform-health signals predating the full test lanes; the scorecard
metrics could feed our status dashboard.

- PRs: #95 (optimize minimal platform scorecard), #113 (minimal API tests + CI test
  step)
- Extracts: scorecard metrics, minimal API-test pattern for the helios-ai-api
  surface
- Risks: our AIHub tests already cover the API; absorb metrics, not duplicate tests

## E33 — AIHub fleet models, service & UI (`ai-hub`) — open

Fleet models, a fleet service, a UI redesign with unit tests, then wiring that fleet
into shared AI abstractions — the earliest fleet-in-the-hub design. GUI direction
now lives in `GUI_THEME_ANALYSIS.md` (WinUI 3); mine the model/service shapes, not
the UI.

- PRs: #96 (fleet models + service + UI redesign + unit tests), #97 (connect fleet
  to shared AI abstractions)
- Extracts: fleet model/service shapes (E15 already cites #96/#97 as fleet-model
  wiring context); UI defers to GUI_THEME_ANALYSIS.md
- Risks: the UI is WPF-era; our shell direction is WinUI 3

## E34 — NuGet version centralization & audit (`build-ci`) — absorbed (PR #95)

Centralized HELIOS NuGet versions with shared metadata and a version-audit workflow
— the governance that would have made the era's dependabot bumps (#58/#60) one-line
changes, and directly portable as central package management today.

- PRs: #101 (centralize NuGet versions + shared metadata + version-audit workflow;
  context: the #58/#60 dependabot bumps it would govern)
- Extracts: central version file, shared-metadata pattern, version-audit workflow
- Risks: must cover HELIOS.sln and the Windows-only src/gui solution consistently

## E35 — Windows platform isolation (`build-ci`) — open

Splitting Windows-only code out of the portable core: a conventional
HELIOS.Platform.sln with its own CI target, a HELIOS.Platform.Windows
(net8.0-windows) project, and separated cross-platform core/CLI builds from the
Windows WPF shell — directly relevant to reviving our excluded src/core; the
isolation split is the path to making it compile again.

- PRs: #84 (conventional HELIOS.Platform.sln + CI target), #111 (isolate
  Windows-only code into HELIOS.Platform.Windows), #132 (separate cross-platform
  core/CLI builds from the Windows WPF shell)
- Extracts: the isolation split as the revival plan for src/core/HELIOS.Platform
- Risks: must align with the HELIOS.sln exclusion policy and root-csproj glob
  guards, not fight them

## E36 — Repo optimization audit & idempotent dev setup (`enhancement`) — open

A repository optimization audit plus a hardened, check-only dev setup with Azure CLI
support, and full-stack documentation with non-mutating validators — the
verify-don't-mutate discipline our bootstrap scripts follow today.

- PRs: #112 (optimization audit + check-only hardened dev setup + Azure CLI
  support), #114 (full-stack docs + non-mutating validators + idempotent setup —
  also under E17)
- Extracts: audit checklist, check-only/idempotent patterns our scripts lack
- Risks: overlaps E1's verify-only port and E17's #114; absorb the audit, dedupe
  the rest

## E37 — Multi-language platform scaffolding (`enhancement`) — open

Two takes on scaffolding a multi-language platform — CI, docs, Azure IaC, language
bindings — including quarantining legacy sources out of the build. Our polyglot
layout (C#/F#/C++/Python) landed differently; the quarantine pattern is the piece
to mine.

- PRs: #118 (scaffold: CI + docs + Azure IaC + language bindings), #119 (sibling:
  CI workflows + infra + docs + scaffolding, quarantine legacy sources)
- Extracts: the legacy-source quarantine pattern (relevant to the excluded src/core)
- Risks: greenfield scaffolding our layout already superseded

## E38 — F# analytics library & platform contracts (`ai-hub`) — open

A HELIOS.Analytics.FSharp library with platform contracts and unit tests — the
earliest F# analytics slot, ancestor to E13's RepositoryAnalytics and E2's scoring
modules. Evaluate the contracts against our F# domain.

- PRs: #120 (HELIOS.Analytics.FSharp library + platform contracts + unit tests)
- Extracts: contract shapes for the F# domain (cross-link E13's
  RepositoryAnalytics)
- Risks: new projects must join HELIOS.sln and the root csproj glob guards

## E39 — Command-center control plane & capability registries (`ai-hub`) — open

The early era's control-plane push: a command center with CI workflows, Azure
infra, analytics and reporting; mass-integration orchestration with
capability/agent registries and operator tooling; a unified pipeline scaffold
spanning Azure/GitHub/Codex/Hermes/Slack/M365; and a unified communication contract
— the early-era counterpart of E16. Absorb the registry and report shapes once
across both.

- PRs: #121 #122 (command-center twins), #127 (mass integration workflow + shell +
  capability/agent registries + Azure bootstrap), #128 (automation workflows +
  capability/config registries + operator tooling), #146 (unified pipeline
  scaffold: Azure + GitHub + Codex + Hermes + Slack + M365), #147 (collaboration
  control plane), #151 (unify Copilot Codex Azure and HELIOS communication
  contract)
- Extracts: capability/agent registry shapes and report formats — once across E16
  and this epic (E16 lists #121/#122/#127/#128 from its side)
- Risks: very large PRs; absorb shapes, never the parallel implementation

## E40 — helios.sh developer helper family (`build-ci`) — tranche-1

A helios.sh helper family: PR-body generation, pruning (and ignoring) generated
artifacts, a shared repo-local tool resolver surfaced in build/readiness reports,
and a verify command with `--include-readiness`. Overlaps E14's ported
verify-readiness.ps1 — absorb only what that script lacks.

- PRs: #123 (helios.sh PR-body generator — **ported** as
  `scripts/dev/helios.ps1 pr-update` + `.github/PULL_REQUEST_BODY.md` ignore), #124
  (prune-generated script + ignore generated artifacts — **ported** as
  `scripts/dev/helios.ps1 prune-generated` + generated artifact ignores), #130
  (repo-local tool resolver — **ported** under E14; cross-linked here), #131
  (`--include-readiness` + helios.sh verify command — **ported** as
  `scripts/dev/helios.ps1 verify --include-readiness`)
- Extracts: PR-body generator, prune-generated hygiene, verify behaviors
  verify-readiness.ps1 lacks
- Risks: bash-vs-PS7 split — repo convention wraps the C# CLI in PS7; port
  behaviors, not the shell

---

## Coverage

40 epics span **~140 distinct upstream PRs** (the remainder of the 195 are dependency
bumps, duplicates of these themes, or superseded merge-train snapshots). Tranche 1 (E14,
E15, E17 and the E1 bootstrap port) has **landed at this branch head** — every ported
file exists in the tree with its benchmark report as evidence, and branch CI validates
them; a port is only ever marked so under that rule. Every other epic holds `candidate` watchlist entries
ready for `scripts/absorption/absorb-pr.ps1`. Fleet-scale benchmarking: seed absorb
commands onto the `xcore-infra` board via the lock-aware `--enqueue` (see
ABSORPTION_PIPELINE.md).
