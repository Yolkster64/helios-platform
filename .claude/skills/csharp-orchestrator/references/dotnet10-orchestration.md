# .NET 10 orchestration — the hub's patterns as shipped

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Companions: `provider-sdks.md` (per-SDK surfaces),
`dotnet-10-and-11.md` (language/runtime policy), `testing.md` (how each pattern is
tested), `nuget-packages.md` (pins). System view:
`docs/architecture/AIHUB_LANGUAGE_ROLES.md`.

Every pattern names its exemplar as `path:line`. The traps are the ones the repo's own
review waves caught — most are annotated `(review finding)` in the code itself.

## Pattern 1 — one facade, four doors

`AIHubService` (`src/ai/HELIOS.AIHub/AIHub.cs:18`) is constructed once and shared by
the CLI (`src/ai/HELIOS.AIHub.Cli/Program.cs:41`), the REST host, and the MCP host
(`src/mcp/HELIOS.Mcp/Program.cs:27`, `AddSingleton(_ => AIHubService.CreateFromConfig())`).
Config resolution is explicit path → `AIHUB_CONFIG` → walk up to `config/aihub.json`
(`AIHub.cs:63-72`); the model catalog is resolved *beside the selected config*, never by
an unrelated directory walk (`AIHub.cs:54-60`).

Trap: a relative `learning.localPath` must anchor to the config root, not the process
CWD, or `.helios/` trees scatter wherever `helios-ai` runs (`AIHubOptions.cs:39-56`).

## Pattern 2 — unconfigured is a state

`ProviderFactory.Create` never throws for a missing key or endpoint: it returns an agent
whose `Readiness` is `Unconfigured` with a hint naming the exact variable
(`Providers/ProviderFactory.cs:12-15,111-122`). A malformed endpoint is also
Unconfigured — one bad variable must not take down `status` for every other provider
(`ProviderFactory.cs:172-179`). A declared-blank `endpointEnv` names the config defect,
not a variable called `""` (`ProviderFactory.cs:149-155`).

Trap: `DefaultAzureCredential` resolves lazily, so a provider can show Ready and 401 on
first use (`provider-sdks.md`, "Credential-chain trap"). `status` is readiness from
configuration, never a network probe (`Abstractions/ChatModels.cs:81-82`).

## Pattern 3 — the provider boundary converts, the chain falls through

`ProviderAgentBase.ChatAsync` (`Providers/ProviderAgentBase.cs:90-126`) turns every SDK
or transport exception into a failed `ChatResult`, so `FallbackChain` can advance.
Caller cancellation is rethrown; an SDK-internal `OperationCanceledException` (an HTTP
timeout the caller did not request) is a provider failure
(`ProviderAgentBase.cs:106-118`). The chain itself is parameterized by provider name
(`Func<string, Task<T>>`, `Resilience/FallbackChain.cs:48-59`) — the ported
`cloud-integration` code re-invoked the primary for every "fallback"
(`FallbackChain.cs:21-23`).

Soft failures carry a bounded, single-line reason into the exhausted-chain summary
(`FallbackChain.cs:108-121`, 240 chars). Per-provider `CircuitBreaker`: 5 consecutive
failures open the circuit for 60 s, then one half-open probe (`CircuitBreaker.cs:28-37`).

Trap: a success arriving while the circuit is Open belongs to a call admitted before it
opened and must not close it (`CircuitBreaker.cs:85-101`); a probe that never records
re-arms after another cooldown (`CircuitBreaker.cs:59-69`).

## Pattern 4 — fan-out is `Task.WhenAll`, never `await` in a loop

`CompareAsync` builds the task list, awaits all, then flags duplicates
(`AIHub.cs:712-728`). `TandemAsync` runs the whole chain concurrently, records every
result, and picks the winner from the *learned* order (`AIHub.cs:747-782`). The MCP
description states the intent: tandem runs feed the same evidence `RouteAsync` draws on
(`src/mcp/HELIOS.Mcp/HeliosAiTools.cs:51`).

Trap: unknown provider names become failed results inside the fan-out
(`AIHub.cs:721-724`), not exceptions — a typo in `--providers` must not abort the
other providers' calls.

## Pattern 5 — learning must never break routing

`ApplyLearningAsync` (`AIHub.cs:261-328`) returns the configured chain whenever learning
is off, adaptive routing is off, the task type is null, the organic history is empty,
the reordered chain contains an unknown provider, or the store throws. The catch list is
specific on purpose: `IOException`, `UnauthorizedAccessException`,
`Azure.RequestFailedException`, `Azure.Identity.AuthenticationFailedException`, and an
`OperationCanceledException` that is not the caller's (`AIHub.cs:305-327`). Recording is
best-effort with the same catch list (`AIHub.cs:636-680`).

Trap: `learning.historyWindow` is clamped to ≥ 1 before it reaches the store
(`AIHub.cs:271-273`) — a config typo must not fail routing. `FleetPlanService` repeats
the clamp and the degradation contract (`Fleet/FleetPlanService.cs:64-70,135-214`).

## Pattern 6 — the learned-reorder path lives in one class

`ChainReorderEngine.Reorder` (`Learning/ChainReorderEngine.cs:81-99`) is the single
implementation shared by `RouteAsync`, `TandemAsync`, and `fleet-plan`; a second copy
would report plans the hub would never execute (`ChainReorderEngine.cs:5-11`).
`OrganicOnly` drops every source-tagged record first (`ChainReorderEngine.cs:25-37`).
`NeuralRoutingLearner` flips newest-first history to chronological for prequential
training, caches weights on `(taskType, count, newest timestamp)`, and returns `null`
whenever it cannot beat the linear policy (`Learning/NeuralRoutingLearner.cs:44-115,
117-131`).

## Pattern 7 — cross-process append with a lock file

`LocalJsonlLearningStore.RecordAsync` serializes the line once, takes an in-process
`SemaphoreSlim`, then opens an adjacent `.lock` file with `FileShare.None` as the
cross-process mutex and appends with `bufferSize: 0` so the write is one OS append
(`Learning/LearningStore.cs:186-235`). The lock file is never deleted — deleting it
would race a peer holding the old inode (`LearningStore.cs:199-204`). Retries are
bounded and jittered (`LearningStore.cs:166-169,219-225`).

Traps: readers open with `FileShare.ReadWrite` because `File.ReadLines` would block a
concurrent append on Windows (`LearningStore.cs:282-285`); a torn line is skipped, never
fatal (`LearningStore.cs:300-303`); telemetry reads (`GetRecentAllAsync`) scale with
total file size by design (`LearningStore.cs:270-278`). `OutcomeId` exists because
telemetry fields are a lossy dedup key — two concurrent outcomes can share every field
(`LearningStore.cs:10-17`, review finding).

## Pattern 8 — subprocess boundaries

Two shapes, both owned by C#:

| Boundary | Class | Contract |
|---|---|---|
| Python spoke | `Learning/PythonInsightsSpoke.cs` | One JSON request on stdin, one response on stdout; static 4-slot `SemaphoreSlim`, 30 s timeout (`:16-17`); `null` on missing interpreter, timeout, broken pipe, or bad JSON (`:149-180`); tree-kill on exit, and the slot stays consumed if the OS cannot confirm exit (`:183-215`) |
| CLI agents | `Providers/CliProcessAgent.cs` | Prompt as one argv element, never a shell (`:7-12`); own and close stdin so CLIs that drain it do not hang (`:37-41,54`); kill the process tree on both cancellation paths (`:65-85`); non-zero exit → failed result with a 500-char tail (`:90-95`); a missing `{system}` slot folds instructions into the prompt (`:100-118`) |

Trap: disposing a `Process` does not terminate the child (`CliProcessAgent.cs:67-69`).

## Pattern 9 — native interop with `LibraryImport`

`Native/NativeMethods.cs:12-71` declares every export with `LibraryImport`,
`UnmanagedCallConv(CallConvCdecl)`, `ReadOnlySpan<T>`/`Span<T>` parameters, and `nuint`
lengths; `AllowUnsafeBlocks` is enabled only because the generated stubs need it
(`HELIOS.AIHub.csproj:9-11`). `NativeGate.Available` is a `Lazy<bool>` ABI handshake
(`Native/NativeGate.cs:9-35`) checked before every native call
(`AIHub.cs:444,516`, `NeuralRoutingLearner.cs:47`).

Trap: `Lazy<bool>` caches a thrown exception forever, so `BadImageFormatException` must
be caught inside the factory or every later check is poisoned (`NativeGate.cs:26-31`).
Add an export by bumping `helios_abi_version()` and `ExpectedAbiVersion` together
(`NativeMethods.cs:16-17`; `.claude/skills/cpp-performance/references/cpu-memory-graphics-abi.md`).

## Pattern 10 — minimal API: authorize before binding, failures as payload

`ApiEndpoints.MapAIHubApi` installs the access-key middleware *before* endpoint
selection because endpoint filters run after argument binding — a malformed remote POST
would otherwise get a binding response without ever being authorized
(`src/ai/HELIOS.AIHub.Api/ApiEndpoints.cs:32-45`). Loopback needs no key; remote
callers must send `X-HELIOS-Api-Key`, compared with
`CryptographicOperations.FixedTimeEquals` (`ApiEndpoints.cs:324-348`). Provider failures
are `200` with `success:false`; `4xx` is for requests the hub was never asked to run
(`ApiEndpoints.cs:13-15`).

Review-caught traps encoded in the endpoints: `quality` must be a finite `[0,1]`
(`:84-90`), `latencyMs` and `costUsd` non-negative finite (`:91-102`), aggregates that
overflow to non-finite become `null` rather than a 500 (`:171-182`), and unrated
outcomes never average as `0` (`:185-190`). `TokensUsed` and `CostPerMillionTokens`
are always `null` because `RoutingOutcome` persists no token counts
(`ApiModels.cs:113-117`).

## Pattern 11 — the MCP host

stdio owns stdout, so hosting logs go to stderr (`src/mcp/HELIOS.Mcp/Program.cs:21-25`).
Every tool declares `ReadOnly`/`Idempotent`/`OpenWorld` and a `[Description]` on the
method and every parameter (`HeliosAiTools.cs:18-26`); errors are `McpException` with an
actionable message (`HeliosAiTools.cs:137-147`). Advisory tools carry their advisory
note in-band (`HeliosFleetPlanTools.cs:30-33`). The extension checklist is the
`api-creator` skill.

## Pattern 12 — `Microsoft.Extensions.AI` as the common seam

`ChatClientAgent` covers OpenAI, GitHub Models, Azure OpenAI, and Ollama with one
`IChatClient` implementation, caching clients per model so per-request overrides get
their own client (`Providers/ChatClientAgent.cs:8-16,42`). Usage tokens come back as
`response.Usage?.InputTokenCount/OutputTokenCount` (`:66-67`) — the only place the hub
learns token counts, which is why CLI agents record `costUsd = 0`
(`CliProcessAgent.cs:97` returns no usage; `AIHub.cs:688-693`). Pins:
`Microsoft.Extensions.AI` 10.8.3 (`Directory.Packages.props:29`).

## Pattern 13 — C# in the WinUI 3 view model

`AIHubPageViewModel` captures `DispatcherQueue` on the UI thread in its constructor,
leaves the UI thread with `ConfigureAwait(false)`, and marshals every bound-property
touch through `TryEnqueue` (`src/gui/HELIOS.Shell/ViewModels/AIHubPageViewModel.cs:22-42,
54-70`). An unreachable API is a displayed state, never an exception
(`:72-103`). Depth: `.claude/skills/winui3-shell/references/winui3-and-legacy-wpf.md`.

## .NET 10 features actually used

- `net10.0` everywhere the portable solution builds (`HELIOS.AIHub.csproj:4`,
  `HELIOS.Mcp.csproj:5`); the shell stays `net8.0-windows10.0.19041.0` until the pinned
  Windows App SDK documents net10 (`HELIOS.Shell.csproj:17`).
- `TimeProvider` injection for testable clocks (`CircuitBreaker.cs:19,36`).
- List patterns at the interop edge: `result is [var provider, var model]`
  (`Configuration/ModelCatalog.cs:138`).
- Collection expressions (`[]`) for empty defaults (`AIHubApiClient.cs:75`).
- `CancellationToken` last with a default on every public async API; `ConfigureAwait(false)`
  in library code (SKILL.md "API design").

What *not* to adopt is in `dotnet-10-and-11.md`: no C# 15 preview features, no
`net11.0` targets, no `DllImport` where `LibraryImport` exists.

## When to route this work to which model or provider

Chains are `config/aihub.json:97-215`; reasoning is
`docs/architecture/LLM_STRENGTHS_PLAYBOOK.md`.

| C# work | Task type → chain (primary first) | Why |
|---|---|---|
| Facade or seam design, new door for the hub | `architecture_design` → `anthropic`, `anthropic-foundry`, `openai` | Tradeoff reasoning; use `helios-ai compare` for a second opinion |
| Provider adapter, options class, DTO mirroring | `code_generation` → `codex`, `openai-codex`, `openai`, `azure-openai`, `anthropic` | Mechanical from a spec; reconcile against this file before committing |
| Diff or PR review, boundary/exception audits | `code_review` → `anthropic`, `anthropic-foundry`, `claude-cli`, `openai` | Semantics over code; the review lanes stay Claude-led |
| "Why does this test fail" | `debugging` → `claude-cli`, `codex`, `openai-codex`, `openai` | Agentic CLIs gather context |
| xunit scaffolds for a new fake | `test_creation` → `codex`, `openai-codex`, `openai`, `anthropic` | Describable transformation |
| Reading a whole subsystem or a huge log | `long_context_analysis` → `anthropic`, `anthropic-foundry`, `claude-cli` | XL context tier |

The language-qualified form of these keys landed in PR #248
(`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`): `helios-ai route <task-type>
"<prompt>" --language csharp` looks up `taskRouting["<task-type>:csharp"]` first and falls
back to the bare task type (`TaskTypeRoutingStrategy.GetChain(taskType, language)`,
`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs:168-196`; `C#` and `cs` normalize
to `csharp` in `NormalizeLanguage`, `:67-80`). No `*:csharp` chain is shipped — the
qualified keys in `config/aihub.json` are `code_generation:cpp|fsharp|python` and
`code_review:bicep|powershell` (`config/aihub.json:105-125,144-156`) — so the table above is exactly what a
C# request gets, and `--language csharp` changes only the `language` recorded on the
outcome (`RoutingOutcome.Language`, `Learning/LearningStore.cs:27-37`), which scopes
adaptive learning to `(taskType, csharp)` (`ChainReorderEngine.ForLanguage`,
`Learning/ChainReorderEngine.cs:49-62`). Adding one is a config edit under `taskRouting` in
both `config/aihub.json` and `config/aihub.cloud.json`, beside the bare parent
(`ConfigBindingTests` rejects a qualified key whose parent is missing).
