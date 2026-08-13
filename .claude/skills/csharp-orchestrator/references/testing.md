# Testing — repo idioms for HELIOS.AIHub.Tests

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Framework: xunit 2.9.3 (`tests/HELIOS.AIHub.Tests/HELIOS.AIHub.Tests.csproj`). CI runs
`dotnet test tests/HELIOS.AIHub.Tests -c Release` (`.github/workflows/dotnet-build.yml`).

## Layout

| Directory / file | Covers |
|---|---|
| `Fakes.cs` | Shared hand-rolled doubles: `FakeProviderAgent`, `FakeChatClient` |
| `Providers/` | `ChatClientAgent`, `CliProcessAgent` behavior against fakes |
| `Resilience/` | `CircuitBreaker`, `FallbackChain` with a fake `TimeProvider` |
| `Configuration/` | Shipped-config drift (`ConfigBindingTests`), cloud config, path resolution |
| `Routing/`, `Learning/` | Task routing strategy; learning stores + F# interop |
| `ApiEndpointTests.cs` | Full HTTP surface via `WebApplicationFactory<Program>` |
| `McpEngineToolTests.cs`, `McpStatusToolsTests.cs`, `McpFoundryToolTests.cs` | MCP tool methods called directly |

## Idiom 1 — hand-rolled fakes at provider seams, not Moq

Moq 4.20.72 is referenced in the csproj but has **zero usages**; every double is a small
scriptable class in `Fakes.cs`:

- `FakeProviderAgent : ProviderAgentBase` — constructor takes readiness + a
  `Func<ChatRequest, ChatResult>` handler; used for router/facade tests.
- `FakeChatClient : IChatClient` — handler function plus a recorded `Calls` list for
  asserting what messages/options the agent actually sent.

Follow this: provider seams are already interfaces designed for substitution, and a
recorded-calls fake reads clearer than `Verify()` chains. Do not add new Moq usages at
these seams; if Moq stays unused, removing the reference is a legitimate cleanup.

## Idiom 2 — keyless determinism

Tests must pass with **no API keys and no network**. `ApiEndpointTests` boots the real app
against the shipped `config/aihub.json`, "where every provider is Unconfigured — so these
run keyless and offline, like CI" (file doc comment). Corollaries:

- Never write a test that requires a real provider call; script a fake instead.
- Assert on readiness/hint behavior (`ProviderReadiness.Unconfigured` + hint), which is
  exactly what CI exercises.
- Opt-in escalation goes through env vars, e.g. `HELIOS_REQUIRE_PYTHON_SPOKE=1` (set in
  `dotnet-build.yml`) makes spoke tests hard-fail in CI while staying soft locally; the
  API key header is only attached when `HELIOS_API_ACCESS_KEY` is present.

## Idiom 3 — shipped-config drift tests

`Configuration/ConfigBindingTests.cs` loads the **real** `config/aihub.json` (via
`AIHubOptions.FindConfigFile` walking up from the test output directory) and asserts:
expected provider/CLI-agent names exist, no secret-looking values, every routing chain
references a known provider, core task types are covered. Consequences:

- Adding/removing a provider in `config/aihub.json` **requires updating these tests in
  the same commit** (and any provider-count assertion in `AIHubServiceTests.cs`).
- New config file ⇒ new options class ⇒ new binding test in the same PR
  (rule stated in the pipelines-config skill).

## Idiom 4 — inject TimeProvider, fake it locally

`CircuitBreaker` takes a `TimeProvider` (defaulting to `TimeProvider.System`);
`Resilience/CircuitBreakerTests.cs` defines a 6-line `FakeClock : TimeProvider` with a
settable `Now` and advances it to cross cooldown boundaries. No `Thread.Sleep`, no real
clocks in tests — new time-dependent code must take `TimeProvider` the same way.

## Idiom 5 — API tests over HTTP, MCP tests in-process

- API: `IClassFixture<WebApplicationFactory<Program>>` + `CreateClient()`, asserting
  status codes and deserialized JSON (`JsonSerializerDefaults.Web`) — the middleware
  (loopback gate, api-key header) is part of what's under test.
- MCP tools are static methods, so the MCP tests (`McpStatusToolsTests.cs`,
  `McpEngineToolTests.cs`) invoke the tool logic directly — no stdio transport. The
  status-tool tests fabricate a throwaway repo root (a `config/aihub.json` marker is all
  root resolution needs) and point the tools' core methods at it (file doc comment).

## CI-side test rules (dotnet-build.yml)

- The native library is built **before** `dotnet build`, and a step asserts it reached
  `tests/HELIOS.AIHub.Tests/bin/Release/net8.0/` — graceful runtime degradation is right
  for dev machines but would let CI silently stop testing native paths.
- Tests log a TRX (`--logger "trx;LogFileName=aihub-tests.trx"`) uploaded as an artifact.
- `InternalsVisibleTo("HELIOS.AIHub.Tests")` in `HELIOS.AIHub.csproj` — prefer testing
  public surface; internals access exists for seams, not as the default.

## Not in the repo (candidates)

| Tool | Adopt when |
|---|---|
| `Microsoft.Extensions.TimeProvider.Testing` (`FakeTimeProvider`) | A test needs timers/`Delay` virtualization, not just `GetUtcNow()` — the hand-rolled `FakeClock` can't do that |
| `FluentAssertions` / `Shouldly` | Only by team decision across the whole suite; mixed assertion styles cost more than they save |
| Snapshot testing (`Verify`) | Large JSON payload assertions (e.g. engine catalog) start drifting from hand-written `Assert.Contains` chains |
| Coverage gates | `coverlet.collector` already produces data; gate in CI only after a baseline is agreed (roadmap scorecard work, Copilot PR #97) |
