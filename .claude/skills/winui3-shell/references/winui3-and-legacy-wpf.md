# WinUI 3 as shipped — XAML depth — and WPF for reading and migration only

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Companions: `xaml-authoring.md` (the platform rules for x:Bind,
templates, ThemeResource lifetime, VSM, Hot Reload — verified against Microsoft Learn),
`rendering-interop.md` (Win2D / SwapChainPanel / Composition), `interaction-and-motion.md`
(motion and the seed porting notes), `design-mining.md` (the WPF → WinUI translation
tables — not repeated here). Binding decision: `docs/architecture/ADR-0010-WINUI3-ONLY.md`.

**The rule first.** WinUI 3 is the only active desktop framework. Everything in Part 3
exists so an agent can *read* the legacy corpus and carry its intent into
`src/gui/HELIOS.Shell`; none of it is a license to write, extend, compile, or bridge
WPF. New desktop code uses C#/.NET 10, the Windows App SDK, `Microsoft.UI.Xaml`, and
`Microsoft.UI.Composition` (ADR-0010 "Decision"). Every pattern below names one
exemplar under `src/gui/HELIOS.Shell/` (read-only in this lane) as `path:line`.

## Part 1 — the shell as it ships (C# side)

### Pattern 1 — project shape

`HELIOS.Shell.csproj`: `net8.0-windows10.0.19041.0` (`:17`), `UseWinUI` (`:25`),
unpackaged `WindowsPackageType=None` (`:26`), framework-dependent against an installed
Windows App SDK 1.6 runtime (`:10-13`), no explicit `<Page>` items because the SDK globs
`*.xaml` (`:40-44`). Deliberately **not** in `HELIOS.sln`; builds through
`src/gui/HELIOS.Shell.sln` on Windows only (`:6-9`; `src/gui/README.md` "Build"). Pins:
`Microsoft.WindowsAppSDK` 1.6.250205002, `CommunityToolkit.Mvvm` 8.3.2
(`Directory.Packages.props:18,35`). No Win2D package is referenced today (`:33-38`).

Honest tension to resolve in the packaging PR, not silently: ADR-0010 lists
"single-project MSIX by default" for new product work, while the bootstrap shell ships
unpackaged for xcopy dev loops (SKILL.md "Project setup"). The MSIX head is a reviewed
change that must keep the unpackaged dev loop working.

### Pattern 2 — DI composed in `App`, one page-level lookup

`App.xaml.cs:39-52` builds the container: the single service is the thin REST client
(`AddSingleton<AIHubApiClient>`), view models are transient so each page instance
constructs its own on the UI thread. The only service-locator call is
`App.GetService<T>()` (`:30-31`), forced by WinUI's parameterless-constructor `Frame`
navigation; the page resolves its view model before `InitializeComponent`
(`Views/AIHubPage.xaml.cs:15-21`) and exposes it get-only as the typed x:Bind root
(`:23-24`), kicking the first refresh once from `Loaded` (`:26-32`).

### Pattern 3 — the shell has no logic and never reaches a provider

`Services/AIHubApiClient.cs:15-19`: provider state comes exclusively from
`helios-ai-api`; the shell loads no hub assembly and calls no LLM provider. Base URL
from `HELIOS_API_URL` (default `http://localhost:5170`), access key from
`HELIOS_API_ACCESS_KEY` sent as `X-HELIOS-Api-Key` (`:22-32,54-58`),
`AllowAutoRedirect = false` so the header never follows a redirect (`:46-47`), a 5 s
timeout so "API not running" appears in seconds (`:50-52`). The wire shape mirrors
`ProviderStatusResponse` field for field (`:7-13`). `GUI_THEME_ANALYSIS.md`
"Recommendation" said view models bind to `HELIOS.AIHub` APIs; the bootstrap that shipped
binds to REST instead (`App.xaml.cs:43-45`) — keep the REST rule, it is what lets the
CLI, MCP server, and shell agree.

### Pattern 4 — threading and errors-as-states in the view model

`ViewModels/AIHubPageViewModel.cs:22-42` captures `DispatcherQueue` in the constructor
and throws if constructed off the UI thread; `RefreshAsync` leaves the UI thread with
`ConfigureAwait(false)` and routes every property or collection mutation through
`TryEnqueue` (`:51-70`). `401` → "set the access key"; connection refused, the 5 s
timeout, or a non-JSON answer → "API not reachable, start it with …" (`:72-103`).
Rows are immutable records rebuilt on refresh (`ViewModels/ProviderItemViewModel.cs:5-9`)
with display helpers on the record so XAML needs no converters (`:20-26`).

### Pattern 5 — windowing

`MainWindow.xaml.cs:15-37`: size through `AppWindow.Resize` (`:20`); `Window` is not a
`FrameworkElement`, so theme subscriptions go on the content root (`:22-27`); navigate
the frame first, then select the nav item, because `SelectionChanged` does not fire for
a programmatic pre-layout selection on all WinUI versions — and where it does, the
handler's `CurrentSourcePageType` guard prevents a double navigation (`:30-36`, review
finding). The `NavigationView` itself is declared in `MainWindow.xaml:8-37` with the
Routing and Fleet items disabled as roadmap placeholders (`:22-33`).

## Part 2 — XAML depth, one exemplar each

### Resource dictionaries and merge order

`App.xaml:5-20` is the whole application resource graph: `XamlControlsResources`
merged **first** so app dictionaries can override Fluent defaults (`:8-9`), then the
canonical token pack `ms-appx:///Themes/Tokens.xaml` (`:14`), then the type ramp
`ms-appx:///Themes/Typography.xaml` (`:17`). Order is the override order; put a new
dictionary after the one it overrides. Pages declare no resources of their own — the
one style a page sets inline is the `ListView.ItemContainerStyle`
(`Views/AIHubPage.xaml:58-64`).

### Theme dictionaries, packs, and HighContrast

`Themes/Tokens.xaml:28-131` is a `ResourceDictionary.ThemeDictionaries` block with the
three WinUI keys — `Default` (dark, `:31`), `Light` (`:71`), `HighContrast` (`:110`) —
each defining the *identical* semantic key set: accent, surface ramp, text, status, and
the three `Provider*Brush` readiness tokens (`:33-67`). Sibling packs
(`Tokens.GitHubDark.xaml`, `Tokens.SolarLight.xaml`, `Tokens.HighContrast.xaml`) carry
the same keys so pages never know which pack is active (`Tokens.xaml:6-11`,
`Themes/README.md:7-19`). Rules the files encode:

- **No literal color outside `Themes/Tokens*.xaml`**; pages consume tokens only via
  `{ThemeResource}` (`Tokens.xaml:12-14`; every brush in `Views/AIHubPage.xaml` —
  `:7,27,28,33,67,68,91`; `MainWindow.xaml:36`).
- **HighContrast maps every token to a `SystemColor*` color** referenced with
  `{ThemeResource}` so the user's contrast theme wins (`Tokens.xaml:110-129`); a `Color`
  alias inside a theme dictionary uses `StaticResource … ResourceKey=` (`:112`) — the
  one sanctioned StaticResource inside a theme dictionary (`xaml-authoring.md`
  "Resource dictionaries"). Severity is conveyed by text or shape, not hue, because
  there is no system "error" color (`:108-109`).
- **Contrast is computed, never inherited**: the worst-case ratio is annotated beside
  each text token, and values that failed were adjusted in place — for example
  `ProviderUnconfiguredBrush` dark `#5C6B7A → #8FA1B1` (was 2.28:1), light
  `#7A8894 → #5F6E7A` (was 3.38:1), `StatusErrorBrush` dark rejected the palette's
  `#FF0055` at 3.20:1 (`Tokens.xaml:15-19,63,67,97,99,105`). Report-document compliance
  claims are never evidence (`Themes/README.md:28-35`).
- **A light-first pack mirrors `Light` into `Default`** so choosing it means a light
  shell regardless of OS theme (`Tokens.SolarLight.xaml:5-8`); the GitHub-dark pack
  aliases its 4-step live ramp onto the extended keys rather than inventing colors
  (`Tokens.GitHubDark.xaml:10-12`).
- **Pack swap contract** (P6): replace the merged token dictionary, then call
  `ReadinessVisuals.Refresh(...)` so no brush survives the switch stale
  (`Themes/README.md:21-26`; `Helpers/ReadinessVisuals.cs:22-24,73-84`).

### Styles — and where control templates would go

`Themes/Typography.xaml:21-95` is the type ramp as keyed `TextBlock` styles
(`HeliosDisplay…`, `Headline`, `Title`, `Body`, `BodyStrong`, `Caption`, `Label`,
`Monospace`), each self-contained with **no `BasedOn`** into the WinUI ramp so
parse-level verification on Linux stays honest (`:13-14`), foregrounds only via
`{ThemeResource}` tokens (`:11-12,26`), font fallback stacks (`:22`), and the legacy
`LetterSpacing` (px) carried as `CharacterSpacing` in 1/1000 em (`:10,44`). Pages apply
them with `Style="{StaticResource HeliosHeadlineTextBlockStyle}"`
(`Views/AIHubPage.xaml:26,84,90,94`) — `StaticResource` is correct for a style whose
*brushes* are ThemeResource, because the brush re-resolves even though the style does
not.

No `ControlTemplate` ships in the shell. When one is needed, prefer restyling the
built-in control's lightweight-styling resources first and retemplate only when the
treatment demands it (`design-mining.md` "Triggers and styles"); a container style with
setters is the shipped precedent (`Views/AIHubPage.xaml:59-63`).

### x:Bind versus Binding — compile-time, modes, functions

The shell uses `{x:Bind}` exclusively; there is no `{Binding}` in
`src/gui/HELIOS.Shell`. The page's get-only `ViewModel` property is the typed root
(`Views/AIHubPage.xaml.cs:23-24`). Modes as used:

| Binding | Mode | Why | Exemplar |
|---|---|---|---|
| `{x:Bind ViewModel.ApiBaseUrl}` inside a `Run` | OneTime (default) | The base URL never changes for the page's life | `Views/AIHubPage.xaml:28-31` |
| `{x:Bind ViewModel.StatusMessage, Mode=OneWay}` | OneWay, explicit | Live text; the OneTime default would freeze it | `:32,50` |
| `{x:Bind ViewModel.IsLoading, Mode=OneWay}` on `ProgressRing.IsActive` | OneWay | Live boolean | `:37-38` |
| `{x:Bind ViewModel.IsApiUnavailable, Mode=OneWay}` on `InfoBar.IsOpen` | OneWay | The "API not running" state is a bound property, not a visual state | `:45-50` |
| `{x:Bind ViewModel.RefreshCommand}` | OneTime | Commands are stable objects; `[RelayCommand]` generates it | `:40-41`; `ViewModels/AIHubPageViewModel.cs:51-52` |
| `{x:Bind ViewModel.Providers}` as `ItemsSource` | OneTime | The `ObservableCollection` instance is stable; its contents notify | `:54-55`; `AIHubPageViewModel.cs:45-46` |
| `{x:Bind Name}` / `{x:Bind Kind}` / `{x:Bind ModelDisplay}` inside the template | OneTime | Rows are immutable records rebuilt on refresh | `:85-92`; `ProviderItemViewModel.cs:5-9` |
| `Visibility="{x:Bind HasDetail}"` | OneTime, bool → Visibility built-in | Property binding only; function bindings cannot use the implicit converter | `:93`; `xaml-authoring.md` "x:Bind vs Binding" |
| `{x:Bind helpers:ReadinessVisuals.BrushFor(Readiness)}` | Function binding | Maps the wire readiness string to a token brush without a converter | `:81,100`; `Helpers/ReadinessVisuals.cs:37-52` |

Function-binding trap and its fix: a function binding resolves at bind time and does
**not** re-run on theme change. The shell keeps that binding correct by returning
*shared mutable* `SolidColorBrush` instances whose `Color` is re-resolved on
`ActualThemeChanged` and `HighContrastChanged` — every bound element recolors with no
rebind (`Helpers/ReadinessVisuals.cs:13-25,59-71`). Where `xaml-authoring.md` still
speaks of an "accepted staleness window" for that function, the code has since closed
it (GUI_UPGRADE_PLAN P1 stale-brush fix); the reference file wins only where the code
agrees, and here the code is the newer truth.

`{Binding}` stays reserved for dynamic-DataContext cases with a stated reason in the PR
(SKILL.md "x:Bind over Binding"); none exists in the shell today.

### Data templates and template selectors

The provider row is one `DataTemplate` with `x:DataType="vm:ProviderItemViewModel"`
(`Views/AIHubPage.xaml:65-104`): a token-brushed `Border` card (`:67-71`), a
three-column `Grid` (`:72-77`), the readiness `Ellipse` (`:79-81`), stacked text with
ramp styles (`:83-96`), and the readiness label (`:98-100`). The `ListView` disables
selection and item click because the dashboard is read-only (`:54-57`).

No `DataTemplateSelector` ships. For heterogeneous rows prefer `ChoosingItemContainer`
on `ListView` so container recycling stays effective, and `x:Phase` for progressive
rendering during fast panning (`xaml-authoring.md` "DataTemplates and list controls").
Keep the virtualizing control's extent bounded — the shell gives the list the star row
of the page grid (`:12-13,54`), never an unbounded `ScrollViewer` parent.

### Visual states

No `VisualStateManager` ships in the shell; the two states the page has —
loading and API-unavailable — are bound properties driving `ProgressRing.IsActive` and
`InfoBar.IsOpen` (`Views/AIHubPage.xaml:37-38,45-50`), which is the right tool when a
state is a *fact from the view model*. Reach for `VisualStateManager` when a state is a
*layout* concern: attach `VisualStateGroups` to the first child of the page root (the
outer `Grid` at `:9`), declare `AdaptiveTrigger` breakpoints, and prefer setters that
reflow the existing elements (`xaml-authoring.md` "VisualStateManager"). Legacy WPF
`Style.Triggers` become these states, never property triggers
(`design-mining.md` "Triggers and styles").

### Win2D and Composition seams — what the shell uses today

Nothing yet. The shell references no Win2D package (`HELIOS.Shell.csproj:33-38`), draws
no `CanvasControl`, and starts no Composition animation; all rendering is XAML layout
over token brushes. The seams are *designed* and gated:

| Seam | When it lands | Rule | Source |
|---|---|---|---|
| Win2D `CanvasControl` sparklines and cost charts | P3 metrics cards over `GET /v1/metrics` | `Invalidate()` only when data changed; allocate nothing in `Draw`; cache in `CreateResources` | `GUI_UPGRADE_PLAN.md` P3; `.claude/agents/gui-perf-profiler.md:16-20` |
| `Microsoft.UI.Composition` for blade, aperture, rings, particles, glow, transitions | P6 effects | Animations run on the compositor; a `DispatcherTimer` ticking for visual effect is a finding | ADR-0010 "Decision"; `gui-perf-profiler.md:19-20` |
| Native spoke into a `SwapChainPanel` | Only when profiling shows CPU-bound scene prep | Consumed through the hub's interop layer; the shell never loads a spoke DLL | SKILL.md line 6; `rendering-interop.md` "Managed vs native" |

The dashboard seam those charts will read is `GET /v1/metrics`
(`src/ai/HELIOS.AIHub.Api/ApiModels.cs:101-134`); `TokensUsed` and
`CostPerMillionTokens` are always `null` because outcomes persist no token counts
(`:113-117`), so a card shows *recorded* cost, never a per-1k-token price computed in
the shell.

### XAML traps this repo's reviews caught

| Trap | Where it was caught | The fix as shipped |
|---|---|---|
| Programmatic nav selection either does not fire `SelectionChanged` or fires it synchronously and double-navigates | `MainWindow.xaml.cs:30-34` (review finding) | Navigate first, then select; guard on `CurrentSourcePageType` |
| A high-contrast toggle does not raise `ActualThemeChanged`, so brushes keep the old palette | `Helpers/ReadinessVisuals.cs:62-69` (review finding) | Subscribe to `AccessibilitySettings.HighContrastChanged` too |
| `HighContrastChanged` arrives off the UI thread | `ReadinessVisuals.cs:66-69` | Marshal through the root's `DispatcherQueue` before mutating live brushes |
| `ActualTheme` only reports Light/Dark, so the `HighContrast` dictionary is unreachable | `ReadinessVisuals.cs:89-98` (review finding) | Detect contrast via `AccessibilitySettings.HighContrast` and resolve the `HighContrast` dictionary explicitly |
| Function bindings freeze the brush they returned at bind time | `ReadinessVisuals.cs:13-25` | Return shared mutable brushes and re-resolve their colors |
| Token values inherited from report documents failed measured contrast | `Themes/Tokens.xaml:15-19,63,67,97,99,105` | Computed WCAG ratios; adjusted values annotated inline; reports never cited |
| Literal colors or `StaticResource` brushes freeze the launch theme | `.claude/agents/winui3-reviewer.md:15-16`; `Tokens.xaml:12-14` | Semantic tokens via `{ThemeResource}` only |
| x:Bind OneTime surprises; missing change notification; static event subscriptions that leak | `winui3-reviewer.md:12-14` | Explicit `Mode=OneWay` on live values (`AIHubPage.xaml:32,38,46,50`); `[ObservableProperty]`; unsubscribe (`AIHubPage.xaml.cs:28`) |
| UI objects touched off the `DispatcherQueue`; `async void` handlers; `.Result`/`.Wait()` on the UI thread | `winui3-reviewer.md:10-11` | Capture the queue at construction and `TryEnqueue` (`AIHubPageViewModel.cs:22-26,60`) |
| Free-running redraw timers; allocation inside `Draw`; HLSL or device management in C# | `gui-perf-profiler.md:16-25` | Redraw on data change only; native work goes to the C++ lane |
| Claims about frame rate made from a Linux container | `gui-perf-profiler.md:26-31` | Static analysis here; name the Windows measurement and its threshold |
| Logic creeping into the shell; web views for core surfaces | `GUI_THEME_ANALYSIS.md` "Recommendation", "Interop boundary" | View models bind to the hub's surface only; no `WebView2` for core pages |

## Part 3 — legacy WPF: where it lives, how to read it, what it may become

### The inventory

| Asset | State | Allowed use |
|---|---|---|
| Root `HELIOS.Platform.csproj` (`UseWPF`) | Temporary legacy baseline tracked by HC-002; excluded from `HELIOS.sln`; recursively globs C# (CLAUDE.md "Binding architecture rules") | Keep its `<Compile Remove>` guards current when adding C# directories; never build product code through it |
| `src/gui/MonadoBlade.GUI/` (~60 files) | Orphaned — no csproj includes it; `AIHubWindow.cs` carries a hardcoded provider list and empty stubs (`GUI_THEME_ANALYSIS.md` "Inventory") | Mine for design intent only (`src/gui/README.md`) |
| `docs/ui-xenoblade/` (`HELIOS.WPF.csproj`, components, shaders) | Quarantine candidate; never compiled (`GUI_THEME_ANALYSIS.md` "Inventory") | Read for vocabulary; port per `design-mining.md` |
| `src/core/.../Phase10/BuilderUI/` | WPF window + step engine (`design-mining.md` "Corpus map") | Re-author as a shell page only if a real setup scenario needs it |
| Recovered `.crdownload` files and WPF-era prototypes | Inert evidence — never compiled, packaged, executed, or imported (ADR-0010 "Legacy exception") | Reference only |

Enforcement: `scripts/validation/validate_yolkster_cutover.py` fails the contract if
new WPF/UWP references appear outside the baseline or an active GUI project lacks
`<UseWinUI>true</UseWinUI>` (ADR-0010 "Enforcement"). The rejected list is explicit:
`<UseWPF>`, `System.Windows`, `PresentationFramework`, `PresentationCore`,
`Windows.UI.Xaml`, PowerShell `Add-Type` GUI hosts, and any WPF bridge, fallback shell,
animation host, or migration layer (ADR-0010 "Explicitly rejected").

### Reading legacy WPF without importing it

Read a legacy file with these translations in mind and write the WinUI 3 form directly —
never a WPF intermediate:

- Namespaces and controls: `System.Windows.*` → `Microsoft.UI.Xaml.*`,
  `clr-namespace:` → `using:` (the shell's own `xmlns:helpers="using:HELIOS.Shell.Helpers"`
  at `Views/AIHubPage.xaml:5`), missing panels (`WrapPanel`, `DockPanel`,
  `UniformGrid`) re-laid out, code-built `Window` subclasses re-authored as pages
  inside the `NavigationView` (`design-mining.md` "Namespace and control mapping").
- Triggers and styles: `Style.Triggers` → `VisualStateManager`; `DynamicResource` →
  `{ThemeResource}` (`Views/AIHubPage.xaml:7`); trigger-driven storyboards → visual
  states or Composition (`design-mining.md` "Triggers and styles").
- Effects: `DropShadowEffect` → Composition `DropShadow` or `ThemeShadow`;
  `BitmapEffect` and `ShaderEffect` do not port — shader work is Win2D custom effects or
  native-spoke work (`design-mining.md` "What does NOT port"; `interaction-and-motion.md`
  "WPF → WinUI porting notes").
- Threading: WPF `Dispatcher` becomes the captured `DispatcherQueue` of Pattern 4.
- Binding: DataContext `{Binding}` and `RelativeSource AncestorType` become page-class
  `x:Bind` to a typed view model (`Views/AIHubPage.xaml.cs:23-24`;
  `design-mining.md` "x:Bind conversion").
- Colors: every literal becomes a semantic token; legacy palettes contribute *values*
  (`Themes/Tokens.xaml:41,70`), never brush keys or files (`design-mining.md` "Corpus map").
- Type: `LetterSpacing` → `CharacterSpacing` (`Themes/Typography.xaml:10`).

The corpus never compiled, so every attribute is verified against the live shell or
Microsoft Learn before it is trusted (`design-mining.md` "First rule").

### Migration checklist (one seed → one shell page)

1. Locate the seed in the inventory and its target in `design-mining.md` "Corpus map";
   confirm the phase in `GUI_UPGRADE_PLAN.md`.
2. Write the page under `Views/` with a transient view model registered in
   `App.xaml.cs`; data comes from `AIHubApiClient` (REST), never from a provider or a hub
   assembly.
3. Tokens via `{ThemeResource}` only; add every new key to all three theme dictionaries
   of every pack, with a computed contrast note.
4. `x:DataType` on every template; explicit `Mode=OneWay` on live values; marshal
   through the captured `DispatcherQueue`; errors are displayed states.
5. Run `python3 scripts/validation/validate_yolkster_cutover.py` and build
   `src/gui/HELIOS.Shell.sln` on Windows (`dotnet build src/gui/HELIOS.Shell.sln -c
   Debug -p:Platform=x64`); Linux CI never compiles the shell.
6. Gate: `winui3-reviewer` and `ux-reviewer` before the normal review wave, and
   `gui-perf-profiler` wherever a `CanvasControl` or Composition animation appears
   (`GUI_UPGRADE_PLAN.md` "Agent roster"); `design-miner` owns corpus ports.

## When to route this work to which model or provider

Chains are `config/aihub.json:97-215`. There is no GUI-specific task type in the hub;
`gui_authoring`, `rendering`, and `native_optimization` are *lane names* of the
`xcore-9-native` pool (`config/fleet/fleet-topology.json:92`), so that pool's chain
(`anthropic`, `openai`, `codex`) applies to fleet dispatch while hub calls use:

| Shell work | Task type → chain | Why |
|---|---|---|
| Page/VM structure, navigation, threading design | `architecture_design` → `anthropic`, `anthropic-foundry`, `openai` | Structural reasoning across views (SKILL.md "Which LLM") |
| XAML boilerplate, styles, templates, converters | `code_generation` → `codex`, `openai-codex`, `openai`, `azure-openai`, `anthropic` | Mechanical markup; pin x:Bind-first, tokens-only, `x:DataType` in the request and reconcile against `xaml-authoring.md` "Generating XAML with LLM agents" |
| Reading a legacy WPF file and proposing its WinUI form | `long_context_analysis` → `anthropic`, `anthropic-foundry`, `claude-cli` | Whole-file recall; the output is a proposal for a WinUI page, never WPF |
| Review of a shell PR (threading, x:Bind, theme regressions) | `code_review` → `anthropic`, `anthropic-foundry`, `claude-cli`, `openai` | The `winui3-reviewer` gate |

Language-qualified routing keys landed in PR #248
(`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`): `helios-ai route code_generation
"<prompt>" --language xaml` tries `taskRouting["code_generation:xaml"]` before the bare key
(`TaskTypeRoutingStrategy.GetChain`,
`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs:168-196`). No `:xaml` chain is
shipped — `config/aihub.json` qualifies `code_generation` only for `cpp`, `fsharp` and
`python` (`config/aihub.json:105-125`) — so the chain above applies and the outcome is recorded with
`language: xaml`; a `code_generation:xaml` key under `taskRouting` in both config files is
the edit if the shell's markup ever earns its own order.
