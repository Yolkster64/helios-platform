# LLM Strengths Playbook — Which Model, When

The decision guide behind `config/aihub.json`'s task-routing table. The table is the
machine-readable form; this document is the reasoning, so future edits stay principled.
`helios-ai routing` prints the live table; MCP clients read it via `helios_task_routing_get`.

## Decision matrix by outcome

| You want… | Use | Why |
|---|---|---|
| A subtle bug found, a diff reviewed honestly | **Claude** (`code_review`) | Strongest long-horizon reasoning over code semantics; best at saying "this is wrong because…" with a failure scenario |
| A whole subsystem or huge log understood | **Claude** (`long_context_analysis`) | Long-context recall + synthesis; feed it the full slice, not excerpts |
| An architecture decision argued through | **Claude → GPT** (`architecture_design`) | Claude for the deep tradeoff analysis; GPT as a second opinion in `compare` |
| A well-specified function/adapter generated | **Codex/GPT** (`code_generation`) | Fast, strong pattern-following codegen; cheapest correct token for boilerplate |
| Mechanical refactors, test scaffolds | **Codex** (`code_refactoring`, `test_creation`) | Excels when the transformation is describable |
| Keystrokes saved while typing | **Copilot** (`inline_completion`) | In-editor latency beats every API path |
| Answers grounded in enterprise/Azure data | **Azure Foundry agent** (`enterprise_data`) | Runs inside the tenant boundary; Entra ID auth; agent tools reach Azure data sources (PR3 adds AI Search) |
| Work done with zero cloud dependency | **Ollama** (`offline`) | Local; also the "is the network the problem?" control |
| Many cheap, similar completions in bulk | **GitHub Models** (`bulk_processing`) | Free-tier hosted small models — $0 with a request cap; falls back to `azure-openai` then `ollama` when rate-limited |
| Many similar *agentic* tasks executed in bulk | **Hermes fleet** (`agent_fleet_dispatch`) | Nine Xcore lanes beat one giant prompt (HERMES_FLEET_AND_XCORE.md) |
| Confidence via disagreement | `helios-ai compare` | Parallel fan-out; treat divergent answers as a signal to think, not to average |

## Decision matrix by moment

| Moment | Route |
|---|---|
| Designing, before code exists | `architecture_design` |
| Writing new code from the design | `code_generation` |
| While typing | `inline_completion` |
| Before opening the PR | `code_review`, `security_analysis` |
| Debugging a failure | `debugging` (agentic CLI first — it can run commands) |
| Working with tenant data / compliance constraints | `enterprise_data` |
| On a plane / air-gapped | `offline` |
| A backlog of 20 similar items | `agent_fleet_dispatch` |

## API vs CLI agents

API providers return one completion; **CLI agents (claude, codex, copilot) are agentic**
— they read files, run commands, and iterate. Prefer the CLI form when the task needs
context gathering ("debug why this test fails"), the API form when you control the full
prompt ("review this diff I'm pasting"). Both forms are providers in the same hub, so
routing chains can mix them (`debugging: claude-cli → codex → openai`).

Tool CLIs round out the shell: `az` (Azure control plane), `gh` (GitHub control plane +
`gh models run`), `bicep` (infra validation). They are not LLM providers but are part of
every agent's toolbox; install profiles live in GITHUB_ECOSYSTEM_DESIGN.md (winget DSC
"cross-LLM shell workload"). Bringing that toolbox up on a fresh box is the
`cloudshell-bootstrapper` agent's job (`.claude/agents/cloudshell-bootstrapper.md`).

## Per-surface optimal use

The generalization above ("API for payloads, CLI for workspaces") plays out differently
per vendor. Task types in parentheses are the `config/aihub.json` chains that encode
each claim.

### Codex CLI vs OpenAI API — same vendor, two tools

- **`codex` CLI agent** (`codex exec {prompt}`, 600s timeout): repo-scale *agentic*
  edits — it reads files, runs tests, iterates. It leads `code_generation`,
  `code_refactoring`, and `test_creation`, and is second in `debugging` behind
  claude-cli. Headless auth is just `OPENAI_API_KEY` in the environment, so it works in
  CI and fleet lanes with no browser.
- **`openai` API provider** (default `gpt-5-mini`): one structured completion where you
  control the entire prompt — doc generation, extraction, `general_query`. It appears as
  a fallback in nearly every chain but *leads* nothing agentic.
- Don't use `codex` for a paste-in review ("review this diff") — that's a payload, and
  the review lanes are Claude-led anyway (`code_review: anthropic → claude-cli → openai`).
  Don't use the API for "make the tests pass" — that's a workspace.

### GitHub Copilot — three distinct surfaces, only one routed

1. **Inline completion** — the `copilot` CLI agent, primary for `inline_completion`
   (fallback `github-models`). In-editor latency is the entire value; nothing else in
   the hub competes on it.
2. **PR review** — `.github/workflows/copilot-dispatch.yml` auto-requests a Copilot
   review on every non-draft PR. Never ask for it manually and never treat its absence
   as an error: the workflow skips green with a notice when Copilot isn't available.
3. **Coding agent** — adding the `copilot` label to an issue *is* the delegation
   decision: the same workflow assigns `copilot-swe-agent`, which starts a session and
   opens a draft PR. Remove the label / unassign to take the work back.

Copilot appears in exactly one routing lane. Do not route review, architecture, or
long-context work to it — the label and the auto-review are the only other sanctioned
paths.

### Claude CLI (`claude -p`)

Leads `debugging`; backs the `anthropic` API in `code_review` and
`long_context_analysis`. Use it when the task needs *gathering* — multi-file reasoning,
architecture archaeology, "why does this fail" — because it runs commands and follows
the trail. It is the highest-token-spend surface in the hub (see the cost ladder), so
never point it at bulk work that `bulk_processing` handles for near-zero cost.

### gh models (`gh models run`)

The `gh-models` CLI agent (default `openai/gpt-5-mini`, 300s timeout — half the others,
deliberately) is the `bulk_processing` primary, falling back `azure-openai → ollama`
when rate-limited. Use it for many cheap, similar, non-agentic completions:
classification sweeps, batch summaries, triage. Its limits are structural: 128K context,
free-tier request cap, no tools. Auth is free too — sourcing
`scripts/bootstrap/connect-github.sh` exports `GITHUB_MODELS_TOKEN` from the gh token.

### Azure Foundry (agent service)

`enterprise_data` routes `azure-foundry → azure-openai` and nothing else does: the value
is the *boundary*, not the model (same `gpt-5-mini` as azure-openai). Entra ID auth,
tenant-resident execution, and Foundry agent tools reaching Azure data sources. Route
anything touching tenant data or compliance constraints here; route nothing generic
here — paying the enterprise path's latency for codegen buys nothing.

### Ollama (offline/airgapped)

`offline` routes to `ollama` alone; it is also the terminal fallback in `defaultChain`,
`bulk_processing`, and `general_query`. Two jobs: zero-cloud-dependency work
(airgapped, on a plane), and the "is the network the problem?" control when every
hosted provider misbehaves. Local `llama3.2`; quality-sensitive work should not end
here on purpose.

### Hermes fleet (bulk *agentic* work)

`agent_fleet_dispatch → hermes`: a backlog of similar agentic tasks goes to the Xcore
pools, not into one giant prompt. Operating the fleet (start/scale/seed/stop) is the
`fleet-operator` agent's job (`.claude/agents/fleet-operator.md`); the absorption
benchmark workload that most often fills it belongs to `absorption-analyst`
(`.claude/agents/absorption-analyst.md`).

## Optimizing across every model automatically

`config/model-catalog.json` is the published-characteristics counterpart to the learned
history in `config/aihub.json`'s `routing`/`learning` blocks: per model, its class
(frontier/balanced/specialist/fast/local), context window, per-million-token cost, and
relative speed. `helios-ai ask "<prompt>" --optimize cost|latency|quality|balanced --for
<task-type>` (and the MCP tool `helios_optimal_provider_get`) picks the single best-fit
provider for a stated preference — instead of the fixed chain, when you know what you're
optimizing for right now. `cost` picks cheapest-first among models whose strengths cover
the task; `latency` picks fastest-first; `quality` picks frontier-class first; `balanced`
splits the difference across all three so no one axis dominates.

This composes with the learning loop rather than replacing it: the catalog picks a
*candidate* from published specs, `helios-ai route` (or `helios_ai_route`) still applies
the F# `RoutingPolicy` reordering from *observed* outcomes in this codebase before
falling back to the static chain. Use `--optimize` for "what's objectively cheapest for
this kind of task", and `route` for "what has actually worked here."

## Current model families (mirrors config/model-catalog.json)

The catalog is the machine-readable registry; CI validates its structure via
`scripts/build/validate-model-catalog.py` against `config/schemas/model-catalog.schema.json`.
Current entries:

| Provider | Models | Role |
|---|---|---|
| **Anthropic (Claude 5 family)** | `claude-opus-5` (frontier, 1M ctx, $5/$25), `claude-sonnet-5` (balanced, 1M ctx, $3/$15 — the `anthropic` provider default), `claude-haiku-4-5-20251001` (fast, 200K ctx, $1/$5) | Review, long-context, architecture, security at Opus/Sonnet tier; Haiku for cheap fast turns |
| **OpenAI (gpt-5.x family)** | `gpt-5.4` (frontier), `gpt-5.1-codex-max` (codegen specialist), `gpt-5-mini` (fast — the `openai` provider default) | Codegen, refactors, tests; mini for general/doc queries |
| **Azure OpenAI / Azure Foundry** | `gpt-5-mini` on both | Enterprise/tenant-boundary work; Foundry adds agent tools over Azure data |
| **GitHub Models** | `openai/gpt-5-mini` (free tier, rate-limited) | `inline_completion` fallback and `bulk_processing` primary |
| **Ollama** | `llama3.2` (local) | `offline` |

When a family ships a new generation, update the catalog (prices/context/strengths),
this table, and the affected `config/aihub.json` chains in the same PR.

## Model knowledge — choosing by tier, not by name

`config/model-catalog.json` is the source of truth for exact numbers; this section is
the *choosing* discipline. It deliberately uses relative tiers — absolute prices rot,
tier relationships don't. When a tier claim here disagrees with the catalog, the catalog
wins and this section needs a PR.

| Family | Model | Class | Context tier | Cost tier | Latency class | Routing lanes (catalog strengths) |
|---|---|---|---|---|---|---|
| Anthropic | `claude-opus-5` | frontier | XL (1M) | premium | slow | `long_context_analysis`, `architecture_design`, `security_analysis` |
| Anthropic | `claude-sonnet-5` | balanced | XL (1M) | mid | medium | `code_review`, `debugging`, `code_analysis` |
| Anthropic | `claude-haiku-4-5-20251001` | fast | M (200K) | cheap | fast | `inline_completion`, `general_query` |
| OpenAI | `gpt-5.4` | frontier | L (400K) | premium | medium | `architecture_design`, `code_generation` |
| OpenAI | `gpt-5.1-codex-max` | specialist | L (400K) | mid | medium | `code_generation`, `code_refactoring`, `test_creation` |
| OpenAI | `gpt-5-mini` | fast | L (400K) | cheap | fast | `general_query`, `documentation_generation` |
| Azure OpenAI | `gpt-5-mini` | fast | L (400K) | cheap | fast | `enterprise_data`, `general_query`, `bulk_processing` |
| Azure Foundry | `gpt-5-mini` | fast | L (400K) | cheap | fast | `enterprise_data` (tenant boundary is the point) |
| GitHub Models | `openai/gpt-5-mini` | fast | S (128K) | free-with-cap | fast | `inline_completion`, `bulk_processing` |
| Ollama | `llama3.2` | local | S (128K) | free, hardware-bound | hardware-bound | `offline` |

How to choose with it:

- **Context tier first, and never excerpt to save a tier.** If the task *is*
  long-context (whole subsystem, huge log), the XL tier is the requirement — feeding
  excerpts to a cheaper S/M-tier model converts a recall problem into a guessing
  problem. If the input genuinely fits S, the cheap tiers are pure savings.
- **Cost tier second: premium must buy something nameable.** Frontier class is for
  tasks where the *quality delta changes the outcome* (architecture, security). If a
  chain's leading mid/cheap model usually succeeds at the lane, premium is waste — that
  is exactly what the ordered chains already encode.
- **Latency class is per-moment, not per-model-goodness.** Interactive moments
  (inline, quick questions) want the fast class; batch/fleet moments tolerate slow.
  `hardware-bound` means *your* box decides — benchmark before promising throughput.
- **Lane mapping closes the loop.** The catalog `strengths` are the same task-type
  vocabulary as the routing table, so `--optimize cost|latency|quality` (previous
  section) can only pick models whose strengths cover the task.

Update discipline: the catalog is refreshed when providers change prices/context/models,
and CI validates its structure on every PR via `scripts/build/validate-model-catalog.py`
against `config/schemas/model-catalog.schema.json`. A catalog edit that changes any tier
relationship must update this section's table and any affected `config/aihub.json`
chain in the same PR (see "Maintaining the table").

## Cost & latency ladder

Cheapest/fastest first, for when the task tolerates it: Copilot inline → small models via
GitHub Models / `gpt-5-mini` → Ollama local (free, hardware-bound) → frontier models
(Claude Opus/Sonnet 5, GPT-5-class) → agentic CLI sessions (highest token spend, highest capability).
The routing table encodes this: chains lead with the cheapest provider that usually
succeeds and fall back upward. Budget guardrails: model `capacity` in Bicep bounds
Azure spend structurally; per-provider circuit breakers stop retry storms.

## Scaling — every knob in one place

Every throughput/capacity knob in the platform, with its home and its safety bound.
HERMES_FLEET_AND_XCORE.md ("Parallelism model") explains *why* the layers are
independent; this is the operator's index of *where*. Fleet knobs are operated through
the `fleet-operator` agent; absorption seeding through `absorption-analyst`.

| Knob | What it scales | Default | Where to change | Safety bound |
|---|---|---|---|---|
| `poolSize` (per pool) | Worker identities per Xcore pool | 9 per pool (36 total) | `config/fleet/fleet-topology.json` | Workspace mode (Cloud Shell/Codespaces) caps to `workspaceProfile.poolSize`, else half the declared size rounded up; an explicit `-PoolSize` is still capped |
| `hermesFleet.maxConcurrentLanes` | Declared per-board lane cap in the fleet contract — consumed by real Hermes workers, **not enforced** by the local stub, start-fleet, or scale-fleet today | code 6 / infra 4 / review 9 / native 3 | `config/fleet/fleet-topology.json` | The enforced ceilings are `poolSize` (workers spawned) and `autoscaling.maxLocalLanes` (reconciler bound); treat this field as the quota the pool SHOULD honor once real Hermes workers read it |
| `autoscaling.minLocalLanes` / `maxLocalLanes` / `maxBurstLanes` | Warm floor / local ceiling / cloud ceiling per pool | defaults 1 / 4 / 5, per-pool overrides | `config/fleet/fleet-topology.json` (pool block merged over `defaults.autoscaling`) | Scale-up only when queue depth > `scaleUpQueueDepth` (3); scale-down only after `scaleDownIdleSeconds` (300) empty — a shrinking queue never scales down; `xcore-9-native` is `local`-mode on purpose (no burst) |
| Reconciler cadence | How fast autoscaling policy is enforced | one pass per invocation; `-Watch` loops at 60s (`-IntervalSeconds`) | `scripts/fleet/scale-fleet.ps1` (cron or `-Watch`) | `-DryRun` prints the decision table touching nothing; kills are identity-verified (pid + recorded start time) |
| VMSS burst gate | Whether cloud burst capacity exists at all | OFF | `infra/main.bicep`: `deployFleetVmss` (false) AND non-empty `vmssAdminPublicKey` ('') — a double gate | `infra/main.bicepparam` pins `deployFleetVmss = false`, so default redeploys create nothing; `what-if` before enabling |
| VMSS sizing | Burst instances and lanes per instance | `fleetBurstMinInstances` 0, `fleetBurstMaxInstances` 5, `fleetVmSku` Standard_B2s, `fleetWorkersPerInstance` 2 | `infra/main.bicep` parameters | Reconciler only *requests* capacity (`az vmss scale`, absolute, ≤1 call/pass); scale-in belongs to the scale set's own policy |
| VMSS reconciler wiring | Whether scale-fleet can make the burst call | unset | env: `HELIOS_FLEET_VMSS_NAME`, `HELIOS_FLEET_VMSS_RG`, `HELIOS_FLEET_VMSS_WORKERS_PER_INSTANCE` (2 — keep matched to `fleetWorkersPerInstance`) | Unset is advisory (`burst wanted: N lane(s)`), never an error; burst lanes currently seed **empty** boards — capacity pre-provisioning, not throughput (CLOUD_SHELL_AND_LOCAL_FLEET.md) |
| Python spoke process cap | Concurrent `helios_agents` subprocesses from the hub | 4 slots, 30s per-call timeout | `src/ai/HELIOS.AIHub/Learning/PythonInsightsSpoke.cs` (`SemaphoreSlim ProcessSlots`, a compile-time constant — deliberately not config) | Insights are advisory: a missing interpreter or saturated slots degrade to `null`, never an exception |
| API access posture | Who may call `helios-ai-api` `/v1/*` | loopback-only | `HELIOS_API_ACCESS_KEY` env; enforcement in `src/ai/HELIOS.AIHub.Api/ApiEndpoints.cs` (`X-HELIOS-Api-Key`, fixed-time compare) | The key enables *direct* remote callers only; hosted deployments still need identity-aware ingress — scaling API replicas never relaxes this |
| Model capacity (tokens/min) | Azure model deployment throughput | `modelCapacity` / `additionalModelDeployments[].capacity` | `infra/main.bicepparam` | Size against the *sum* of concurrent lanes (36 at full burst), not one pool; capacity is also the structural spend bound |
| Absorption benchmark parallelism | Concurrent absorb-pr benchmarks on the fleet | uncapped (`-Max` 0) | `scripts/fleet/seed-absorption-tasks.ps1 -Max <n>` (board `xcore-infra`, lane `infrastructure`) | Each benchmark is a full build+test gate — the infra pool's enforced local ceiling is `autoscaling.maxLocalLanes` **3**, so cap `-Max` at 2 to leave a lane free for other infra work; re-seeding is idempotent (`absorb-pr-<N>` ids) |
| Hub fan-out | Providers hit in parallel per request | `compare`/`tandem` provider list; per-provider circuit breakers | `config/aihub.json` chains | A 429 records a failure on that provider's circuit breaker and the fallback chain advances to the next provider — there is **no** automatic 429→board bridge; board tasks go `blocked` only when a worker calls `kanban_block` |

## .NET version guidance (asked constantly, so pinned here)

- **Today**: repo targets **net8.0** everywhere; net8.0 support ends **2026-11-10**.
- **Current LTS**: **.NET 10** (Nov 2025). The net10.0 upgrade is roadmap PR6 — one PR,
  all four projects together, plus `DOTNET_VERSION` bumps in workflows.
- **.NET 11**: **preview only** (ships Nov 2026). Track features; never target in
  committed code and never describe as GA. WinUI 3 work (GUI_THEME_ANALYSIS.md) should
  land on .NET 10, not wait for 11.

## Maintaining the table

Edit `config/aihub.json`, not code. Chains are ordered (primary first). Every provider
named in a chain must exist in `providers`/`cliAgents` — `ConfigBindingTests` fails CI
otherwise. When a new model class genuinely changes a row (e.g., a cheaper reviewer),
update the chain and this document's *why* in the same PR.
