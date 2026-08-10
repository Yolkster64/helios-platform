# Multi-LLM Integration — Design

The HELIOS AIHub (`src/ai/HELIOS.AIHub`) is the platform's single integration layer for
every LLM provider, consolidating the three prior partial attempts (`cloud-integration/`
C# dead code, `scripts/ai-services/` OpenAI-only PowerShell, and the orphaned GUI
`AIHubWindow`) behind the core seams `IAgent`/`IRouter`.

## Provider matrix

| Provider key | Access | Package / mechanism | Auth | Notes |
|---|---|---|---|---|
| `openai` | SDK (REST under the hood) | `OpenAI 2.12.0` → `IChatClient` | `OPENAI_API_KEY` | ChatGPT/Codex-class models |
| `anthropic` | SDK, native Messages API | `Anthropic.SDK 5.10.0` | `ANTHROPIC_API_KEY` | Community SDK isolated behind `ProviderFactory`; raw-REST fallback documented below |
| `azure-openai` | SDK | `Azure.AI.OpenAI 2.1.0` | endpoint + key **or** Entra ID (`DefaultAzureCredential`) | Model = *deployment name* from `infra/main.bicepparam` |
| `azure-foundry` | SDK | `Azure.AI.Agents.Persistent 1.1.0` | Entra ID against `projectEndpoint` | Foundry Agent Service: agent + thread + run + poll |
| `github-models` | REST (OpenAI-compatible) | `OpenAI` client @ `https://models.github.ai/inference` | `GITHUB_MODELS_TOKEN` / `GITHUB_TOKEN` | API-shaped access to the GitHub catalog |
| `ollama` | REST | `OllamaSharp 5.4.30` (`IChatClient`) | none (`OLLAMA_BASE_URL`) | Offline/local |
| `claude-cli`, `codex`, `copilot`, `gh-models`, `hermes` | CLI subprocess | `CliProcessAgent` argv templates | each CLI's own login | The cross-LLM shell primitive |

**GitHub Copilot has no public completion API.** The old
`cloud-integration/configs/copilot.config.json` pointed at a fictional
`api.copilot.microsoft.com` surface. Copilot integrates two real ways: the `copilot` CLI
as a process agent, and GitHub Models for API-shaped calls. The Copilot *coding agent*
(issue → PR) is a GitHub-side workflow, not an API client (see GITHUB_ECOSYSTEM_DESIGN.md).

## Layering

```
config/aihub.json ──► AIHubOptions ──► ProviderFactory ──► IChatProviderAgent[]
                                                            (ProviderAgentBase)
AgentRequest → ChatRequest mapping        ┌── ChatClientAgent (M.E.AI IChatClient: openai,
IAgent seam (source-linked from core) ────┤    azure-openai, github-models, ollama)
                                          ├── AnthropicAgent (native SDK)
                                          ├── FoundryAgentProvider (persistent agents)
                                          └── CliProcessAgent (argv template, no shell)
AIHubService ──► TaskTypeRoutingStrategy (IRouter/IRoutingStrategy seam)
             ──► FallbackChain + per-provider CircuitBreaker
             ──► CompareAsync parallel fan-out
Consumers: helios-ai CLI · HELIOS.Mcp (MCP stdio) · future core "ai" command (PR2)
```

Design invariants:

- **Unconfigured is a state.** A missing key/endpoint yields a registered provider with
  `ProviderReadiness.Unconfigured` and an actionable hint — startup never throws, so
  `status` and CI stay deterministic in keyless environments.
- **Provider boundary converts exceptions to failed `ChatResult`s**, which the fallback
  chain treats as fall-through; cancellation always propagates.
- **The fallback chain is parameterized by provider** (`Func<string, Task<T>>`) — fixing
  the ported `cloud-integration` bug where every "fallback" re-invoked the primary.
- **Secrets flow one way**: env var → Key Vault (`AZURE_KEY_VAULT_URI`) → Unconfigured.
  `config/aihub.json` holds env-var *names*; Bicep writes the vault secrets.

## Anthropic raw-REST fallback

If `Anthropic.SDK` ever blocks an upgrade, replace `AnthropicAgent.ChatCoreAsync` with a
direct `HttpClient` call — the surface we use is small:
`POST https://api.anthropic.com/v1/messages` with headers `x-api-key`,
`anthropic-version: 2023-06-01`, body `{model, max_tokens, system?, messages:[{role:"user",
content}]}`; read `content[].text` and `usage.input_tokens/output_tokens`. The rest of the
class (metrics, readiness, error conversion) is inherited and unchanged.

## Parallelism & autoscaling

- **Request fan-out**: `CompareAsync` runs providers concurrently (`Task.WhenAll`);
  `RouteToMultipleAsync` on the router seam supports N-agent selection for consensus
  patterns.
- **Capacity**: Azure model deployment `capacity` (thousands of TPM) is a Bicep parameter
  — scale by re-deploying; per-provider circuit breakers shed load to fallbacks when a
  provider saturates (429s open the circuit after 5 consecutive failures, 60s cooldown,
  half-open probe).
- **Fleet-level parallelism** (many agents, not many calls): HERMES_FLEET_AND_XCORE.md.

## Learning loop (opt-in)

`config/aihub.json`'s `learning` block turns routing into a feedback loop instead of a
static table. When `enabled: true`, every routed call's outcome (provider, success,
latency, cost, optional quality) is appended via `ILearningStore` — `local` (JSONL under
`.helios/learning/`), `azure` (Table Storage, partitioned by task type), or `hybrid`
(both; local is authoritative, Azure syncs best-effort and never blocks a call).

Before each routed call, `AIHubService.RouteAsync` asks the **F# `RoutingPolicy`**
(`src/ai/HELIOS.AIHub.Domain`) to reorder the configured chain from recent history.
Providers with fewer than 5 recorded attempts keep their configured position — thin
evidence must not demote a good provider on one unlucky run — so day one behaves exactly
like the static table, and the chain only starts moving once there's something to learn
from. `RoutingPolicy.explain` is available for surfacing *why* a chain was reordered.

F# domain logic is exposed to C# through a thin interop surface
(`RoutingPolicyInterop`, `PricingInterop`) that takes only primitives and arrays — no
F#-only types cross the boundary, per the fsharp-functional skill's interop rule. The
same module's `Pricing` functions (with units of measure — see PR3 for wiring
`CostUsd` from real provider usage instead of the current placeholder `0`) turn raw token
counts into dollar estimates without the token/million unit-mixing bug that plagues
hand-rolled cost math.

## Native spoke (optional, not yet wired)

`src/ai/HELIOS.AIHub.Native` is a C++ library (CMake, flat C ABI, `LibraryImport`
P/Invoke) for the numeric hot paths that belong outside managed code: cosine similarity
across a `compare` fan-out's embeddings, and UTF-8-safe token/prefix estimation. It
builds independently of the .NET solution and nothing calls into it yet — wiring `compare`
to use it for response dedup is PR3 scope. See `src/ai/HELIOS.AIHub.Native/README.md`.

## REST orchestration API

`src/ai/HELIOS.AIHub.Api` (`helios-ai-api`) exposes the same `AIHubService` singleton the
CLI and MCP server use as a minimal-API HTTP surface, so anything that speaks HTTP — a
WinUI 3 shell, Python agents, Cloud Shell scripts, other services — orchestrates through
one door with shared circuit-breaker and learning state:

| Endpoint | Verb | Purpose |
|---|---|---|
| `/healthz` | GET | Liveness (no hub touch) |
| `/v1/status` | GET | Provider readiness, no network calls |
| `/v1/routing` | GET | Default chain + task-routing table |
| `/v1/learning?taskType=&limit=` | GET | Recent routing outcomes, newest first |
| `/v1/ask` | POST | One provider (or default chain): `{prompt, provider?, model?, system?}` |
| `/v1/route` | POST | Task-type chain with learned reorder + fallback: `{taskType, prompt, system?}` |
| `/v1/tandem` | POST | Whole chain concurrently, learned winner reported |
| `/v1/compare` | POST | Parallel fan-out with duplicate flagging: `{prompt, providers?, system?}` |

Provider failures are payload (`200` + `success:false` + `error`), not transport errors;
`4xx` is reserved for malformed requests. Config resolution matches the CLI:
`--aihub-config`, then `AIHUB_CONFIG`, then walking up to `config/aihub.json`.

## Testing

41 unit tests, no network: fallback switching regression, breaker transitions, routing
strategy, real-config binding (drift fails CI), CLI process fixtures, fake `IChatClient`
mapping tests, the local learning store's round-trip/filter/limit/torn-line behavior, and
the F# routing policy's promotion/thin-evidence/empty-history cases through its C#
interop surface. Live-API calls are deliberately untested in CI; `helios-ai status` +
smoke runs cover wiring.
