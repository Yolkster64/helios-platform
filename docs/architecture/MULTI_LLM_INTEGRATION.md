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

## Testing

31 unit tests, no network: fallback switching regression, breaker transitions, routing
strategy, real-config binding (drift fails CI), CLI process fixtures, fake `IChatClient`
mapping tests. Live-API calls are deliberately untested in CI; `helios-ai status` +
smoke runs cover wiring.
