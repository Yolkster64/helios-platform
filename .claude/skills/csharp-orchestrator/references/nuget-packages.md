# NuGet packages — per-project inventory and pitfalls

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Versions live directly in each `.csproj` today — there is **no** `Directory.Packages.props`
in the working tree (Central Package Management is a pending candidate; see
"Not in the repo" below). Pin exact versions, never floating `*`.

## src/ai/HELIOS.AIHub/HELIOS.AIHub.csproj

| Package | Version | Why it's here |
|---|---|---|
| `OpenAI` | 2.12.0 | Base OpenAI client; also fronts GitHub Models via endpoint override (`Providers/ProviderFactory.cs`) |
| `Microsoft.Extensions.AI` | 10.8.3 | `IChatClient` seam every chat provider is normalized onto (`Providers/ChatClientAgent.cs`) |
| `Microsoft.Extensions.AI.OpenAI` | 10.8.3 | `.AsIChatClient()` adapter over OpenAI/Azure chat clients |
| `Azure.AI.OpenAI` | 2.1.0 | `AzureOpenAIClient` for Azure OpenAI / Foundry Models (`ProviderFactory.CreateAzureOpenAi`) |
| `Anthropic.SDK` | 5.10.0 | Claude via its native Messages API (`Providers/AnthropicAgent.cs`) |
| `Azure.AI.Agents.Persistent` | 1.1.0 | Foundry Agent Service: agents/threads/runs (`Providers/FoundryAgentProvider.cs`) |
| `Azure.Identity` | 1.21.0 | `DefaultAzureCredential` for Azure OpenAI, Foundry, Key Vault, Tables |
| `Azure.Security.KeyVault.Secrets` | 4.10.0 | Secret fallback after env vars (`Configuration/SecretResolver.cs`) |
| `Azure.Data.Tables` | 12.11.0 | Shared learning store (`Learning/AzureTableLearningStore.cs`) |
| `OllamaSharp` | 5.4.30 | Local models; `OllamaApiClient` implements `IChatClient` directly |

Non-package dependencies in the same csproj: a `ProjectReference` to the F# domain spoke
(`HELIOS.AIHub.Domain.fsproj`), source-linked core seam files (`IAgent.cs`/`IRouter.cs`),
and conditional `None Include` items copying the optional C++ native library to output.

## src/mcp/HELIOS.Mcp/HELIOS.Mcp.csproj

| Package | Version | Why |
|---|---|---|
| `ModelContextProtocol` | 2.1.0 | MCP server: stdio transport, `[McpServerTool]` attribute surface |
| `Microsoft.Extensions.Hosting` | 10.0.10 | `Host.CreateApplicationBuilder` + DI for the server (`Program.cs`) |

## tests/HELIOS.AIHub.Tests/HELIOS.AIHub.Tests.csproj

| Package | Version | Note |
|---|---|---|
| `xunit` | 2.9.3 | Test framework |
| `xunit.runner.visualstudio` | 2.8.2 | `PrivateAssets=all` |
| `Microsoft.NET.Test.Sdk` | 17.9.0 | Required for `dotnet test` |
| `Microsoft.AspNetCore.Mvc.Testing` | 8.0.11 | `WebApplicationFactory` for API tests — **8.0.x must match the net8.0 TFM** |
| `Moq` | 4.20.72 | Referenced but currently **unused** — every test double is a hand-rolled fake (see `references/testing.md`) |
| `coverlet.collector` | 6.0.0 | Coverage collector, `PrivateAssets=all` |

`HELIOS.AIHub.Cli` and `HELIOS.AIHub.Api` carry no PackageReferences of their own — only a
ProjectReference to `HELIOS.AIHub` (see their csproj files).

## Pitfalls

- **The Azure.AI.OpenAI 2.x rewrite trap.** 2.x is a ground-up rewrite on top of the
  `OpenAI` 2.x library, not an upgrade of 1.0-beta. The 1.0-beta surface
  (`OpenAIClient(endpoint, cred)`, `ChatCompletionsOptions`, `GetChatCompletionsAsync`,
  `DeploymentName`) is gone; the 2.x pattern is a top-level `AzureOpenAIClient` from which
  you take `GetChatClient("<deployment-name>")` (Microsoft Learn migration guide,
  `dotnet-migration`; live usage in `Providers/ProviderFactory.cs`). Code samples from the
  1.0-beta era — most pre-2024 blog posts — will not compile against this repo's pin.
- **`GetChatClient` takes a deployment name on Azure, a model name everywhere else.**
  `ChatClientAgent`'s factory parameter is the raw string; only the Azure path names it
  `deployment` (`ProviderFactory.CreateAzureOpenAi`). Passing a model name like
  `gpt-5-mini` fails on Azure unless a deployment with that exact name exists.
- **Keep `Microsoft.Extensions.AI` and `Microsoft.Extensions.AI.OpenAI` on the same
  version** (both 10.8.3 today). The adapter package binds tightly to the abstractions
  version; skew produces `MissingMethodException` at runtime, not build errors.
- **`Microsoft.AspNetCore.Mvc.Testing` tracks the ASP.NET Core shared framework** — pin
  its major.minor to the TFM (8.0.x for net8.0). Bumping it past the TFM drags in
  framework bits the runner doesn't have.
- **`Anthropic.SDK` is community-owned.** The repo deliberately uses its native Messages
  API rather than its `IChatClient` adapter to avoid an abstractions-version handshake
  between two independently-released packages (`Providers/AnthropicAgent.cs` doc comment).
- **Restore is keyless by design.** Root `nuget.config` maps `*` to nuget.org and only
  `HELIOS.*` to the private GitHub source (credential via `%GITHUB_TOKEN%` env
  indirection), so `dotnet restore HELIOS.sln` works without any token (comment in
  `.github/workflows/dotnet-build.yml`).

## Not in the repo (candidates)

| Package | Repo does instead | Adopt when |
|---|---|---|
| `Polly` | Hand-rolled `Resilience/CircuitBreaker.cs` + `Resilience/FallbackChain.cs` (tested, `TimeProvider`-injected, single-probe half-open semantics) | You need retry-with-jitter, hedging, or rate-limiter policies — don't reimplement those by hand; migrate the breaker too rather than mixing systems |
| `System.CommandLine` | Hand-parsed args in `HELIOS.AIHub.Cli` | The verb surface outgrows simple parsing (nested subcommands, completions, `--help` generation) |
| `OpenTelemetry` / `Serilog` | `Microsoft.Extensions.Logging` console only; MCP logs to stderr | Hosted deployment needs traces/metrics export. Constraint: the MCP server's stdout is protocol-owned (`src/mcp/HELIOS.Mcp/Program.cs`) — any logging sink must stay off stdout |
| `Microsoft.Extensions.TimeProvider.Testing` | Hand-rolled `FakeClock : TimeProvider` in `tests/.../Resilience/CircuitBreakerTests.cs` | Tests need timer/`Task.Delay` virtualization, not just `GetUtcNow()` |
| Central Package Management (`Directory.Packages.props`) | Per-csproj `Version=` attributes | Coordinates with the open Copilot PR #95 — do not hand-introduce CPM while that PR is in flight; after it merges, update THIS file to cite the props file instead of csproj lines |
