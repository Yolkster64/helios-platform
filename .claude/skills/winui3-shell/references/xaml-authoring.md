Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.

# XAML authoring (WinUI 3 / HELIOS.Shell)

Applies to `src/gui/HELIOS.Shell/` (Windows App SDK 1.6, `net8.0-windows10.0.19041.0`, min platform 10.0.17763 — `src/gui/HELIOS.Shell/HELIOS.Shell.csproj`). Platform behavior below is verified against Microsoft Learn's WinUI 3 / Windows App SDK pages; repo conventions cite the file that sets them.

## x:Bind vs Binding

`{x:Bind}` compiles to code at XAML build time (generated partial class in `obj/`, e.g. `<view>.g.cs`): type-checked, no reflection, breakpoint-debuggable. `{Binding}` uses runtime object inspection. Default to x:Bind — the shell already does (`Views/AIHubPage.xaml`).

| Aspect | {x:Bind} | {Binding} |
|---|---|---|
| Resolution | compile time, generated code | runtime reflection |
| Default Mode | **OneTime** | OneWay |
| Path root | the Page/Window class (named elements, properties, statics, functions) | DataContext |
| DataTemplate | requires `x:DataType` | untyped |
| UpdateSourceTrigger | PropertyChanged, except TextBox.Text = LostFocus; no `Explicit` | Default / LostFocus / PropertyChanged |

Traps (all from the Learn x:Bind / data-binding-in-depth pages):

- **OneTime is the default.** A binding that "never updates" is almost always a missing `Mode=OneWay`; OneTime was chosen because OneWay generates change-detection hookup code. `x:DefaultBindMode` on an element flips the default for that subtree.
- **FallbackValue** shows when the *path* cannot resolve (a non-leaf segment is null); **TargetNullValue** shows when the leaf resolves to an explicit `null`. Confusing them hides real binding bugs behind placeholder text.
- x:Bind needs compile-time types, so it **cannot target `DataContext`** (typed `Object`, mutable at runtime). Expose a get-only typed `ViewModel` property on the page instead (`Views/AIHubPage.xaml.cs`).
- x:Bind inside a standalone ResourceDictionary requires that dictionary to have a code-behind class.
- Function bindings (`{x:Bind helpers:ReadinessVisuals.BrushFor(Readiness)}`) resolve at bind time and do not re-resolve on theme change — `Helpers/ReadinessVisuals.cs` documents the accepted staleness window.
- Booleans bind directly to `Visibility` (built-in bool→Visibility converter, min target SDK 14393 — satisfied by the csproj's 17763 floor). Property binding only, not function binding.

Use `{Binding}` only where x:Bind cannot go (dynamic-DataContext scenarios) and say why in the PR (`.claude/skills/winui3-shell/SKILL.md`).

## DataTemplates and list controls

Every DataTemplate used with x:Bind declares `x:DataType` — without it the bindings cannot compile. The shell's pattern: immutable row records rebuilt on refresh, so the template's default OneTime mode is correct (`ViewModels/ProviderItemViewModel.cs`, `Views/AIHubPage.xaml`).

| Control | Choose when | Notes (Learn) |
|---|---|---|
| ListView / GridView | out-of-box list/grid UX | Built-in UI virtualization, selection, keyboarding. Virtualization is defeated inside panels granting unbounded space (ScrollViewer, auto-sized Grid cell) — keep the control's extent bounded |
| ItemsRepeater | custom collection UI | Data-driven panel: no default UI, no selection/focus/interaction policy, no built-in scrolling — wrap in a ScrollViewer. Virtualizes when its host supports it. Prefer over ItemsControl |
| ItemsView | list/grid with switchable layout | Built from ItemsRepeater + ScrollView + ItemContainer; preserves selection across layout switches |

Heterogeneous rows: `ChoosingItemContainer` outperforms a `DataTemplateSelector` on ListView (container recycling stays effective); `x:Phase` renders template parts progressively during fast panning.

## Resource dictionaries and ThemeResource lifetime

`{ThemeResource}` re-evaluates on every runtime theme change; `{StaticResource}` resolves once at XAML load and freezes the launch theme. All shell brushes are semantic tokens in `Themes/Tokens.xaml` referenced only via ThemeResource; no XAML outside Tokens.xaml names a literal color (`docs/architecture/GUI_THEME_ANALYSIS.md`).

Rules that bite (Learn ThemeResource / xaml-theme-resources pages):

- Theme dictionaries key on `Default` (WinUI's dark — see Tokens.xaml comment), `Light`, `HighContrast`. Every key must exist in **all three**, or lookup can fail when the user switches themes. Tokens.xaml keeps this invariant; keep it when adding tokens.
- An unresolvable ThemeResource key is a XAML parse exception at **runtime**, not a build error.
- No forward references — define a resource lexically before its first reference.
- Inside a theme dictionary, reference sub-values with StaticResource, not ThemeResource: ThemeResource-inside-theme-dictionaries pollutes dictionaries during theme-change walks. Exception: HighContrast entries reference `SystemColor*` colors via ThemeResource so user contrast settings win — Tokens.xaml does exactly this.
- Merged-dictionary order matters: `XamlControlsResources` first so app dictionaries can override (`App.xaml`).

## VisualStateManager

`VisualState` holds `Setter`s applied while the state is active; states live in `VisualStateManager.VisualStateGroups`, which must be attached to the **first child of the root element** for triggers to fire automatically. `AdaptiveTrigger` (`MinWindowWidth`/`MinWindowHeight`) declares breakpoints — a state applies from its threshold up to the next state's; the wide state usually has no setters and represents the XAML as written. Drive states from code with `VisualStateManager.GoToState(control, name, useTransitions)` (e.g. from `SizeChanged`). Setters targeting attached properties parenthesize the name: `Target="myBox.(RelativePanel.AlignHorizontalCenterWithPanel)"`. Prefer setters that reposition/reflow existing elements over duplicated element trees.

## Hot Reload limits (WinUI 3)

There is no XAML visual designer for WinUI 3 projects; Hot Reload under the debugger is the iteration loop (Learn: xaml-runtime-design-tools). It requires F5 — Ctrl+F5 disables Hot Reload, Live Visual Tree, and Live Property Explorer.

| Applies live | Needs restart |
|---|---|
| Add / remove / reorder elements | New classes or code-behind event handlers; `x:Class` changes |
| Property value edits (colors, margins, text, sizes) | Wiring events to controls while running |
| Style and resource-dictionary edits | `App.xaml` merged-dictionary changes (sometimes) |
| Data-template content | x:Bind expressions referencing new properties; styles in `themes/generic.xaml` |

## Generating XAML with LLM agents

The hub routes `code_generation` through codex first (`config/aihub.json` taskRouting: `codex → openai → azure-openai → anthropic`; `docs/architecture/LLM_STRENGTHS_PLAYBOOK.md`). Per the SKILL.md routing table: layout/MVVM structure decisions go to anthropic or openai; mechanical markup generation to codex. A UI agent requesting XAML from the hub must pin the conventions the generator will otherwise violate:

- **x:Bind-first.** No `{Binding}` unless the request states the dynamic-DataContext justification; require explicit `Mode=OneWay` on live values (OneTime default trap above).
- **Theme-aware brushes only.** Reference Tokens.xaml semantic brushes via `{ThemeResource}`; reject output containing literal colors or hardcoded brushes outside Tokens.xaml.
- **Typed templates.** Every DataTemplate carries `x:DataType`; pages expose a get-only `ViewModel` root.
- **Always compile-check on Windows.** Linux CI never builds the shell — no CI check compiles GUI changes today (`src/gui/README.md`) — so generated XAML is unverified until `dotnet build src/gui/HELIOS.Shell.sln -p:Platform=x64` passes on Windows. Treat generated-but-unbuilt XAML as a draft, never a deliverable.

## Not in the repo (candidates)

- **XamlStyler** (Xavalon/XamlStyler) — not configured in this repo. Its default attribute ordering (XamlStyler wiki): `x:Class`; `xmlns`/`xmlns:x`; other `xmlns:*`; `x:Key`/`x:Name`/`x:Uid`/`Title`; attached layout (`Grid.Row`…, `Canvas.*`); `Width`/`Height`/Min/Max; `Margin`/`Padding`/alignments/`Panel.ZIndex`; everything else (wildcard groups); `mc:Ignorable` and designer attributes; `Storyboard.*`/`From`/`To`/`Duration` last — with optional alphabetical fallback for unmatched attributes and "first line attributes" pinning. Adopting it would make agent-generated XAML diffs deterministic; wire it as a Windows-side pre-commit or CI step, never into the Linux `HELIOS.sln` build.
- **WinUI 3 Gallery** (github.com/microsoft/WinUI-Gallery `main` branch; Store id 9P3JFPWWDZRC) — the canonical interactive reference for control usage; Microsoft's own control docs link to it per control. Check the Gallery page for a control before inventing markup for it.
