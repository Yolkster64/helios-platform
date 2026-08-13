# Provider SDKs — working API knowledge per integration

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Every claim below is grounded in `src/ai/HELIOS.AIHub/` — read the cited file before
extending a provider. Package versions: `references/nuget-packages.md`.

## The IChatClient seam (Microsoft.Extensions.AI)

One implementation, `Providers/ChatClientAgent.cs`, covers OpenAI, GitHub Models, Azure
OpenAI, and Ollama. The contract:

- Build `List<ChatMessage>` (`ChatRole.System` first when a system prompt exists, then
  `ChatRole.User`), plus `ChatOptions { ModelId, MaxOutputTokens, Temperature }`.
- `await client.GetResponseAsync(messages, options, ct)` → `response.Text`,
  `response.ModelId`, `response.Usage?.InputTokenCount/OutputTokenCount`.
- Clients are cached per model in a `ConcurrentDictionary<string, IChatClient>` keyed by
  the request's model string, so per-request model overrides get their own client.
- A **null client factory means Unconfigured** — construction never throws for missing
  secrets; readiness surfaces via `ProviderReadiness` with a `ConfigurationHint`.

## Per-SDK construction (Providers/ProviderFactory.cs)

| Provider | Construction | Trap |
|---|---|---|
| OpenAI | `new OpenAIClient(key).GetChatClient(model).AsIChatClient()` | Key from `OPENAI_API_KEY` or Key Vault `openai-api-key` |
| GitHub Models | `new OpenAIClient(new ApiKeyCredential(key), new OpenAIClientOptions { Endpoint = baseUri })` | Endpoint `https://models.github.ai/inference`; token needs `models:read`; malformed baseUrl → Unconfigured, not a crash |
| Azure OpenAI | `new AzureOpenAIClient(endpointUri, ApiKeyCredential \| DefaultAzureCredential)` then `GetChatClient(deployment)` | See both traps below |
| Ollama | `new OllamaApiClient(new Uri(endpoint), model)` — already an `IChatClient` | Endpoint `OLLAMA_BASE_URL` → config `baseUrl` → `http://localhost:11434` |

**Azure deployment-vs-model trap**: the string passed to Azure's `GetChatClient` is the
*deployment* name created by `infra/main.bicep`, not the underlying model id. The
deployment names default to model names in this repo's infra, which hides the distinction
until someone renames one.

**Credential-chain trap**: with no `AZURE_OPENAI_API_KEY`, the factory falls back to
`DefaultAzureCredential` (az login → managed identity → workload identity). That
credential resolves lazily — a broken chain fails at first call, not at construction, so
`status` can show Ready for a provider that 401s on use.

## Anthropic.SDK (Providers/AnthropicAgent.cs)

Native Messages API, not the SDK's `IChatClient` adapter (deliberate — see the file's doc
comment). Surface: `new AnthropicClient(apiKey)`, `MessageParameters { Model, MaxTokens,
Messages = [new(RoleType.User, prompt)] }`, system prompt as
`List<SystemMessage>`, `Temperature` is **decimal** (cast from double). Call
`client.Messages.GetClaudeMessageAsync(parameters, ct)`; concatenate
`response.Content.OfType<TextContent>()`. `MaxTokens` is required — the repo defaults 4096.

## Azure.AI.Agents.Persistent (Providers/FoundryAgentProvider.cs)

`new PersistentAgentsClient(projectEndpoint, new DefaultAzureCredential())` — the endpoint
is the `projectEndpoint` output of `infra/main.bicep`, not the OpenAI endpoint. Request
flow: `Administration.CreateAgentAsync(model, name, instructions)` →
`Threads.CreateThreadAsync` → `Messages.CreateMessageAsync(threadId, MessageRole.User, …)`
→ `Runs.CreateRunAsync` → poll `GetRunAsync` while `Queued|InProgress` →
`Messages.GetMessagesAsync(order: ListSortOrder.Ascending)` reading `MessageTextContent`
from `MessageRole.Agent` messages.

Pitfalls the implementation already encodes — keep them when touching it:

- **A persistent agent bakes model AND instructions at creation.** Reusing one agent
  pins every caller to the first request's system prompt; the cache is keyed by
  `(model, instructions)` and bounded (8) with deferred remote deletion.
- **Threads are per-request service-side state** — delete in `finally` with
  `CancellationToken.None` (cleanup must run for cancelled callers), and swallow all
  cleanup failures: an orphaned thread beats masking a completed paid run.

Administration surface (`Providers/FoundryAgentAdministrationService.cs`, behind the
`helios_foundry_agent_*` MCP tools): `Administration.GetAgentsAsync(limit: …)` returns
an `AsyncPageable<PersistentAgent>` that pages transparently — bound total enumeration
yourself; `Administration.CreateAgentAsync(model, name, description, instructions)` is
issued exactly once, never retried (a retry could double-create). The SDK client hides
behind the `IFoundryAgentAdministration` seam so tests run keyless against a fake.

## Key Vault + Tables (Configuration/SecretResolver.cs, Learning/AzureTableLearningStore.cs)

- `SecretClient(new Uri(uri), new DefaultAzureCredential())`; resolution order is env var
  → Key Vault → null. Catch `RequestFailedException` and `AuthenticationFailedException`
  to null — bad auth is "unconfigured", never a startup crash. Results (including null)
  are cached per secret name.
- `TableClient(endpoint, "aihubOutcomes", new DefaultAzureCredential())` with lazy
  `CreateIfNotExistsAsync` behind a `SemaphoreSlim`. RowKey is inverted ticks
  (`MaxValue.Ticks - timestamp.Ticks`) because Table Storage only sorts ascending and
  reads want newest-first. Partition key = task type → single-partition queries.

## ModelContextProtocol (src/mcp/HELIOS.Mcp/)

- Hosting (`Program.cs`): `Host.CreateApplicationBuilder` + `AddMcpServer()
  .WithStdioServerTransport().WithToolsFromAssembly()`. **stdout belongs to the protocol**:
  clear the default console logger and re-add it with
  `LogToStandardErrorThreshold = LogLevel.Trace`, or JSON-RPC framing breaks.
- Tools (`HeliosAiTools.cs`, `HeliosStatusTools.cs`, `HeliosFoundryTools.cs`): static
  class marked `[McpServerToolType]`; each method `[McpServerTool(Name = "helios_…",
  Idempotent = …, OpenWorld = …)]` + `[Description]` on method and every parameter. DI
  services (`AIHubService`, `PythonInsightsSpoke`, `FoundryAgentService`) are injected
  as ordinary leading parameters; `CancellationToken` last. Return JSON strings
  (`JsonSerializer.Serialize`), not objects.

## Not in the repo (candidates)

- **`Azure.AI.Projects` / `Azure.AI.Inference`**: alternative Foundry SDK surfaces. The
  repo standardizes on `Azure.AI.Agents.Persistent` for agents and `Azure.AI.OpenAI` for
  models; adopt `Azure.AI.Projects` only when connection-listing/project-management APIs
  are needed (roadmap PR3 scope, `docs/architecture/ROADMAP_MULTI_LLM.md`).
- **Anthropic `IChatClient` adapter**: would let `ChatClientAgent` absorb Claude too.
  Adopt only if the abstractions-version handshake risk documented in
  `AnthropicAgent.cs` is retired (e.g. once CPM pins both packages in one place).
