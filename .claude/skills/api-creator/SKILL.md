---
name: api-creator
description: End-to-end recipe for adding a new capability to the HELIOS hub — a new LLM provider, a new CLI command, or a new MCP tool — with all the places that must change together. Use when extending the AIHub surface.
---

# API Creator — Extending the HELIOS Hub

Three extension points, one checklist each. Everything ships in a single PR with tests.

## Add a new LLM provider

1. **Config**: add the entry to `config/aihub.json` under `providers` (type, model,
   `apiKeyEnv`/`endpointEnv`, optional `apiKeySecretName`) — env-name indirection only.
2. **Factory**: add a case to `ProviderFactory.Create` (src/ai/HELIOS.AIHub/Providers/).
   - OpenAI-compatible endpoint → reuse `ChatClientAgent` with an `OpenAIClient` +
     custom `Endpoint` (see `github-models`).
   - Native SDK → subclass `ProviderAgentBase`, implement `ChatCoreAsync` only (see
     `AnthropicAgent`); the base handles metrics, status, Unconfigured short-circuit,
     and exception→failed-result conversion.
   - External CLI → just add a `cliAgents` config entry; `CliProcessAgent` is generic.
3. **Unconfigured is a state, not an error**: missing key ⇒ construct with `null`
   factory + a hint naming the exact env var. Never throw at startup.
4. **Routing**: add the provider to relevant `taskRouting` chains.
5. **Tests**: extend `ConfigBindingTests` expected-provider list and
   `AIHubServiceTests.ShippedConfig_BuildsHub_WithAllProvidersRegistered` count; add a
   provider-specific test with a fake if it has mapping logic.
6. **Docs**: row in `docs/architecture/MULTI_LLM_INTEGRATION.md` provider matrix +
   `.env.template` entry.

## Add a new CLI command

1. Case in the `switch` in `src/ai/HELIOS.AIHub.Cli/Program.cs` + help text.
2. Logic belongs in `AIHubService` (facade), not in the command handler.
3. Deterministic keyless behavior: commands must not fail merely because no API keys are
   set (CI runs `status` and `routing` as smoke tests in `dotnet-build.yml`).

## Add a new MCP tool

1. Method on `HeliosAiTools` (src/mcp/HELIOS.Mcp/): `[McpServerTool(Name = "helios_<verb>_<noun>",
   ReadOnly = <true if no side effects>, Idempotent = …, OpenWorld = <true if it calls LLMs>)]`
   plus `[Description]` on the method and every parameter (agents choose tools by these).
2. Take `AIHubService hub` as the first parameter (DI-injected); return JSON via
   `JsonSerializer` — structured, parseable, no prose.
3. Errors: throw `McpException` with an actionable message ("Set X", "Run Y first").
4. Destructive operations (deploy, delete) are **not** added without explicit review —
   v1 is deliberately non-destructive; extend `docs/mcp/CLIENT_SETUP.md` tool list +
   add an eval question to `docs/mcp/EVALUATION.md`.

## Which LLM

Design the contract with `architecture_design` (Claude), generate the adapter with
`code_generation` (Codex/GPT), review with `code_review` (Claude), and verify SDK usage
against real docs — never trust remembered signatures for provider SDKs.
