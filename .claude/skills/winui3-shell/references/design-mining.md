Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.

# Design mining — WPF → WinUI 3 porting for the ChatGPT-era corpus

Scope: the translation knowledge for the `design-miner` agent's lane — how corpus
markup becomes shell code. *What* to mine and the provenance rule are owned by
`docs/architecture/GUI_UPGRADE_PLAN.md` §1 (source-of-truth map) — cross-referenced
here, never duplicated. Target conventions are `SKILL.md` and `xaml-authoring.md`;
motion/animation ports follow `interaction-and-motion.md` and
`docs/architecture/INTERACTIVE_SHELL_EXPERIENCE.md`; shader/particle material routes
to the native lane per `.claude/skills/cpp-performance/references/particle-systems.md`.

## First rule: the corpus never compiled — verify every attribute

The seeds span three dialects: WPF (`docs/ui-xenoblade`, `src/gui/MonadoBlade.GUI`,
`src/core/HELIOS.Platform/Phase10/BuilderUI`), WinUI-shaped mockups
(`docs/WinUI3-Design/Presentation`), and outright invented properties. Known invalid
constructs, verified against the files:

- `MonadoBlade.GUI/Styles/Typography.xaml:19` (and throughout) sets `LetterSpacing`
  on `TextBlock` — no such property in WPF or WinUI 3. WinUI's equivalent is
  `CharacterSpacing` (units: 1/1000 em).
- `docs/WinUI3-Design/Presentation/Pages/DashboardPage.xaml:27` uses
  `TextTransform="Uppercase"` — exists on neither platform; uppercase the string in
  the view model or drop the treatment.
- `docs/ui-xenoblade/Components/Buttons/GlowButton.xaml:7` and
  `Components/Panels/HolographicPanel.xaml:8` place
  `<ResourceDictionary.MergedDictionaries>` as direct `UserControl` content —
  invalid markup in both frameworks (the property element belongs to a
  `ResourceDictionary` that is never opened). And per "Merge order" below, the
  per-control re-merge pattern itself must not be ported.

Never assume a corpus attribute exists: check it against the real WinUI 3 API
(Microsoft Learn) before emitting it. Parse-level checks on Linux, honest PR note per
`GUI_UPGRADE_PLAN.md` §3.

## Namespace and control mapping

- The XAML default namespace URI is identical in WPF, UWP, and WinUI 3
  (`http://schemas.microsoft.com/winfx/2006/xaml/presentation` — see the live
  `src/gui/HELIOS.Shell/App.xaml`), so root elements mostly survive. Custom-namespace
  prefixes do not: WPF `xmlns:local="clr-namespace:X"`
  (`HolographicPanel.xaml:4`) → WinUI `xmlns:local="using:X"`.
- Code-behind: WPF `System.Windows.*` and UWP-era `Windows.UI.Xaml.*` both →
  `Microsoft.UI.Xaml.*` (likewise `Windows.UI.Composition` →
  `Microsoft.UI.Composition`). The shell's own files are the reference for correct
  usings (`src/gui/HELIOS.Shell/Helpers/ReadinessVisuals.cs:1-2`).
- Core panels/controls (Grid, StackPanel, Border, TextBlock, Button, ProgressBar)
  map 1:1. Missing in WinUI 3: `WrapPanel`/`DockPanel`/`UniformGrid`
  (`MonadoBlade.GUI/Views/ThemeSettings.xaml:50` uses `WrapPanel`) — re-layout with
  Grid/ItemsRepeater or take the CommunityToolkit panel, decided per port; `Label` →
  `TextBlock`. MonadoBlade's code-built `Window` subclasses
  (`MonadoBlade.GUI/Windows/*.cs`) re-author as pages inside the shell's
  NavigationView, never as new Windows (`Microsoft.UI.Xaml.Window` has no
  Width/Height; sizing goes through `AppWindow`).

## Triggers and styles (the biggest WPF delta)

- WinUI 3 `Style` has **no `Style.Triggers`** — property triggers do not exist. The
  corpus hover/pressed/disabled trigger styles
  (`MonadoBlade.GUI/Themes/XenobladeThemeSystem.xaml:114-125`,
  `Phase10/BuilderUI/Styles/XenbladTheme.xaml:49-56`) become `VisualStateManager`
  CommonStates. Prefer restyling the built-in control — WinUI templates already
  define CommonStates; override lightweight-styling resources first, retemplate only
  when the treatment demands it (`xaml-authoring.md`).
- `DynamicResource` (`MonadoBlade.GUI/Themes/DarkModeThemeResources.xaml:61-65`) does
  not exist in WinUI: use `{ThemeResource}` for anything theme-reactive,
  `{StaticResource}` otherwise (SKILL.md rule; this is also what makes theme packs
  switch live).
- Trigger-driven `Storyboard`s (the glow pulse in
  `docs/ui-xenoblade/Theme/Styles.xaml:53-79`) become storyboards inside a
  `VisualState`, driven by `VisualStateManager.GoToState` from pointer events on
  custom controls — or Composition animations per `interaction-and-motion.md`, which
  owns the motion-port depth.
- `DropShadowEffect` → Composition. WPF's `UIElement.Effect` has no WinUI
  counterpart. The corpus glow idiom is `DropShadowEffect` with `ShadowDepth=0`
  (`HolographicPanel.xaml:21-25`, `docs/ui-xenoblade/MainWindow.xaml:40`,
  `Typography.xaml:192`). Ports: `Compositor.CreateDropShadow()` on a `SpriteVisual`
  behind the element (via `ElementCompositionPreview`, namespace
  `Microsoft.UI.Xaml.Hosting`); `ThemeShadow` for plain elevation; Win2D blur for
  genuine glow surfaces. Shadow color comes from a token, resolved in code — never a
  literal.

## What does NOT port

- **WPF BitmapEffects** — legacy even in WPF (removed in .NET 4); nothing to carry.
- **WPF pixel shaders (`ShaderEffect` + compiled `.ps`)** — WinUI 3 XAML has no
  shader-effect element. Custom shader work becomes a Win2D custom effect (managed)
  or native-spoke work; the decision table is
  `cpp-performance/references/rendering-gpu.md`. Grep-verified: the corpus contains
  no `ShaderEffect`/`BitmapEffect` usage — the three recovered
  `docs/ui-xenoblade/Shaders/*.hlsl` files are standalone fragments, not XAML
  effects, and their honest inventory plus port path is `particle-systems.md` /
  `DYNAMIC_BACKGROUND_ENGINE.md` — not this lane's XAML work.
- **Per-control resource re-merging** (below) and **`RelativeSource AncestorType`
  bindings** (`ThemeSettings.xaml:39`) — WinUI's `RelativeSource` supports only
  `Self` and `TemplatedParent`; restructure with named elements, x:Bind to the page's
  view model, or element-to-element x:Bind.

## Resource-dictionary merge order in WinUI 3

The shell's pattern is fixed by `src/gui/HELIOS.Shell/App.xaml:7-13`:
`XamlControlsResources` merged FIRST, then `Themes/Tokens.xaml`, so app dictionaries
override control styles. Lookup runs element → page → `Application.Resources`; within
`MergedDictionaries` the last-merged dictionary wins (searched in reverse). Theme
variants live in `ThemeDictionaries` keyed `Default`/`Light`/`HighContrast` — WinUI's
"Default" is the dark dictionary (`Tokens.xaml:17-57`). Two corpus habits to reject:
per-control re-merging of the whole theme set (`GlowButton.xaml:7-12` merges four
dictionaries into one UserControl — duplicates them per instance and forks the theme;
tokens are app-level, merged once), and relative `../../Theme/*.xaml` Source paths —
WinUI uses `ms-appx:///` URIs (`App.xaml:12`).

## x:Bind conversion of Binding-heavy markup

Corpus dialects: `MonadoBlade.GUI/Views/ThemeSettings.xaml` is the `{Binding}`-heavy
seed (20 occurrences, DataContext-based, command binding through
`RelativeSource AncestorType`); the `docs/WinUI3-Design` pages instead use `x:Name`
plus code-behind assignment (`DashboardPage.xaml:28-29`). Both convert to `{x:Bind}`
per `SKILL.md`/`xaml-authoring.md` — the rules that bite during ports:

- `x:Bind` resolves against the page/control **class**, not `DataContext`: expose a
  `ViewModel` property on the page and bind `{x:Bind ViewModel.X}`.
- Default mode is `OneTime` — write `Mode=OneWay` explicitly for every live value, or
  the port silently freezes (the ui-designer reconciliation rule).
- `DataTemplate` needs `x:DataType`; converters usually become x:Bind function
  bindings — the live example is `ReadinessVisuals.BrushFor`
  (`src/gui/HELIOS.Shell/Helpers/ReadinessVisuals.cs`, consumed from
  `Views/AIHubPage.xaml`).
- `ElementName` bindings become direct element x:Bind (`{x:Bind Slider.Value,
  Mode=OneWay}`); `AncestorType` restructures as above.

## Corpus map — seed → shell target, translation work per seed

Authoritative what/where/value inventory: `GUI_UPGRADE_PLAN.md` §1's table. This view
adds only the porting-lane column; if §1's table changes, change this one with it.

| Seed (§1 map) | Shell target | Dominant translation work |
|---|---|---|
| `MonadoBlade.GUI/Themes/MonadoColorPalette.xaml` | `Themes/Tokens.xaml` + theme packs (§2 — `theme-designer` owns) | Values only: colors → semantic tokens; never port brush keys or the file |
| `MonadoBlade.GUI/Styles/Typography.xaml` | TextBlock styles on the Fluent ramp (P1) | `LetterSpacing` → `CharacterSpacing`; drop/re-express the line-192 `DropShadowEffect` via Composition |
| `docs/WinUI3-Design/.../DashboardPage.xaml` | AIHub/Fleet KPI cards (P3/P5) | Near-WinUI markup: literal colors → tokens, `TextTransform` removed, x:Name+code-behind → x:Bind |
| `docs/ui-xenoblade/Components/`, `CustomControls/` | P6 Composition treatments (GlowButton, ServiceCard, HolographicPanel, MonadoGlowBorder, AnimatedProgressRing) | Triggers → VSM, `DropShadowEffect` → Composition, fix invalid merged-dictionary markup, colors → tokens |
| `docs/ui-xenoblade/Shaders/*.hlsl` | Win2D custom effect vs native spoke (P6/BG4) | Not XAML work — route via `particle-systems.md` and `render-engineer` |
| `src/core/.../Phase10/BuilderUI/` | Wizard flow (P6, only if a real setup scenario needs it) | WPF Window + step engine (`BuilderUIHost.cs`) → shell page with Frame/VSM step states; Triggers → VSM |
| `MonadoBlade.GUI/Systems/{FpsCounter,MemoryProfiler,FrameTimeHistogram}.xaml` | Debug perf overlay (`gui-perf-profiler`'s P3 build task) | Layout intent only; counters re-authored managed-side |
| `MonadoBlade.GUI/Views/ThemeSettings.xaml` | Theme settings page (P6) | The x:Bind conversion exemplar: DataContext `{Binding}` → page-class x:Bind, `AncestorType` command → view-model command, `WrapPanel` → WinUI layout |
