---
name: csharp-orchestrator
description: C# conventions for the HELIOS orchestrator core, AIHub, CLI, and MCP server — API design, DI/hosting, async, interop boundaries, and .NET version policy. Use when writing or reviewing any C# in this repo.
---

# C# — HELIOS Orchestrator Core

**Hub-and-spoke rule**: C# is the center. All I/O, credentials, external services, and
cross-language coordination live here. C++/F#/Python spokes are invoked *by* C# (P/Invoke
or C++/WinRT, in-proc assembly, subprocess/gRPC respectively) and never talk to each other.

## Project layout

- New code goes under `src/<area>/<Project>/` and must be added to `HELIOS.sln`.
- The root `HELIOS.Platform.csproj` recursively globs `**/*.cs` — add any new C#
  directory to its `<Compile Remove>` list in the same commit.
- `src/core/HELIOS.Platform` does not build (323 pre-existing errors). Do not reference
  it; source-link individual dependency-free contract files instead (see
  `src/ai/HELIOS.AIHub/HELIOS.AIHub.csproj` linking `IAgent.cs`/`IRouter.cs`).

## API design

- Contracts as `sealed record` types; behavior behind interfaces (`IChatProviderAgent`).
- Never throw for expected absence: return status types (`ProviderReadiness.Unconfigured`
  with a hint) instead of exceptions at startup. Exceptions are for bugs and transport
  failures, and get converted to failed results at provider boundaries.
- Public async APIs: `Task`-returning, `CancellationToken` last with a default,
  `ConfigureAwait(false)` in library code, no `async void`.
- Options/config: bind JSON to a `*Options` class with `System.Text.Json`; env-var
  indirection for secrets (name in config, value from environment/Key Vault).

## Concurrency

- Guard mutable state with a private `object _gate` + `lock`, or use
  `ConcurrentDictionary` for registries. `SemaphoreSlim(1,1)` for async-safe lazy init.
- Parallel LLM fan-out: build the `Task` list, then `Task.WhenAll` — never `await` in a
  loop for independent calls (see `AIHubService.CompareAsync`).
- Timeouts: `CancellationTokenSource.CreateLinkedTokenSource(ct)` + `CancelAfter`;
  distinguish caller cancellation from timeout with a `when` filter.

## Which LLM for which C# work

| Work | Route (`helios-ai route <task>`) |
|---|---|
| Architecture / API shape decisions | `architecture_design` → Claude |
| Reviewing a diff or PR | `code_review` → Claude |
| Generating a new provider/adapter from a spec | `code_generation` → Codex/GPT |
| Test scaffolding | `test_creation` → Codex/GPT |
| Inline completions while typing | `inline_completion` → Copilot |
| Analyzing a huge log/codebase slice | `long_context_analysis` → Claude |

## .NET version policy

Repo targets **net8.0** (EOL 2026-11-10). Current LTS is **.NET 10**; **.NET 11 is
preview only** (ships Nov 2026) — never claim .NET 11 GA or target it in committed code.
The net10.0 upgrade is a scheduled roadmap PR; keep new code free of net8-only
assumptions (prefer `TimeProvider` over `DateTime.UtcNow` for testability, `LibraryImport`
over `DllImport`).

## Reference material

Depth lives in `references/` — every claim there cites the repo file that grounds it:

- `references/nuget-packages.md` — per-csproj package inventory with exact pins, upgrade
  pitfalls (the Azure.AI.OpenAI 2.x rewrite trap, Mvc.Testing TFM matching), and the
  deliberately-absent list (Polly, System.CommandLine, OTel) with adoption criteria.
- `references/provider-sdks.md` — working API knowledge per SDK behind
  `src/ai/HELIOS.AIHub/Providers/`: the `IChatClient` seam, Azure deployment-vs-model and
  credential-chain traps, Anthropic/Ollama/Foundry-Agents/KeyVault/Tables/MCP surfaces.
- `references/testing.md` — test idioms: hand-rolled fakes over Moq,
  `WebApplicationFactory`, shipped-config drift tests, keyless determinism, TimeProvider
  injection.
