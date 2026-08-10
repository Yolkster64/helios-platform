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
| Many similar tasks executed in bulk | **Hermes fleet** (`agent_fleet_dispatch`) | Nine Xcore lanes beat one giant prompt (HERMES_FLEET_AND_XCORE.md) |
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

## Cost & latency ladder

Cheapest/fastest first, for when the task tolerates it: Copilot inline → small models via
GitHub Models / `gpt-4o-mini` → Ollama local (free, hardware-bound) → frontier models
(Claude, GPT-4-class) → agentic CLI sessions (highest token spend, highest capability).
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
