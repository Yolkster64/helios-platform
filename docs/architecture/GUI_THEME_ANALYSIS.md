# GUI & Theme Analysis — WinUI 3 Direction

Deep analysis of every GUI asset across the HELIOS repos, and the consolidation
recommendation. Design-only in this PR; implementation is roadmap PR6.

## Inventory (what actually exists)

| Asset | State | Verdict |
|---|---|---|
| `src/gui/MonadoBlade.GUI/` (~60 files, WPF, Xenoblade-themed) | **Orphaned** — no `.csproj` includes it; `AIHubWindow.cs` has a hardcoded 10-provider list with empty `SelectOptimalProvider`/`MonitorProviderHealth` stubs | Mine for design intent, not code |
| `docs/ui-xenoblade/HELIOS.WPF.csproj` | Builds `net10.0-windows` (retargeted with the platform), `Nullable=disable`, lives under `docs/` with a stray git object store | Do not adopt; quarantine in PR2 cleanup |
| `docs/WinUI3-Design/Presentation/Pages/AIHubPage.xaml` | Design mockup of the AIHub dashboard | Direct input to the WinUI 3 page |
| monado-blade `src/Tracks/D_UI_UX_Automation/` | Empty csproj — the "GUI repo" has no GUI | Confirms helios-platform is where the shell gets built |
| Root `HELIOS.Platform.csproj` (`net10.0-windows`, `UseWPF`) | Compiles a recursive glob of the repo; not a real app | Retire as part of the core repair (PR2/PR6) |

## Recommendation: WinUI 3 shell, one project, three pages

**Framework**: WinUI 3 (Windows App SDK) over WPF — aligns with the user's declared
"C# WinUI3 center", gets Fluent theming (Light/Dark/HighContrast) natively, first-class
`AppWindow` management, and the C++ interop path (C++/WinRT + Win2D) that the
cpp-performance spoke needs for heavy rendering. WPF assets are treated as wireframes.

**Project**: `src/gui/HELIOS.Shell/` (net8.0-windows + Windows App SDK; the platform is
on net10.0 — the shell follows once the pinned Windows App SDK line documents net10
support. Do not wait for .NET 11, which is preview only). MVVM via
CommunityToolkit.Mvvm; **no logic in the shell** — every view model binds to
`HELIOS.AIHub` public APIs (`GetStatus()`, `GetMetrics()`, `RoutingTable`, `CompareAsync`).

**Pages** (v1):

1. **AI Hub dashboard** — the `AIHubWindow` revival: provider table (readiness, model,
   latency, success rate, tokens from `AgentMetrics`), circuit-breaker state badges,
   per-provider enable toggles writing `config/aihub.json`.
2. **Routing** — the task-routing table as an editable grid (chains reorder by drag),
   backed by the same JSON + `ConfigBindingTests` contract.
3. **Fleet** — Xcore-9s pool state via the Hermes kanban DB (read-only v1), lane counts,
   task throughput.

## Theme system

Design tokens as WinUI resource dictionaries, honoring the Xenoblade-derived identity
from the WPF assets without hardcoding colors:

- `Themes/Tokens.xaml` — semantic brushes (`HeliosAccentBrush`, `ProviderReadyBrush`,
  `ProviderDegradedBrush`, `SurfaceBrush`…) defined per theme dictionary
  (Default/Light/HighContrast), referenced only via `{ThemeResource}`.
- The Xenoblade look (deep blues, cyan accent, hex-grid motifs from `MonadoBlade.GUI`)
  becomes the *Default (dark)* dictionary's token values — swappable, testable, and
  HighContrast-safe because no XAML names a literal color.
- Type ramp + spacing follow Fluent defaults; custom chrome only on the dashboard header.

## Interop boundary (per hub-and-spoke)

Charts/visualizations that outgrow XAML: Win2D `CanvasControl` first; if profiling shows
CPU-bound scene prep, a C++/WinRT component renders to a `SwapChainPanel` — the C++ spoke
rule applies (flat ABI, no spoke-to-spoke calls). No web views for core surfaces.

## Migration path

PR6: scaffold `HELIOS.Shell` + dashboard page bound to live `AIHubService` →
port routing page → quarantine `src/gui/MonadoBlade.GUI` + `docs/ui-xenoblade` into
`legacy/` → retire the root WPF csproj once the tray/shell-extension projects get real
homes. Review gate: the `winui3-reviewer` agent (.claude/agents/) on every shell PR.
