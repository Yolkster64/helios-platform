# .NET 10 (LTS) and .NET 11 (preview) — upgrade knowledge

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Release facts verified against the official releases index
(`builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json`) and
Microsoft Learn, 2026-08-13.

## Release reality (decision basis)

| Channel | Latest | Type | Phase | Meaning for HELIOS |
|---|---|---|---|---|
| 11.0 | 11.0.0-preview.7 | STS | preview (GA ~Nov 2026) | Validation lane only until GA |
| 10.0 | 10.0.11 | **LTS** | active (3-year support) | **The platform target** |
| 9.0 | 9.0.19 | STS | maintenance | Skip |
| 8.0 | 8.0.30 | LTS | maintenance (**EOL Nov 2026**) | Migrate off before EOL |

Policy: production TFM is `net10.0` (GA LTS). A `net11.0` build lane runs
allowed-to-fail against the preview SDK; when 11 GAs, the flip is a TFM bump reviewed
against the GA release notes. Never gate required CI on a preview SDK.

## C# 14 (default with the .NET 10 SDK) — what to actually use here

- **Extension members** (`extension` blocks: static extension methods, extension
  properties): reads well for provider-shaping helpers, but keep public seams
  (`IAgent`, `IRouter` source-linked files) plain — they must stay dependency-free
  and comprehensible from System.* alone.
- **`field`-backed properties**: replaces private-backing-field boilerplate in view
  models and options classes; adopt opportunistically when touching a file, not as a
  sweep.
- **Null-conditional assignment** (`a?.B = c`) and **unbound generic `nameof`**
  (`nameof(List<>)`): small wins; fine anywhere.
- **First-class span conversions**: relevant to the native interop boundary
  (`NativeMethods.cs`) and any hot parsing paths — arrays now convert implicitly to
  `Span<T>`/`ReadOnlySpan<T>` in more places, composing with generic inference.
- **Lambda parameter modifiers without types** (`(text, out result) => …`): handy for
  `TryParse`-shaped delegates in config binding.
- Partial constructors/events and user-defined compound assignment exist; no current
  HELIOS use case — do not invent one.

## .NET 10 runtime/library changes that matter to this repo

- **JIT de-abstraction** (array interface devirtualization, enumerator stack
  allocation, closure stack allocation): LINQ-over-array hot paths in routing/scoring
  get cheaper for free — do not "pre-optimize" code into manual loops to help .NET 8
  anymore.
- **System.Text.Json**: new strict options — duplicate-property rejection and a
  strict-serialization preset. Candidate for `config/aihub.json` binding
  (`AIHubOptions.Load`) to catch config typos at load; adopt deliberately with a
  test, since it tightens previously-lenient parsing.
- **`WebSocketStream`**: simplifies any future streaming provider transport; noted,
  unused today.
- **Post-quantum crypto (ML-DSA etc.)**: not HELIOS surface; leave to the platform.
- **F# 10** (`HELIOS.AIHub.Domain.fsproj`): language features that needed
  `<LangVersion>preview</LangVersion>` pre-GA are default in the GA SDK. FSharp.Core
  central pin must move with the retarget (the CPM pin exists because implicit
  FSharp.Core does not flow transitively under Central Package Management — see
  `Directory.Packages.props`).

## .NET 11 preview — what the validation lane watches

- **Runtime Async is on for `net11.0` targets** (no `EnablePreviewFeatures` needed):
  async methods get runtime-native continuations — cleaner stack traces, lower
  overhead. The AIHub is async end-to-end (provider fan-out, tandem/compare), so this
  is the single most relevant .NET 11 change; watch for behavior differences in
  `ExecutionContext` capture (continuations may skip capture when no ambient state
  exists).
- **Raised minimum hardware requirements** (newer x64/Arm64 instruction sets): check
  fleet VMSS SKUs and any old self-hosted runners before the GA flip.
- **C# 15 preview** (union types, closed hierarchies, collection-expression
  arguments, labeled break/continue): do not use preview language features in
  committed code; the F#-style union modeling temptation is real — revisit at GA.
- NativeAOT interface-dispatch and SIMD lane APIs (`Vector128/256/512` zip/unzip/
  concat): relevant only if the native cosine kernel ever moves managed.

## Upgrade mechanics for THIS repo (the checklist the retarget must satisfy)

1. TFMs `net8.0` → `net10.0` in every csproj/fsproj `HELIOS.sln` builds, plus the
   excluded projects (root WPF, `src/core`) so nothing forks; `src/gui` moves
   `net8.0-windows…` → `net10.0-windows…` only after verifying the pinned
   Windows App SDK supports it (Windows-only build — parse-level here).
2. `Directory.Packages.props`: `Microsoft.Extensions.*` 8.x → 10.x,
   `Microsoft.AspNetCore.Mvc.Testing` to 10.x (the TFM-match rule in
   `references/nuget-packages.md`), FSharp.Core to the .NET-10 line. Azure/OpenAI/
   Anthropic SDKs are TFM-agnostic (netstandard2.0/net8.0 assets run on net10) — bump
   only for real fixes, not reflexively.
3. Workflows: every `actions/setup-dotnet` `dotnet-version: 8.0.x` → `10.0.x`;
   Dockerfiles: `sdk:8.0`/`aspnet:8.0` → `10.0` images (restore layers keep copying
   the central props files). Add the allowed-to-fail `net11-preview` job
   (`dotnet-version: 11.0.x`, `dotnet-quality: preview`, `continue-on-error: true`).
4. Docs stating ".NET 8": `CLAUDE.md`, `AGENTS.md`, `README`, this skill's SKILL.md
   version-policy line.
5. Full gate on net10: build 0 errors, all tests, pytest, bicep — plus one manual
   `helios-ai status` smoke to catch runtime-only breaks.
