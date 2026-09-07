# Model and tool pairing — which model, which surface, and when to use them together

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Grounding: `config/aihub.json` (chains), `config/fleet/fleet-topology.json`
(pool chains), `docs/architecture/LLM_STRENGTHS_PLAYBOOK.md` (why), `REVIEW_LOOP.md`
(the three-reviewer loop), `.claude/agents/codex-liaison.md`, and the `openai-codex`
and `github-copilot` skills. Every capability claim traces to one of those or to a
recorded outcome; nothing here is a benchmark the repo did not run.

## 1. Each surface, and what it is for

| Surface | Kind | Best for | Never for | Ground truth |
|---|---|---|---|---|
| **Codex CLI** (`codex exec {prompt}`, 600 s) | Agentic CLI provider `codex` | Repo-scale mechanical edits: "make the tests pass", adapters, refactors, test scaffolds — leads `code_generation`, `code_refactoring`, `test_creation` | Paste-in reviews (a payload, and reviews are Claude-led) | `config/aihub.json:61-66,98-137`; playbook "Codex CLI vs OpenAI API" |
| **Claude Code / `claude-cli`** (`claude -p`) | Agentic CLI provider; also the stewarding session | Planning, architecture archaeology, "why does this fail" (leads `debugging`), reviewing and fixing `copilot/*` branches, long-context reads | Bulk, cheap, similar completions — highest token spend in the hub | `config/aihub.json:55-60,173-178`; playbook "Claude CLI"; `FORWARD_PLAN.md` "Operating model" |
| **Copilot** | Three surfaces, one routed | Inline completion (`copilot` CLI, `inline_completion`); automatic PR review on every non-draft PR; coding agent on issues labelled `copilot` | Review, architecture, or long-context work through the hub | playbook "GitHub Copilot"; `.claude/skills/github-copilot/SKILL.md` |
| **`gh` CLI** | Control plane, not a model | PRs, issues, workflow dispatch, `gh models run` for cheap batch turns; sourcing `connect-github.sh` or dot-sourcing `connect-devices.ps1` exports `GITHUB_MODELS_TOKEN`. The one-sitting login — both device codes (gh, az) on one screen, then the chain — is `pwsh scripts/bootstrap/connect-devices.ps1`; `bash scripts/bootstrap/first-run.sh --connect` runs the same logins as step 0 | Anything a model should reason about | playbook "API vs CLI agents"; `CLOUD_SHELL_AND_LOCAL_FLEET.md` "Bootstrap (device-code auth)"; `scripts/bootstrap/connect-devices.ps1:4-5,33-52`; `scripts/bootstrap/first-run.sh:53,132-155` |
| **GitHub App** `helios-control-<owner>` | Control plane — wired (PR #241) | Repo-admin writes from a workflow (the governance items: rulesets, settings, labels, milestones) and pushes that must fire `on: push`. Registered once from the owner's machine by `scripts/bootstrap/connect-github-app.ps1` (manifest flow, two clicks; variables `HELIOS_APP_CLIENT_ID` / `HELIOS_APP_ID` / `HELIOS_APP_SLUG`, secret `HELIOS_APP_PRIVATE_KEY`; `-DispatchGovernance` for the first apply); `governance-run.yml` mints a per-run installation token with `actions/create-github-app-token@v3`, falling back to the `HELIOS_ADMIN_TOKEN` PAT, then `github.token` | Projects v2 (still the owner's classic PAT with the `project` scope); approving production; ARC runner auth (still docs-level) | `scripts/bootstrap/connect-github-app.ps1:17-29,71-77`; `.github/workflows/governance-run.yml:82-88,126`; `.claude/skills/github-control/references/auth-topology.md:71-95,124-136` |
| **`openai` API** (`gpt-5-mini`) | API provider | One structured completion you fully control; docs; `general_query`; fallback nearly everywhere | Workspace tasks | `config/aihub.json:4-9`; playbook "Codex CLI vs OpenAI API" |
| **`openai-codex` API** (`gpt-5.1-codex-max`) | API provider | The codegen specialist where the `codex` CLI is absent (CI, containers); not live-smoked keyless | Assuming it is the CLI | `config/aihub.json:10-16` |
| **`anthropic` API** (`claude-sonnet-5`) | API provider | Diff review, security, architecture, long context, documentation — leads six chains | Bulk | `config/aihub.json:17-22,138-188` |
| **`anthropic-foundry`** (deployment `claude-sonnet-4-6`) | API provider in Microsoft Foundry | The same family when the work must stay inside the Foundry boundary; Entra fallback | Being assumed identical in model version to `anthropic` | `config/aihub.json:23-30` |
| **`azure-openai`** (`gpt-5-mini` deployment) | API provider | Tenant-resident cheap tier; leads `defaultChain` and `general_query` | Frontier-quality reasoning | `config/aihub.json:31-36,89-96` |
| **`azure-foundry`** (agent service) | API provider | `enterprise_data`: the boundary is the value, agent tools over Azure data | Generic codegen (pays the enterprise path's latency for nothing) | `config/aihub.json:48-52,189-193`; playbook "Azure Foundry" |
| **`github-models`** (`openai/gpt-5-mini`) | API provider | `bulk_processing`; free-with-cap | Long context (128K) or tools | `config/aihub.json:37-42,204-208` |
| **`ollama`** (`llama3.2`) | Local API provider | `offline`; the network-is-the-problem control | Quality-sensitive work | `config/aihub.json:43-47,201-203` |
| **Fleet** — Hermes lanes, four Xcore-9 pools | Executors behind `agent_fleet_dispatch → hermes` | A backlog of 20 similar *agentic* tasks; absorption benchmarks; parallel reviews on the read-only `xcore-review` board | Deciding anything — chains and topology are config; `fleet-plan` only reports | `config/fleet/fleet-topology.json:28-114`; `HERMES_FLEET_AND_XCORE.md` |

Two rules from the surfaces above govern every pairing: **API for payloads, CLI for
workspaces** (playbook "API vs CLI agents"), and **hub output is a draft, never a
deliverable** — reconcile against the target stack's skill before it lands
(`codex-liaison.md` Rule 2).

## 2. Pairing matrix — phase × language

Columns: **Primary** produces; **Second opinion** is consulted through `compare` or a
second `route` only when the decision warrants it; **Verifier** judges before merge;
**Executor** carries it out at scale. Chains are `config/aihub.json:97-215`; pool
chains are `config/fleet/fleet-topology.json`. "Claude session" means the stewarding
Claude Code session of `FORWARD_PLAN.md`'s operating model; "Codex + Copilot waves"
means the PR loop of `REVIEW_LOOP.md`.

| Phase | C# / hub | F# domain | C++ native | Python spoke | PowerShell | Infra (Bicep / YAML / JSON) | XAML (WinUI 3) | Docs |
|---|---|---|---|---|---|---|---|---|
| Planning | Primary: Claude session. Second: `compare` anthropic vs openai | same | same | same | same | Primary: Claude session; second opinion via `architecture_design` chain | Primary: Claude session (`GUI_UPGRADE_PLAN.md` phases) | Claude session |
| Architecture | `architecture_design` → anthropic; second: openai (in-chain) | same | same; native pool chain anthropic → openai → codex for lane work | same | n/a (PS wraps C#) | `architecture_design`; infra pool chain anthropic → openai → azure-openai | `architecture_design`; verifier `winui3-reviewer` | `documentation_generation` → anthropic |
| Code generation | Primary: `codex` CLI; second: `openai-codex`; verifier: Claude session against `csharp-orchestrator`; executor: code pool (codex-led) | `code_generation:fsharp` → anthropic, anthropic-foundry, codex, openai-codex, openai (`config/aihub.json:112-118`); verifier: `fsharp-reviewer` against `fsharp-functional` | `code_generation:cpp` → codex, openai-codex, anthropic, anthropic-foundry, openai (`config/aihub.json:105-111`); verifier: `cpp-perf-reviewer`; executor: native pool, local only | `code_generation:python` → codex, openai-codex, openai, github-models, azure-openai (`config/aihub.json:119-125`); verifier: `python-reviewer` | Primary: `codex` (no `code_generation:powershell` chain, so the bare chain applies); verifier: `powershell-reviewer`; rule: wrap the C# CLI | Primary: infra pool / `workflow-author`, `bicep-arm-author` agents; verifier: `bicep build`, `infra-validate.yml` | Primary: `codex` for markup; verifier: `winui3-reviewer` + `ux-reviewer` | Primary: `documentation_generation`; verifier: markdownlint + link check |
| Refactoring | `code_refactoring` → codex, openai-codex, anthropic, openai | same | same | same | same | `config_authoring` lane in the infra pool | `code_refactoring`; verifier `winui3-reviewer` | n/a |
| Debugging | `debugging` → `claude-cli`, codex, openai-codex, openai | same | same (sanitizer output in the prompt) | same | same | same | same | n/a |
| Test creation | `test_creation` → codex, openai-codex, openai, anthropic; verifier: `testing.md` idioms | same; FsCheck candidates in `analytics-patterns.md` | C# tests over the ABI (no ctest) | pytest, dependency-free | Pester 5.4.0 | `ConfigBindingTests`, workflow YAML parse | none today | n/a |
| Code review | `code_review` → anthropic, anthropic-foundry, claude-cli, openai; then Codex + Copilot waves | same + `fsharp-reviewer` | same + `cpp-perf-reviewer` | same + `python-reviewer` | `code_review:powershell` → anthropic, anthropic-foundry, openai, github-models (`config/aihub.json:151-156`) + `powershell-reviewer` + parser baseline in CI | `code_review:bicep` → anthropic, anthropic-foundry, azure-openai, azure-foundry, openai (`config/aihub.json:144-150`) + `infra-validate.yml` | same + `winui3-reviewer`, `ux-reviewer` | Claude session |
| Security analysis | `security_analysis` → anthropic, anthropic-foundry, openai; executor for audits: review pool (claude-led, read-only tools) | same | same + ASan/UBSan build | same | same | same + `deploy-hardening-contract.yml` | same | n/a |
| Infra / Bicep / YAML | n/a | n/a | n/a | n/a | wrapper scripts only | Primary: infra pool; verifier: `bicep build`, `what-if` by a human | n/a | n/a |
| Docs | `documentation_generation` → anthropic, anthropic-foundry, openai, github-models | same | same | same | same | same | same | same; verifier: the Claude session for accuracy against cited files |

Where a cell says "same", no language-qualified chain is shipped for that column and the
bare task-type chain applies. The language dimension landed in PR #248
(`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`): `helios-ai route <task-type>
"<prompt>" --language <lang>` tries `taskRouting["<task-type>:<lang>"]` before the bare key
(`TaskTypeRoutingStrategy.GetChain(taskType, language)`,
`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs:168-196`); the shipped qualified
chains are `code_generation:cpp|fsharp|python` and `code_review:bicep|powershell`
(`config/aihub.json:105-125,144-156`); every outcome records the normalized language
(`RoutingOutcome.Language`, `src/ai/HELIOS.AIHub/Learning/LearningStore.cs:27-37`); and
adaptive learning — still off by default — scopes its evidence per `(taskType, language)`
(`ChainReorderEngine.ForLanguage`, `src/ai/HELIOS.AIHub/Learning/ChainReorderEngine.cs:49-62`),
which is what lets the learned order differ per column. The per-language verifiers
`fsharp-reviewer`, `python-reviewer` and `powershell-reviewer` are under `.claude/agents/`
and rostered in `config/fleet/fleet-topology.json` (same PR).

## 3. Automation recipes (repo commands only)

Cost is stated relative to a single `route` call. Wall time for fan-outs is roughly the
slowest provider, not the sum.

### Recipe 1 — plan, draft, reconcile, review

```bash
helios-ai route architecture_design "Design the seam for <X>; list invariants and tests"   # 1 call (anthropic)
helios-ai route code_generation "Implement <X> per this design: …"                        # 1 call (codex CLI, agentic)
dotnet build HELIOS.sln -c Release && dotnet test tests/HELIOS.AIHub.Tests -c Release       # reconcile against the stack skill first
gh pr create --draft …   # then mark ready: Copilot review is automatic; Codex reviews the head
```

Cost: 2 model calls plus the review waves (each push = a new Codex wave; converge on
👍 — `REVIEW_LOOP.md` "The wave protocol"). Not worth it for a one-line change: go
straight to the PR loop.

The language-qualified form — `helios-ai route code_generation "<prompt>" --language fsharp`
— landed in PR #248 (`src/ai/HELIOS.AIHub.Cli/Program.cs:79-107`: `--language` is optional,
must carry a value, and is passed as `HubRouteRequest.Language`); it selects
`code_generation:fsharp` (`config/aihub.json:112-118`) and costs the same single call.
`helios-ai routing` marks each qualified chain with `+` (`Program.cs:175-194`).

### Recipe 2 — race two kinds of codegen (tandem)

```bash
helios-ai tandem code_generation "<prompt>"     # codex (CLI) and openai-codex/openai/... (API) concurrently
```

Cost: N calls for an N-provider chain (five for `code_generation`), every outcome
recorded. Worth it when the CLI and API lanes genuinely differ in latency or failure
mode and you want the learned winner marker after a handful of runs. Not worth it once
`/v1/learning?taskType=code_generation` already shows ≥ 5 attempts per candidate — use
`route` and let the reorder engine do the work.

### Recipe 3 — decide, don't average (compare)

```bash
helios-ai compare "Should the fallback chain be per-model or per-provider? Argue both." --providers anthropic,openai
```

Cost: one call per named provider; nothing recorded. Worth it for a decision where
disagreement is the signal. Not worth it for anything with a deterministic answer or for
bulk.

### Recipe 4 — cold-start cost pick (catalog)

```bash
helios-ai ask "<prompt>" --optimize cost --for documentation_generation   # e.g. openai/gpt-5-mini
```

Cost: 1 call. Worth it before history exists. Not worth it once `route` has evidence —
catalog picks are priors, learned order is measurement.

### Recipe 5 — bulk, cheap, non-agentic

```bash
helios-ai route bulk_processing "Classify: …"    # github-models → azure-openai → ollama
```

Cost: 1 call at the free/cheap tier. Not worth routing anywhere else; never send bulk to
`claude-cli`.

### Recipe 6 — repetitive agentic work on the fleet

```bash
pwsh scripts/fleet/start-fleet.ps1 -DryRun                         # launch plan
pwsh scripts/fleet/start-fleet.ps1 -Fleet xcore-9-infra -PoolSize 3
pwsh scripts/fleet/seed-absorption-tasks.ps1 -Epic E2 -Max 2       # only when the manifest says workerKind: hermes
pwsh scripts/fleet/fleet-status.ps1 -Json
helios-ai fleet-plan                                                # advisory: configured vs learned chain per pool
```

Cost: one agentic session per task, in parallel, bounded by `maxConcurrentLanes` and
`autoscaling.maxLocalLanes` (`fleet-topology.json`). Worth it for a backlog of similar
tasks. Not worth it on the stub fleet (it marks tasks done without executing), for a
single task, or on a credential-bearing host for absorption benchmarks — use
`gh workflow run absorption-benchmark.yml -f pr_number=<N>` instead
(`.claude/agents/absorption-analyst.md`).

### Recipe 7 — the review loop as the verifier of every recipe

Copilot reviews automatically on ready-for-review; Codex reviews every push and reacts
👍 when converged; `@codex address that feedback` pushes fixes that are drafts under Rule
2 of `codex-liaison.md`; merge only when `mergeable_state` is clean, every finding is
fixed or refuted with evidence, and required checks are green (`REVIEW_LOOP.md`
"Stopping rule"). Cost: zero hub calls; the Codex plan's quota. Not worth skipping —
ever — for agent-authored code.

## 4. What is not worth it, in one table

| Temptation | Why not | Do instead |
|---|---|---|
| `tandem` on every request | N× tokens forever; the reorder engine already learns from `route` once evidence exists | `tandem` a handful of times, then `route` |
| `compare` for bulk | Nothing is recorded, nothing is learned, N× tokens | `bulk_processing` |
| `claude-cli` for classification sweeps | Highest-spend surface | `github-models` or `gh models run` |
| A frontier model for `general_query` | The chain leads with `azure-openai`/`openai` for a reason | `route general_query` |
| Routing reviews to `codex` | Reviews are Claude-led; the Codex reviewer is the PR-side surface, not the hub lane | `code_review` chain, then the PR waves |
| Fleet for one task | Bring-up and board overhead dwarf the work | `route` |
| Trusting a hub draft verbatim | Convention drift gets in that way | Reconcile against the stack skill; run the gates |
