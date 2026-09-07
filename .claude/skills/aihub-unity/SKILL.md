---
name: aihub-unity
description: The HELIOS hub as ONE system — which model, provider, or combination to use for a task, what it costs in tokens and time, when tandem beats route and when compare earns its fan-out, how the F# score and the C++ learner weigh cost against success, the Hermes/Xcore fleets as executors, one Cloud Shell as the unity surface, and the absorber as the learning intake. Use for ANY question about which model/provider/combo to use, cost or tokens, tandem/compare/route trade-offs, fleets, Cloud Shell unity, or the absorption pipeline.
---

# AIHub unity — one hub, every shell, every model, one learning store

HELIOS runs **one** hub. Azure Cloud Shell, Codespaces, local `pwsh`/`bash`, and the
WinUI 3 shell; every provider and model in `config/aihub.json`; every agent — Claude
Code, Codex CLI, Copilot, Hermes lanes, the four Xcore-9 pools; and both access planes
— Azure through OIDC, the ops workload identity, and Key Vault *by name*; local through
Ollama, the fleet stub, and Docker — all reach `AIHubService`
(`src/ai/HELIOS.AIHub/AIHub.cs:18`) through the same four contracts: the `helios-ai`
CLI, the `/v1` REST surface, the `helios_*` MCP tools, and the `helios-operator` plugin
over that same MCP server. Every routed, tandem, fleet-lane, or benchmark outcome lands
in one `ILearningStore` (`src/ai/HELIOS.AIHub/Learning/LearningStore.cs:85-127`). The
system design with every seam cited is `docs/architecture/AIHUB_LANGUAGE_ROLES.md`.

## The five commands and what each spends

Grammar from `src/ai/HELIOS.AIHub.Cli/Program.cs:406-434`; REST and MCP twins in
`docs/architecture/AIHUB_LANGUAGE_ROLES.md` "The center".

| Command | Calls | Records outcomes | Use when |
|---|---|---|---|
| `helios-ai route <task> "<prompt>"` | First success in the (learned) chain; fallbacks only on failure (`AIHub.cs:171-252`) | Yes, per attempt | The default. One task type, one answer |
| `helios-ai tandem <task> "<prompt>"` | Every provider in the chain concurrently; winner = first success in learned order (`AIHub.cs:747-782`) | Yes, every provider | Two providers genuinely differ in latency or failure mode and you want evidence for future single-shot routing |
| `helios-ai compare "<prompt>" [--providers a,b]` | Every named (or every Ready) provider in parallel; near-duplicates flagged (`AIHub.cs:712-728,509-566`) | **No** (no task type) | Confidence via disagreement on a decision; never for bulk |
| `helios-ai ask "<prompt>" --provider P [--model M]` | Exactly one provider | No | You already know the provider |
| `helios-ai ask "<prompt>" --optimize <cost, latency, quality, or balanced> --for <task>` | One provider/model the static catalog ranks best among *Ready* providers (`AIHub.cs:138-149`) | No | "Objectively cheapest/fastest for this kind of task", before any history exists |

Read-only companions that spend nothing: `status`, `routing`, `providers`,
`fleet-plan`, `engine-plan`, `engines`, `absorb-status` (`Program.cs:153-364`).

## Where cost is measured today

- Per outcome: `RoutingOutcome.CostUsd` = catalog rate × reported usage
  (`AIHub.cs:688-709`, `Pricing.fs:47-49`), `0` when usage or a confident rate match is
  missing. CLI agents report no usage, so `claude-cli`, `codex`, `copilot`, `gh-models`,
  and `hermes` record `0` (`Providers/CliProcessAgent.cs:97`).
- Per provider: `GET /v1/metrics` → `TotalCostUsd`, `AverageCostUsd`,
  `AverageLatencyMs`, `SuccessRate`; `TokensUsed` and `CostPerMillionTokens` are
  always `null` (`src/ai/HELIOS.AIHub.Api/ApiModels.cs:113-117`).
- Prior, not measurement: `config/model-catalog.json` `inputPerMillionUsd` /
  `outputPerMillionUsd` ("as of Aug 2026" in its own `$comment`).

Depth and the pricing-block proposal for `config/aihub.json`:
`references/model-strengths-and-cost.md`.

## The combo calculus in one paragraph

The hub maximizes a weighted score per provider — success 0.55, quality 0.25, latency
0.10, cost 0.10 (`src/ai/HELIOS.AIHub.Domain/RoutingPolicy.fs:48-49`) — over organic
outcomes for one task type, reorders only providers with ≥ 5 attempts, and blends in the
native MLP's prediction at most 50 % (`LearnerFusion.fs:192-194`). Context budget
narrows the chain first (`ContextBudget.fs:50-58`); readiness and circuit breakers
decide who may be tried at all. Formal statement, the quoted formulas, and worked
numbers: `references/combo-calculus.md`.

## Ideal-combo procedure (repo commands only)

1. `helios-ai status` — who is Ready; Unconfigured hints name the env var to set.
2. `helios-ai routing` — the configured chain for the task type.
3. `curl -s "http://localhost:5170/v1/metrics?limit=200"` and
   `…/v1/learning?taskType=<task>&limit=50` — measured cost, latency, success so far.
4. Cold start (no history): `helios-ai ask "<prompt>" --optimize balanced --for <task>`
   or plain `route`.
5. Two candidates that differ in kind (API vs CLI): `helios-ai tandem <task> "<prompt>"`
   a handful of times; the winner marker is the learned favorite among successes.
6. A decision, not a deliverable: `helios-ai compare "<prompt>" --providers a,b`.
7. Repetitive agentic work: `pwsh scripts/fleet/start-fleet.ps1 -DryRun`, seed the
   board, `helios-ai fleet-plan` to compare configured vs learned chains — advisory only.
8. Nothing here edits config; chain changes are human edits to `config/aihub.json` or
   `config/fleet/fleet-topology.json`.

Model and tool pairing per phase and language, with automation recipes and their
token/time cost: `references/model-and-tool-pairing.md`.

## Token-saving patterns that exist

- **Context budget**: prompts that cannot fit a provider's window are not sent to it
  (`AIHub.cs:341-390`; reserved output `min(4096, window/4)`, `AIHub.cs:426`).
- **Per-task chains**: `general_query` and `bulk_processing` lead with cheap or free
  tiers (`config/aihub.json:204-214`); `documentation_generation` falls back to
  `github-models`.
- **Local-first**: `offline → ollama`; the fleet stub does no model work at all
  (`scripts/fleet/start-fleet.ps1:1-14`).
- **Circuit breakers** stop paying for a failing provider: 5 failures, 60 s
  (`Resilience/CircuitBreaker.cs:28-37`).
- **Provider prompt caching: not wired.** `ChatClientAgent` sets only `ModelId`,
  `MaxOutputTokens`, `Temperature` (`Providers/ChatClientAgent.cs:51-56`);
  `AnthropicMessageMapping` sends no cache directives. Say so rather than promising it.

## One Cloud Shell, fleets as executors, the absorber as intake

- Bring-up is `bash scripts/bootstrap/first-run.sh` (twin `first-run.ps1`): an ordered
  soft chain over the existing scripts, `.helios/bootstrap-state.json`, and a numbered
  owner checklist (`scripts/bootstrap/first-run.sh:1-60`). The one-sitting login is
  `pwsh scripts/bootstrap/connect-devices.ps1` (bash twin `connect-devices.sh`): both
  device codes — gh and az — on one screen, then the chain without another prompt: the
  GitHub Models token export (dot-sourced), the GitHub App via
  `connect-github-app.ps1 -DispatchGovernance`, the ops identity via
  `connect-admin.ps1 -SkipGitHub`, `auto-login.ps1`, `auth-doctor.ps1 -Json`, and
  `first-run.sh --verify-only` (`scripts/bootstrap/connect-devices.ps1:4-5,33-52`);
  `bash scripts/bootstrap/first-run.sh --connect` runs those logins as step 0 with
  `-SkipChain`, since `first-run.sh` is the chain (`first-run.sh:53,132-155`). Every
  lane is verify-first (`connect-all.ps1` is the per-lane orchestrator it builds on);
  identity pinning and the `helios-ops-automation` workload-identity bridge are
  `connect-account.ps1`; Key Vault values enter process env only, by the names
  `config/aihub.json` declares.
- The GitHub App `helios-control-<owner>` is wired (PR #241):
  `scripts/bootstrap/connect-github-app.ps1` registers it through the manifest flow —
  two owner clicks, Create then Install — stores the repository variables
  `HELIOS_APP_CLIENT_ID` / `HELIOS_APP_ID` / `HELIOS_APP_SLUG` and the secret
  `HELIOS_APP_PRIVATE_KEY`, waits for the installation, and with `-DispatchGovernance`
  fires the first governance apply (`connect-github-app.ps1:17-29,71-77`).
  `.github/workflows/governance-run.yml` mints a per-run installation token with
  `actions/create-github-app-token@v3` (`governance-run.yml:82-88`); precedence for
  `ADMIN_TOKEN` is app token → `HELIOS_ADMIN_TOKEN` PAT → `github.token`
  (`governance-run.yml:126`). Projects v2 still needs the owner's classic PAT with the
  `project` scope, and ARC runner auth is still docs-level
  (`.claude/skills/github-control/references/auth-topology.md:71-95,124-136`). Azure
  deploys federate via OIDC with no client secret (`docs/architecture/HYBRID_CLOUD_ARCHITECTURE.md`).
- Fleets execute; they do not decide. `agent_fleet_dispatch → hermes`; pools and chains
  are config; `fleet-plan` only reports (`src/ai/HELIOS.AIHub/Fleet/FleetPlanService.cs:49-52`).
- The absorber benchmarks upstream PRs and posts `source: "absorption-benchmark"`
  outcomes that inform insights and never steer chains
  (`scripts/absorption/absorb-pr.ps1:287-299`; `Learning/ChainReorderEngine.cs:25-37`).

## Invariants

Advisory only, nothing auto-executes (`config/aihub.json:218`, `adaptiveRouting: false`
by default); external signals never steer provider order; names not values; fleets and
agents cannot grant themselves cloud or production authority (CLAUDE.md "Multi-LLM
hub"); WinUI 3 only (`docs/architecture/ADR-0010-WINUI3-ONLY.md`). The language dimension
for routing landed in PR #248 (`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`):
`route <task-type> "<prompt>" --language <lang>` (`src/ai/HELIOS.AIHub.Cli/Program.cs:79-107`),
`helios_ai_route`'s `language` parameter (`src/mcp/HELIOS.Mcp/HeliosAiTools.cs:32-48`), and
`HubRouteRequest.Language` (`src/ai/HELIOS.AIHub/Abstractions/ChatModels.cs:28-32`) pick
`taskRouting["<taskType>:<language>"]` before the bare key (`TaskTypeRoutingStrategy.GetChain`,
`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs:168-196`); outcomes carry the
normalized language (`Learning/LearningStore.cs:27-37`) and learning is scoped per
`(taskType, language)` (`ChainReorderEngine.ForLanguage`, `Learning/ChainReorderEngine.cs:49-62`).
No language given → the pre-#248 behavior, byte for byte.

## Reference material

- [references/model-strengths-and-cost.md](references/model-strengths-and-cost.md) —
  every provider and model family in `config/aihub.json` and
  `config/model-catalog.json`, kept consistent with
  [docs/architecture/LLM_STRENGTHS_PLAYBOOK.md](../../../docs/architecture/LLM_STRENGTHS_PLAYBOOK.md);
  where cost is measured; the cost ladder; the labelled pricing-block proposal.
- [references/combo-calculus.md](references/combo-calculus.md) — the optimization the
  hub implements, stated formally from the code: objective, decision variables,
  constraints, update rules, quoted formulas, and worked numeric examples on a small
  fixture.
- [references/model-and-tool-pairing.md](references/model-and-tool-pairing.md) — when
  to use each model and each tool surface (Codex CLI, Claude Code, Copilot, `gh`, the
  API providers, the fleet), the pairing matrix by phase × language, and automation
  recipes with their relative cost.
- System view: [docs/architecture/AIHUB_LANGUAGE_ROLES.md](../../../docs/architecture/AIHUB_LANGUAGE_ROLES.md).
- Report-only advisor: [.claude/agents/aihub-strategist.md](../../agents/aihub-strategist.md).
