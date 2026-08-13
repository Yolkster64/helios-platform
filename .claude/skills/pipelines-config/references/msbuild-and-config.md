# MSBuild & config files — the HELIOS-specific layer

*Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.*

Generic JSON/YAML/config-format knowledge lives in
`.claude/skills/automation-wiring/references/config-schemas.md`. This file covers the
csproj/MSBuild idioms and JSON-binding conventions specific to this repo.

## csproj baseline (all four AIHub-family projects)

Grounded in `src/ai/HELIOS.AIHub{,.Cli,.Api}/…csproj` and `src/mcp/HELIOS.Mcp/…csproj`:

| Property | Value | Note |
|---|---|---|
| `TargetFramework` | `net8.0` | Version policy in csharp-orchestrator SKILL.md |
| `LangVersion` | `latest` | Api project omits it (SDK.Web default suffices) |
| `Nullable`, `ImplicitUsings` | `enable` | Non-negotiable for new projects |
| `Description` | one sentence | Every project has one — keep it |
| `OutputType`/`AssemblyName` | Cli: `Exe`/`helios-ai`; Api: `helios-ai-api` | Api uses `Microsoft.NET.Sdk.Web`, not `OutputType` |
| `InvariantGlobalization` | `true` (Api only) | Trims ICU; fine because the API formats nothing locale-sensitive |

## The four load-bearing ItemGroup idioms (HELIOS.AIHub.csproj)

1. **`InternalsVisibleTo`** as an item:
   `<InternalsVisibleTo Include="HELIOS.AIHub.Tests" />` — no AssemblyInfo.cs needed.
2. **Source-linked seam files** instead of a ProjectReference on the broken core:
   `<Compile Include="../../core/.../IAgent.cs" Link="CoreSeams/IAgent.cs" />`. The
   linked files must stay dependency-free (System.* usings only — CLAUDE.md rule). Never
   convert this to a ProjectReference while the core has its ~323 errors.
3. **Conditional native payload**:
   `<None Include="../HELIOS.AIHub.Native/build/….so" Condition="Exists('…')"
   CopyToOutputDirectory="PreserveNewest" />` per platform artifact (.so/.dylib/.dll).
   Copies flow transitively to CLI/test output so `LibraryImport` resolves at runtime;
   absence is legal (managed fallbacks). CI makes absence loud instead
   (`dotnet-build.yml` asserts the .so reached test output).
4. **`AllowUnsafeBlocks`** only because `LibraryImport` source-generated marshalling
   requires it (SYSLIB1062) — the comment in the csproj scopes the justification; don't
   copy the flag to projects without interop.

## Root-csproj glob guard (repeat because it bites)

Root `HELIOS.Platform.csproj` recursively globs `**/*.cs`. Any new C# directory outside
`src/ai`/`src/mcp` must be added to its `<Compile Remove>` list **in the same commit**,
including Windows-only `src/gui/` projects that live in their own solution
(CLAUDE.md hard rules). New projects also get added to `HELIOS.sln`.

## nuget.config — source mapping as a security boundary

Root `nuget.config`: `packageSourceMapping` sends `*` to nuget.org and only `HELIOS.*` to
the private GitHub source; the GitHub credential is `%GITHUB_TOKEN%` env indirection
(never a literal). Two consequences: restore works keyless in CI, and dependency-confusion
attacks on public names can't route to the private feed. Keep new feeds mapped; never add
an unmapped source.

## JSON config binding conventions (Configuration/AIHubOptions.cs)

- Options classes bind with **System.Text.Json**, one `[JsonPropertyName]` per property,
  `sealed class`, initialized collection defaults (`= new()`).
- Deserializer options: `PropertyNameCaseInsensitive`, `ReadCommentHandling.Skip`,
  `AllowTrailingCommas` — so `config/aihub.json` may carry `$comment` keys and human
  formatting.
- Config discovery is **walk-up**: `FindConfigFile` climbs parent directories from CWD
  and from `AppContext.BaseDirectory`, which is why published artifacts ship a `config/`
  folder next to the executable (`dotnet-build.yml` publish step).
- Contract: new config file ⇒ options class ⇒ binding test against the real shipped file
  in the same PR (`tests/.../Configuration/ConfigBindingTests.cs` is the exemplar; it is
  what turns config drift into a CI failure).
- Secrets never appear in config — only env-var names / Key Vault secret names
  (`apiKeyEnv`, `apiKeySecretName` in `ProviderOptions`).

## Not in the repo (candidates)

| Mechanism | Status / adopt when |
|---|---|
| `Directory.Packages.props` (CPM) | **Coordinates with open Copilot PR #95** — review that PR rather than hand-adding; central pins affect every csproj including the root WPF project and `src/gui/`, which restore via MSBuild props inheritance even though they're outside `HELIOS.sln` |
| `Directory.Build.props` | Same PR #95 blast radius; adopt to dedupe the baseline table above only after #95 settles |
| `packages.lock.json` | Adopt with CPM, then key the NuGet cache on lockfiles (see `references/actions-tooling.md`) |
| `UseArtifactsOutput` (central `artifacts/` output) | Nice-to-have; touches every path assumption in workflows (`bin/Release/net8.0` is asserted literally in `dotnet-build.yml`) — bundle with the net10 upgrade, not before |
| `.editorconfig` `[*.cs]` analyzers section | Tracked as PR2 work in `docs/architecture/ROADMAP_MULTI_LLM.md` |
