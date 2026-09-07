# Model strengths and cost — what each lane is for, and where the money is measured

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* The reasoning behind the routing table is
`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md`; this file keeps the per-provider view
consistent with it and with `config/aihub.json` / `config/model-catalog.json`, and adds
the measurement story. Nothing here invents a price: every number is a catalog value
(a published prior) or a recorded outcome (a measurement), labelled as such.

## Provider and model families (consistent with the playbook)

Provider keys, default models, and auth names are `config/aihub.json:3-86`; classes,
context windows, and published per-million rates are `config/model-catalog.json:3-106`;
lane roles are the playbook's "Decision matrix by outcome" and "Per-surface optimal use".

| Provider key | Default model | Kind | Best at (playbook) | Leads these chains (`config/aihub.json:97-215`) | Auth name |
|---|---|---|---|---|---|
| `anthropic` | `claude-sonnet-5` | API | Honest diff review, long-context synthesis, architecture tradeoffs, security | `code_review`, `long_context_analysis`, `documentation_generation`, `code_analysis`, `security_analysis`, `architecture_design` | `ANTHROPIC_API_KEY` / `anthropic-api-key` |
| `anthropic-foundry` | `claude-sonnet-4-6` (a Foundry *deployment* name) | API | Same family inside the Microsoft Foundry boundary; Entra fallback when the key is absent | Second in every Claude-led chain | `ANTHROPIC_FOUNDRY_RESOURCE` + `ANTHROPIC_FOUNDRY_API_KEY` or Entra |
| `openai` | `gpt-5-mini` | API | One structured completion where you own the whole prompt; doc generation; `general_query` | Fallback in nearly every chain; leads nothing agentic | `OPENAI_API_KEY` / `openai-api-key` |
| `openai-codex` | `gpt-5.1-codex-max` | API | Codegen specialist for CI and containers where the `codex` CLI is absent; not live-smoked from a keyless environment (`config/aihub.json:11`) | Second in `code_generation`, `code_refactoring`, `test_creation`; third in `debugging` | same key as `openai` |
| `azure-openai` | `gpt-5-mini` (deployment) | API | Tenant-resident cheap tier; `bulk_processing` and `general_query` fallback | Leads `defaultChain` and `general_query` | `AZURE_OPENAI_ENDPOINT` + key or Entra |
| `azure-foundry` | `gpt-5-mini` | API (agent service) | The *boundary* is the value: Entra auth, tenant-resident execution, agent tools over Azure data | `enterprise_data` | `AZURE_FOUNDRY_PROJECT_ENDPOINT` + Entra |
| `github-models` | `openai/gpt-5-mini` | API (OpenAI-compatible) | Many cheap similar completions; free tier with a request cap | `bulk_processing`; second in `inline_completion` | `GITHUB_MODELS_TOKEN` / `GITHUB_TOKEN` |
| `ollama` | `llama3.2` | API (local) | Zero cloud dependency; the "is the network the problem?" control | `offline`; terminal fallback in `defaultChain`, `bulk_processing`, `general_query` | none (`OLLAMA_BASE_URL`) |
| `claude-cli` | — | CLI (`claude -p`) | Agentic gathering: multi-file reasoning, "why does this fail" | `debugging`; backs `code_review` and `long_context_analysis` | the CLI's own login |
| `codex` | — | CLI (`codex exec`, 600 s) | Repo-scale agentic edits: reads files, runs tests, iterates | `code_generation`, `code_refactoring`, `test_creation` | `codex login` or `OPENAI_API_KEY` |
| `copilot` | — | CLI (`copilot -p`) | In-editor latency; nothing else competes on it | `inline_completion` | one `gh` login |
| `gh-models` | `openai/gpt-5-mini` | CLI (`gh models run`, 300 s) | Batch classification and triage, no tools, 128K context | not in a chain today — `bulk_processing` routes to the `github-models` API provider | `gh` login |
| `hermes` | — | CLI (`hermes chat -q`) | Bulk *agentic* backlogs across the Xcore-9 pools | `agent_fleet_dispatch` | Hermes on PATH |

The playbook's tier table ("Model knowledge — choosing by tier, not by name") is the
choosing discipline: context tier first, cost tier second, latency class per moment.
When a tier claim disagrees with the catalog, the catalog wins and the playbook needs
a PR.

Catalog rows exist for `anthropic`, `openai`, `azure-openai`, `azure-foundry`,
`github-models`, and `ollama` only (`config/schemas/model-catalog.schema.json`
`provider` enum). Consequences worth knowing:

- `--optimize` can name `openai` with model `gpt-5.1-codex-max`, and the hub then sends
  the request to the `openai` provider with that model override
  (`src/ai/HELIOS.AIHub.Cli/Program.cs:53-70`, `AIHub.cs:132-149`); the `openai-codex`
  key itself is never ranked.
- `anthropic-foundry` has no catalog row, so its outcomes record `costUsd = 0` and it
  is never filtered by context window (`AIHub.cs:400-428,688-709`).
- CLI agents have no rows and report no usage, so their cost is unmeasured — a real
  gap, not a free lunch (the playbook calls agentic CLI sessions the highest token
  spend in the hub).

## Where cost is measured, field by field

| Where | What | Source |
|---|---|---|
| `RoutingOutcome.CostUsd` | `PricingInterop.EstimateCostUsd(inputPerMillion, outputPerMillion, inputTokens, outputTokens)` = `in/1e6·rateIn + out/1e6·rateOut`; exact model match, then prefix match, then a lone catalog entry; else `0` | `AIHub.cs:688-709`; `Pricing.fs:43-49,83-93` |
| `RoutingOutcome.LatencyMs` | Wall clock around `ChatCoreAsync`, including CLI process time | `ProviderAgentBase.cs:99-104`; `AIHub.cs:655` |
| `RoutingOutcome.Success`, `Quality`, `Pool`, `Source` | Success from the provider result; quality only via `POST /v1/learning` (advisory) or a future judge; pool from `HELIOS_FLEET_POOL`; source only on advisory ingests | `LearningStore.cs:45-73`; `AIHub.cs:636-659`; `ApiEndpoints.cs:70-124` |
| `GET /v1/metrics` | Per provider over the recent window (all task types, advisory included): `Attempts`, `Successes`, `AdvisoryCount`, `SuccessRate`, `AverageLatencyMs`, `TotalCostUsd`, `AverageCostUsd`, `AverageQuality` | `ApiEndpoints.cs:151-210`; `ApiModels.cs:101-134` |
| `GET /v1/insights?taskType=` | Python `provider_summary` (`avgCostUsd`, `totalCostUsd`, `recentSuccessRate`, …) and `detect_drift` | `analysis.py:54-127` |
| `helios-ai ask/route` stderr | `[provider/model in 1.2s, 1234→567 tokens]` when the provider reported usage | `Program.cs:384-396` |
| Not measured anywhere | Token counts on outcomes; CLI agent spend; prompt-cache hits (caching is not wired) | `ApiModels.cs:113-117`; `CliProcessAgent.cs:97`; `ChatClientAgent.cs:51-56` |

The unit discipline is in F#: rates are `float<usd/Mtoken>`, usage `int64<token>`, and
mixing per-token with per-million is a compile error (`Pricing.fs:6-11,18-29`).

## The cost and latency ladder (playbook, restated)

Cheapest and fastest first, for when the task tolerates it: Copilot inline → small
models via GitHub Models or `gpt-5-mini` → Ollama (free, hardware-bound) → frontier
models → agentic CLI sessions (highest spend, highest capability)
(`LLM_STRENGTHS_PLAYBOOK.md` "Cost & latency ladder"). Chains lead with the cheapest
provider that usually succeeds and fall back upward; Azure model `capacity` in Bicep
bounds spend structurally; circuit breakers stop retry storms.

Catalog priors, per million tokens, as published in `config/model-catalog.json` (Aug
2026 per its `$comment`; treat as a prior that rots, not a fact the hub verified):

| Provider / model | Class | Context | Input | Output |
|---|---|---|---|---|
| anthropic / `claude-opus-5` | frontier | 1,000,000 | 5.00 | 25.00 |
| anthropic / `claude-sonnet-5` | balanced | 1,000,000 | 3.00 | 15.00 |
| anthropic / `claude-haiku-4-5-20251001` | fast | 200,000 | 1.00 | 5.00 |
| openai / `gpt-5.4` | frontier | 400,000 | 10.00 | 30.00 |
| openai / `gpt-5.1-codex-max` | specialist | 400,000 | 1.25 | 10.00 |
| openai / `gpt-5-mini` | fast | 400,000 | 0.25 | 2.00 |
| azure-openai / `gpt-5-mini` | fast | 400,000 | 0.25 | 2.00 |
| azure-foundry / `gpt-5-mini` | fast | 400,000 | 0.25 | 2.00 |
| github-models / `openai/gpt-5-mini` | fast | 128,000 | 0.00 (capped) | 0.00 (capped) |
| ollama / `llama3.2` | local | 128,000 | 0.00 | 0.00 |

Worked cost at those priors (`Pricing.costOf`): 3,000 input + 1,200 output tokens on
`gpt-5.1-codex-max` = `0.003·1.25 + 0.0012·10 = 0.01575 USD`; the same shape on
`gpt-5-mini` = `0.00275 USD`; one million in and one million out on `claude-sonnet-5` =
`18.00 USD` (the value the repo's own test asserts,
`tests/HELIOS.AIHub.Tests/Learning/RoutingPolicyInteropTests.cs:57-62`).

## Where the learning loop weighs cost

Cost is one of four terms with weight 0.10 in the linear score
(`RoutingPolicy.fs:48-49`) and one of six features for the MLP
(`LearnerFusion.fs:97-113`), always inverse-normalized against the other providers in
the same task type — so a provider recording `0` (no usage) reads as "cheapest" until
its success rate or latency says otherwise. `references/combo-calculus.md` runs the
arithmetic.

## Pricing block proposal for `config/aihub.json` (PROPOSAL — not implemented)

Status: **proposal**. Today prices live only in `config/model-catalog.json`, keyed by
`(provider, model)` with no provenance fields and no coverage for `anthropic-foundry`
or CLI agents. `AIHubOptions` binds no pricing (`Configuration/AIHubOptions.cs:89-121`),
and `EstimateCostUsd` reads the catalog only (`AIHub.cs:695-708`). Adopting this block
would be a reviewed change to the binder, `EstimateCostUsd`, `ConfigBindingTests`, and
the playbook's model table — in one PR.

Proposed shape, per provider entry:

```json
"anthropic-foundry": {
  "type": "anthropic-foundry",
  "model": "claude-sonnet-4-6",
  "endpointEnv": "ANTHROPIC_FOUNDRY_RESOURCE",
  "apiKeyEnv": "ANTHROPIC_FOUNDRY_API_KEY",
  "pricing": {
    "unit": "usd-per-million-tokens",
    "inputPerMillionUsd": 0.0,
    "outputPerMillionUsd": 0.0,
    "cachedInputPerMillionUsd": null,
    "provenance": { "source": "<vendor price page or contract id, never a secret>", "verifiedUtc": "2026-01-01T00:00:00Z", "verifiedBy": "owner" },
    "estimateOnly": true
  }
}
```

Field semantics (all optional; absence keeps today's behavior):

| Field | Unit / type | Meaning |
|---|---|---|
| `unit` | fixed string | Must equal `usd-per-million-tokens` so the F# `Mtoken` measure is the only unit that ever reaches `Pricing.costOf` |
| `inputPerMillionUsd`, `outputPerMillionUsd` | non-negative number | Rates the provider bills; `0` for free tiers and local models |
| `cachedInputPerMillionUsd` | number or null | Reserved for provider prompt caching, which is not wired; null until a provider adapter reports cached-token usage |
| `provenance.source` | string | Where the number came from — a URL or a contract identifier, never a credential |
| `provenance.verifiedUtc` | RFC 3339 | When a human checked it; the strategist agent reports rates older than a threshold as stale |
| `provenance.verifiedBy` | string | Role, not an email |
| `estimateOnly` | bool | `true` marks a rate that exists to make cost *comparable* (for example a CLI agent's approximate per-run spend) and must never be presented as billing |

How the F# score would consume it: `EstimateCostUsd` would prefer the provider block
over the catalog row, pass the same two rates into `PricingInterop.EstimateCostUsd`
(`Pricing.fs:83-93`) unchanged, and stamp `RoutingOutcome.CostUsd` as today — the
score's cost term (`RoutingPolicy.fs:96-97`) needs no change because it normalizes
across providers. A CLI agent with `estimateOnly: true` would stop recording `0` and
start competing on cost honestly; a rate with a stale `verifiedUtc` should degrade to the
catalog value rather than be trusted. Until this lands, say "measured per outcome; see
`/v1/metrics`" and never quote a price the repo has not written down.
