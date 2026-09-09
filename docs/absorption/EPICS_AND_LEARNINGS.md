# Absorption epics and what we learned

One row per absorption epic, the themes the issues and pull requests teach, and the
candidates ranked. Companion to `docs/absorption/START_HERE.md` (the beginner's guide)
and `docs/architecture/ABSORPTION_LEDGER.md` (the narrative ledger). Issue and PR state
was read from `Yolkster64/helios-platform` on 2026-09-06; upstream PR numbers refer to
`M0nado/helios-platform` and are prefixed "upstream".

## The epics, one row each

Epic E-n is issue number 13+n. "Landed" cites pull requests in this repository; "wanted"
is the ledger's summary of what the upstream PRs were reaching for.

| Epic | Issue | Title | What it wanted | Status | What landed | Verdict / learning |
| --- | --- | --- | --- | --- | --- | --- |
| E1 | #14 | Unified `setup-all` control-fabric CLI | One entrypoint that brings the whole control fabric to readiness instead of a dozen per-subsystem scripts (ten upstream drafts) | Closed as completed 2026-09-06; ledger `absorbed (PR #94)` | `scripts/setup/setup-all.ps1` (PR #94); `-VerifyOnly` on the connect scripts (upstream #213, PR #13); the `first-run` chain (PR #208); open PR #209 adds a board-setup inventory row (needs rebase, #229) | Wrap the existing scripts, never reimplement; ten competing drafts became one PowerShell orchestrator |
| E2 | #15 | XCore9 evaluation service and runtime matrix | A bounded evaluation service, a governed runtime matrix with smoke evidence, scoring telemetry feeding policy gates | Open | Nothing ported; the watchlist marks upstream #222 `absorbed` with no port reference (treat as unverified); #294 and #253 are candidates | The natural home for "score each candidate"; expect path conflicts under `src/ai` |
| E3 | #16 | Hermes/XCore contracts and specialization | Versioned federation contracts and per-pool specialization | Open | Nothing; our `config/fleet/fleet-topology.json` v2 is live | Reconcile fields into the live topology; never replace it |
| E4 | #17 | Governed capability profiles and plan validation | Fail-closed capability profiles, JSON-Schema validation of plans, a 50-item capability backlog | Open | Nothing; #292, #295, #285 candidates | Validators and the taxonomy are the low-risk extract; #242 confirms three config files have no schema |
| E5 | #18 | Azure activation hardening — MI→KV custody, OIDC | Managed-identity-to-Key-Vault binding, audience hardening, immutable plan/deploy custody | Closed 2026-09-06 when PR #191 merged (empty diff — the files landed through PR #199); ledger `absorbed (PR #199)` | Audience pin, sealed custody artifacts, `scripts/validation/validate_deploy_custody.py`, `deploy-hardening-contract.yml`; #198 also merged empty; #197, #196, #190, #148 open for owner decision | Contract-tested workflow hardening lands well when scoped; unscoped follow-ups churn hundreds of files |
| E6 | #19 | Private Azure edge and segmented network | Governed private edge and segmentation beyond the zero-inbound NSG | Open | Nothing | Upstream targets Container Apps; we deploy Foundry + VMSS — pattern only, later |
| E7 | #20 | Repository integrity and submodule governance | Integrity validator, declaration audit, fail-closed pinned-submodule gate | Open | Nothing | Dormant governance until a real submodule exists |
| E8 | #21 | CI/test stabilization and test-ownership lanes | Unified test ownership, centralized tool versions, stable lanes | Open | Nothing directly (E24's preflight job and E27's lesson overlap) | Lane names differ; absorb the ownership map idea only |
| E9 | #22 | One-button launcher and packaging | Self-contained local bring-up as a single action | Open | Nothing; `first-run.sh`/`.ps1` (PR #208) covers bring-up differently | Packaging targets the upstream layout |
| E10 | #23 | Read-only Helios.Connect CLI | A zero-mutation connect CLI with strict guardrails | Open | Nothing; `absorb-status` and the loopback-guarded API are already read-only | Absorb the guarantees into existing surfaces, not a second CLI |
| E11 | #24 | Reliability evidence harness | Evidence reports plus a development-only failure injector | Open | Nothing; #220 candidate | Report shape matches absorption reports; injector must stay dev-only |
| E12 | #25 | Integration lanes and merge-train tooling | Stable/preview lanes, umbrella trains, consolidation reports | Open | Nothing | The ledger itself is the consolidation; take the report format only |
| E13 | #26 | Branch intelligence and repository analytics | Priority scoring for what to absorb next; an analytics library | Open | Nothing; #141, #140 candidates | Could rank the watchlist; new projects must join `HELIOS.sln` |
| E14 | #27 | Build graph and readiness tooling | Readiness verify, required/optional tool split, tool resolver, compile checker | Open, `tranche-1` landed | `scripts/build/verify-readiness.ps1`, `scripts/build/tool-resolver.ps1`, `compileall` gate in `python-spoke.yml` (PRs #13, #105) | Port ideas; the build graph itself is upstream-specific |
| E15 | #28 | Model registry and routing validation | Registry with schema, deprecated-model replacement, routing validation | Open, `tranche-1` landed | `config/schemas/model-catalog.schema.json`, `scripts/build/validate-model-catalog.py` in `dotnet-build.yml`, catalog refresh, `bulk_processing` lane (PR #13) | The schema is durable; model IDs move fast |
| E16 | #29 | AIHub unified control plane — dashboards and reporting | Dashboards, reports, analysis agents, engine contracts | Open | Nothing; #145 candidate | Mine data shapes for the planned dashboard sections; never the parallel implementation |
| E17 | #30 | Docs and onboarding | Canonical setup guide, owner-first checklist, wiki sync | Open, `tranche-1` landed | `docs/PROJECT_SETUP.md`, `docs/OWNER_START_HERE.md` (PR #13); #117 candidate, likely reject | Docs port cleanly; the Getting started epic #223 continues this lane |
| E18 | #31 | Windows boot security / WinRE recovery | Guarded boot security, rootkit recovery, WinRE bridges | Open, `audit-first` | Nothing, by design | PR #4's safety disposition rejected unsigned SYSTEM WinRE tasks; documentation only |
| E19 | #32 | USB quick-start installer and customization | The founding bootable installer and customization profiles | Open | Nothing | WinPE era; only the profile shape is worth reading |
| E20 | #33 | Orchestration backbone and Hermes autosetup | First orchestration layer, autosetup generator | Open | Nothing | Superseded by the fleet topology and the bootstrap scripts |
| E21 | #34 | Consolidation automation — manifests, plan-runner, merge CLI | Merge-source manifests and a plan-runner | Open | Nothing | Same idea as E12 from the early era; one design across both |
| E22 | #35 | Deep-AI automation orchestrator and integration planner | Planner profiles, inventory model, orchestrators | Open | Nothing | Nothing here may auto-execute; profiles and inventory model only |
| E23 | #36 | Local AIHub X-Tier control modules | Earliest x-tier modules | Open | Nothing | Superseded by E3's contracts |
| E24 | #37 | Workflow modernization and action-pin upgrades | Pipeline stabilization, action pins, preflight, cache | Closed via PR #96 (2026-08-12); ledger `absorbed (PR #96)` | `preflight` job in `ci-validation.yml`, action pins modernized, least-privilege permissions | Small Copilot-executed epic; landed in a day |
| E25 | #38 | .NET inventory and automerge readiness | Inventory plus automerge readiness checks | Open | Nothing | Readiness criteria only; automerge stays off the table |
| E26 | #39 | Phase-docs consolidation and AI-path hardening | Doc consolidation, HTTP-path hardening, cache-locking fix | Open | Nothing | Four competing drafts; the touched code may be gone |
| E27 | #40 | Portable core CI — Linux lanes and guardrails | Portable core build and test on Linux | Open | Nothing | `HELIOS.sln`'s exclusion policy already encodes the lesson |
| E28 | #41 | `ltrain` local training entrypoint | On-box model training entrypoint | Open | Nothing | Advisory engine-catalog entry only; never auto-execute |
| E29 | #42 | `helios azure` command family and persisted config | Azure command family with validation and persisted config | Open | Nothing | `connect-azure` covers the need; port checks, not a second surface |
| E30 | #43 | Early Azure infra and deploy-artifact evolution | First Bicep and deploy packaging | Open | Nothing | `infra/` supersedes it; packaging ideas only |
| E31 | #44 | Deep-automation remote redaction hardening | Redaction rules for remote data | Open | Nothing; #91 candidate | Security-adjacent, small, durable |
| E32 | #45 | Minimal-platform scorecard and API tests | Lightweight platform-health signals | Closed via PR #97 (2026-08-12); ledger `absorbed (PR #97)` | `scripts/build/minimal-platform-scorecard.py` (informational artifact in `dotnet-build.yml`), four API validation tests | Scorecard metrics can feed the dashboard |
| E33 | #46 | AIHub fleet models, service and UI | Earliest fleet-in-the-hub design | Open | Nothing | UI is WPF-era; shell direction is WinUI 3 |
| E34 | #47 | NuGet version centralization and audit | Central package versions, shared metadata, version audit | Closed via PR #95 (2026-08-12); ledger `absorbed` | `Directory.Packages.props`, `Directory.Build.props`, `nuget-version-audit.yml` (report-only) | Directly portable governance; done |
| E35 | #48 | Windows platform isolation | Split Windows-only code from the portable core | Open | Nothing | The revival path for the excluded legacy core (HC-002) |
| E36 | #49 | Repo optimization audit and idempotent dev setup | Audit plus check-only dev setup | Open | Nothing | Overlaps E1's verify-only and E17; absorb the audit |
| E37 | #50 | Multi-language platform scaffolding | Greenfield scaffolding with legacy quarantine | Open | Nothing | Our polyglot layout landed differently; quarantine pattern only |
| E38 | #51 | F# analytics library and platform contracts | An F# analytics library with contracts | Open | Nothing | Evaluate contracts against `HELIOS.AIHub.Domain` |
| E39 | #52 | Command-center control plane and capability registries | Command center, registries, unified pipeline scaffold | Open | Nothing; #128 candidate | Registry shapes once across E16 and E39 |
| E40 | #53 | `helios.sh` developer helper family | PR-body generation, prune-generated, verify with readiness | Open, `tranche-1` landed | `scripts/dev/helios.ps1 pr-update / prune-generated / verify --include-readiness` (PR #105, which closed the duplicate #93) | Port behaviours, not the shell |

Counts: 40 epics; 5 issues closed (#14, #18, #37, #45, #47); 5 epics carry a landed
tranche (E5, E14, E15, E17, E40 — six if E1's closure is counted as its tranche);
1 audit-first carve-out (E18); 30 open with no port yet.

## Themes we learned

**Every blind merge conflicts; every idea ports.** PR #13's own description records that
all seven tranche-1 trial merges conflicted, and yet every one of those upstream PRs
landed as a ported idea: a readiness script, a compile gate, a schema, two documents.
The lesson shaped the whole program. The benchmark report's conflict list is the most
valuable line in it, because it points at exactly the files where this fork diverged
and therefore where "the idea, not the code" applies. A conflict verdict is the normal
result, and the guide says so in three places on purpose.

**Small, bounded, one-epic pull requests land; large ones churn.** The Copilot coding
agent closed E34, E24 and E32 in a single day (PRs #95, #96, #97, 2026-08-12) and E5
three weeks later (PR #199 carried the files; #191 closed the issue), each with a
handful of real files and a contract test.
The counter-examples are just as instructive: issue #229's triage found ten open PRs
with an empty diff against `main` (a plan commit and nothing else) and one E5 follow-up
(#197) touching 686 files, 683 of them Markdown blank-line churn. The forward plan's T8
already says how to run the next batch — one E-numbered issue at a time, the `copilot`
label as the delegation, the fleet and an agent session reviewing.

**The trust boundary is the design, not an afterthought.** The gate executes the merged
tree's own build code. PR #94's security review made the keyless hosted workflow the
default lane, and the script now refuses (exit 3) on any host carrying a credential by
name or on disk. Three documents and the analyst agent repeat the rule in the same
words. The consequence for automation is simple: the planned cadence runs on the hosted
runner, and fleet batches run only on real Hermes workers on credential-free hosts.

**Advisory is a contract, enforced in code.** Absorption verdicts, fork digests, and
fleet-lane records all enter the learning store with a required `source`, and
`ChainReorderEngine.OrganicOnly` drops every sourced record before any routing engine
sees it. `adaptiveRouting` is `false` in `config/aihub.json` on top of that. The
program can therefore feed the hub freely — the owner's "feeds the AI hub" ask on
issue #242 — without any risk that an upstream PR's build result reorders a provider
chain.
The same invariant covers `fleet-plan` and every engine recommendation: they report,
never apply.

**The owner asks for the same five things, in different words each time.** Reading
issues #98, #109, #115, #223, #231, #235 and the eight addenda on #242 together: an easy,
verify-first setup that ends in one checklist; a dashboard where the learning and
absorption state is visible; scores per candidate that are code-specific
(per language); a smart, automated ranking of what to take next; and everything wired
into one hub that learns. The repository has the first item and the plumbing for the
second and fifth; the third and fourth are open watchlist candidates (E2, E4, E13) and
one planned config file. The guide's ranked list is ordered by exactly that gap.

**Hygiene debt hides real progress.** Issues #54–#93 are Linear-loop twins of the
epics; PR #105 "fixes #93" and PR #209 "fixes #54" when they mean E40 and E1, so a
search for "which PR closed E40" lands on a duplicate. The ledger's status lines lagged
the issues (E1 closed on GitHub, `open` in the ledger; E24 and E32 closed by PRs, `open`
as ledger headings; E5 closed by PR #191, still `tranche-1`) until this guide corrected
them, and the watchlist commit that meant to flip upstream #224 to `absorbed` flipped
upstream #222 instead — #224 now reads `absorbed`
with its port reference, while #222 still says `absorbed` with nothing ported for E2.
None of this is hard to fix; fix it in the same PR as the next watchlist change, so the
status view stays trustworthy.

**The fleet is ready to batch, but only a real fleet counts.** Seeding is idempotent,
capped, epic-filterable, and lock-aware — good tooling. But the weekly learning lane
runs a stub cycle that proves wiring only, and a stub fleet consumes seeded absorption
tasks without running a single gate. Issue #242 measured that the upstream Hermes CLI
now ships the kanban verbs the topology assumes (claim, complete, block, swarm, daemon)
and that installers are public; installing it on the fleet host is what turns the
seeding script from a demo into the batch engine the forward plan describes.

**Dependency upstreams are watched, not yet acted on.** The fork observation workflow
has run weekly and produced digests as artifacts, but `docs/observations/` does not
exist — no digest has ever been committed, and no `fork-observation` advisory record
has been posted. The loop's manual step is the untested part. The fix is procedural: on
the next Monday, open the run summary, commit the digest through a PR if it says
anything, and post its per-repo lines to `/v1/learning` from a loopback shell.

**Evidence beats green.** PR #13's rule — a port is marked landed only when its files
exist at the branch head with the report as evidence and CI validates them — is the
reason the ledger can be trusted at all. The same rule is what makes E5's closure
meaningful (a validator and a contract workflow, not a description), and what the
planned cadence must keep: post the verdict with the report, flip the status, and stop.

## Candidates ranked

Value and risk are judged against the owner's asks and the ledger's stated risks;
effort is the expected size of the port, not of the upstream PR. "Next step" names the
smallest action that moves the row.

| Candidate | Source | Value | Risk | Effort | Recommended next step |
| --- | --- | --- | --- | --- | --- |
| Schema validation harness for config files | Upstream #292 (E4) | High — `config/aihub.json`, `fleet-topology.json`, `connectors.json` have no schema (#242); precedent in E15 | Low — validators only | Small | Hosted benchmark; extract the harness shape; write one schema per config file with a `quality.yml` job |
| Capability-profile validator and backlog taxonomy | Upstream #295, #285 (E4) | High — roadmap seed plus fail-closed validators | Low if the runtime and security model are left behind | Small–medium | Benchmark #295 first; take the validator and the taxonomy document only |
| Reliability evidence harness | Upstream #220 (E11) | High — report shape matches absorption reports; deliberate fallback/circuit-breaker exercise | Low with dev-only, fail-closed gating | Medium | Hosted benchmark; port the report shape into `.helios/` conventions; gate the injector behind an explicit env name |
| Runtime matrix with smoke evidence | Upstream #294 (E2) | High — the "score each candidate" ask; maps onto local/Windows/Docker runtimes | Medium — pre-consolidation layout | Medium | Hosted benchmark; expect conflicts; port the matrix definition as a config file |
| KNAA scoring telemetry and rubric | Upstream #253 (E2) | High — feeds the empty `quality` field; the per-language rubric's ancestor | Medium — policy gates assume upstream CI | Medium | Benchmark after #294; take the rubric; draft `config/absorption/scoring.json` (planned) |
| Board-setup inventory row (E1 follow-through) | This repo's open PR #209 | Medium — completes the `setup-all` inventory | Low — read-only, keyless | Small | Rebase on `main` per #229 and retarget "Fixes #54" to #14's closure note |
| Remote-redaction rules | Upstream #91 (E31) | Medium — durable security rules for logging and telemetry | Low | Small | Hosted benchmark; port the rules as a documented pattern list |
| Read-only enforcement guarantees | Upstream #221 (E10) | Medium — guarantees for hosted inspection | Low | Small | Benchmark; absorb guarantees into `helios-ai status`/`absorb-status` and the MCP tools |
| Dashboard data shapes | Upstream #145 (E16), #128 (E39) | Medium — informs the planned `absorption`/`learning` sections | Medium — very large PRs | Small if shapes only | Read the PR files list, not a trial merge; extract JSON shapes into #132's design |
| Branch-intelligence priority scoring | Upstream #141, #140 (E13) | Medium — the "smart ranking" ask | Medium — analytics layout; `HELIOS.sln` and glob guards | Medium | Benchmark #141; port the scoring model as a Python spoke function over the watchlist |
| Test-ownership map | Upstream #219 (E8) | Medium — tames the workflow zoo | Low | Small | Extract the map as a document; do not rename lanes |
| Subnet-review workflow pattern | Upstream #218 (E6) | Low–medium — discipline for VMSS networking | Medium — Container Apps target | Small | Read only; note the pattern in `infra/README.md` when VMSS goes live |
| Wiki sync behaviours | Upstream #117 (E17) | Low — ours is newer | Low | Small | Benchmark as the first teaching run; record `rejected` with the reason |
| Submodule approval gate and integrity validator | Upstream #215, #214 (E7) | Low until a submodule exists | Low | Medium | Leave as `candidate`; revisit if `.gitmodules` returns |
| Boot security / WinRE threat model | Upstream #166 (E18) | Documentation only | Carve-out — no code | Small | Write the threat-model section; nothing else |

Not ranked: E19, E20, E22, E23, E26, E30, E33, E36, E37 candidates — era-specific or
superseded by the current tree; benchmark only if a specific extract is named first.
