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
"cross-LLM shell workload").

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

## Cost & latency ladder

Cheapest/fastest first, for when the task tolerates it: Copilot inline → small models via
GitHub Models / `gpt-5-mini` → Ollama local (free, hardware-bound) → frontier models
(Claude Opus/Sonnet 5, GPT-5-class) → agentic CLI sessions (highest token spend, highest capability).
The routing table encodes this: chains lead with the cheapest provider that usually
succeeds and fall back upward. Budget guardrails: model `capacity` in Bicep bounds
Azure spend structurally; per-provider circuit breakers stop retry storms.

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
