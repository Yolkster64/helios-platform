# Interactive Shell Experience (design of record)

The interactive, audio, and lighting layer of the HELIOS shell: the Monado command
wheel, hologram/ether-laser effect treatments, the motion system, pointer
interactivity, the spatial sound engine, and opt-in RGB device lighting. This
document is a DESIGN plus a phased plan — **none of it is implemented; nothing here
compiles on Linux CI.** The shell is WinUI 3 (`src/gui/HELIOS.Shell`, Windows App
SDK 1.6, `net8.0-windows10.0.19041.0`, min platform 10.0.17763), builds only via
`dotnet build src/gui/HELIOS.Shell.sln -c Debug -p:Platform=x64` on Windows, and
every PR that implements a phase below carries the honest "compiles on Windows only,
parse-level checks on Linux" note per `GUI_UPGRADE_PLAN.md` §3. Every performance
number in this document is a **TARGET** in the sense fixed by
`DYNAMIC_BACKGROUND_ENGINE.md` §4: a budget to measure against with the
gui-perf-profiler's debug overlay (or PIX/VS frame analysis) on real hardware —
never an achievement to claim. The provenance rule of `GUI_UPGRADE_PLAN.md` §1
applies to everything mined here: the recovered `docs/ui-xenoblade` material is
design seed, not shipped feature, and its companion report docs are unreliable.

Companions: `GUI_UPGRADE_PLAN.md` (phases, §2 canonical tokens, agent roster),
`DYNAMIC_BACKGROUND_ENGINE.md` (tiers, budgets, and the flat-C parameter-block ABI
this design composes with — nothing below duplicates its numbers),
`.claude/skills/winui3-shell/SKILL.md` + `references/rendering-interop.md` +
`references/interaction-and-motion.md` (the working-knowledge companion to this
doc). Consuming agents: `ui-designer` (wheel, panels, motion), `render-engineer`
(native-tier effects), `audio-engineer` (§5, new with this design),
`theme-designer` (motion + palette tokens); gated by `winui3-reviewer`,
`ux-reviewer`, `gui-perf-profiler`, and `cpp-perf-reviewer` where the native seam
is crossed.

## 0. What the recovered seeds actually contain

Four recovered WPF files seed the visual vocabulary of §§1–3. Per the provenance
rule they are cited for what they *are*, defects included — none of them is
portable code:

- **`docs/ui-xenoblade/Components/Panels/HolographicPanel.xaml`(+`.cs`)** — a
  40-line UserControl: a `Border` (token background, 2 px cyan border, corner
  radius 8) whose "glow" is a WPF `DropShadowEffect` (hardcoded `#00D4FF`,
  BlurRadius 15, ShadowDepth 0, Opacity 0.5); a "scan lines" `Rectangle`
  (`IsHitTestVisible="False"`, Opacity 0.08) filled with
  `HolographicScanLinesBrush` — which `Theme/Brushes.xaml` defines as a **single
  vertical two-band LinearGradientBrush** (cyan above 0.5, white below, brush
  Opacity 0.1). It never renders repeating lines. The file also would not load
  as-is: `ResourceDictionary.MergedDictionaries` sits directly under
  `<UserControl>` (invalid property element), and the `ContentPresenter` uses
  `TemplateBinding` outside a ControlTemplate while binding the control's own
  `Content` into itself. The code-behind is an empty `InitializeComponent` shell.
- **`docs/ui-xenoblade/CustomControls/MonadoGlowBorder.cs`** — a `Border` subclass
  that, on `Loaded`, re-parents itself: builds a radial-gradient glow `Ellipse`
  (3-stop alpha falloff: intensity×200 → intensity×100 → 0) behind a cloned inner
  Border inside a Grid. DPs: `GlowColor` (default `FromArgb(0, 0, 212, 255)` —
  **alpha 0, invisible by default**), `GlowIntensity` (0.6), `EnablePulse` (true).
  The pulse is a `DoubleAnimation` on the ellipse's Opacity from intensity×0.5 to
  intensity, **666 ms**, CubicEase InOut, AutoReverse, Forever.
  `OnGlowIntensityChanged` is an empty stub — intensity changes after load do
  nothing.
- **`docs/ui-xenoblade/CustomControls/AnimatedProgressRing.cs`** — a `Control`
  subclass that would not compile: it assigns `this.Content` (WPF `Control` has no
  `Content` property), calls `Color.FromArgb(0, 212, 255)` (three args to a
  four-arg method), and instantiates `LinearEase` (no such WPF type). Its custom
  `Arc : Shape` ignores its own `StartAngle`/`EndAngle` and emits a degenerate
  path that starts and ends at (100,50) — it draws nothing meaningful.
  `OnValueChanged`/`OnColorChanged` are empty stubs. What it *does* usefully seed:
  the shape of the control — a circular low-alpha track + an accent arc + an
  indeterminate 360° rotation over 2 s.
- **`docs/ui-xenoblade/Theme/Animations.xaml`** — an 11-storyboard catalog with
  CubicEase in/out/in-out easing resources: `PulseAnimation` (opacity 1→0.6,
  666 ms, auto-reverse forever), `GlowPulseAnimation` (0.8→0.3, 666 ms),
  `ScalePulseAnimation` (1.0→1.05, 666 ms), `SlideInFromTopAnimation` /
  `SlideInFromRightAnimation` (ThicknessAnimation on **Margin** + fade, 500 ms),
  `FadeInAnimation`/`FadeOutAnimation` (300 ms), `ColorTransitionAnimation`
  (hardcoded `#00D4FF`→`#0080FF` border color, 500 ms, auto-reverse forever),
  `SpinAnimation` (0→360°, 2 s), `ButtonHoverGlowAnimation` (opacity 0.3→0.8,
  300 ms), `EnergyDischargeAnimation` (fade-out + scale 1→2, 800 ms). Defects: it
  declares `<LinearEase/>` (not a WPF type) and references it via forward
  `StaticResource`; the header's "1.5 Hz" claim is off by 2× (666 ms is the
  *half*-cycle under AutoReverse, so the pulse is ~0.75 Hz); the slide-ins animate
  Margin (layout-bound, UI-thread); and the color transition hardcodes the retired
  WPF-era `#00D4FF` cyan (canonical accent is `#00D9FF`, `GUI_UPGRADE_PLAN.md` §2).

What survives the port is the **vocabulary** — radial glow halos, a 666 ms pulse
period, ring-and-arc geometry, scanline overlays, slide/fade/discharge motions —
re-expressed on Composition and Win2D with token colors.

## 1. The Monado wheel

A radial command wheel, Monado-arts style: press the invoke gesture, a ring of
segments springs open around the pointer (or window center for keyboard
invocation), each segment a shell command; rotate/arrow/point to select, release
or confirm to execute.

### Control shape

`MonadoWheel` is a custom `Control` (templated, in `src/gui/HELIOS.Shell/Controls/`)
hosted in a light-dismiss `Popup`. Its items are `MonadoWheelItem` view-model
objects (icon glyph, label, command via `ICommand` from CommunityToolkit MVVM —
skill conventions apply: `x:Bind`, DI'd view models, no service locators).
Commands come from the shell's existing surface (navigate to AIHub/Routing/Fleet,
refresh, toggle theme, open settings, toggle background tier); the wheel adds no
new capabilities, only a faster path to existing ones.

### Radial layout math

For `N` segments, segment `i` owns the angular span
`[θ_i − π/N, θ_i + π/N)` where `θ_i = −π/2 + i·2π/N` (segment 0 at 12 o'clock,
clockwise). Item content centers at `center + r_mid·(cos θ_i, sin θ_i)` with
`r_mid = (r_inner + r_outer)/2`. Pointer hit-testing is polar: given pointer
offset `(dx, dy)` from the wheel center, the hit segment is
`i = round(((atan2(dy, dx) + π/2) mod 2π) / (2π/N)) mod N`, valid only when
`r_inner ≤ √(dx²+dy²) ≤ r_outer`; inside `r_inner` is a dead zone (no selection;
click there dismisses, matching light-dismiss). Segment arcs are drawn with Win2D
(`CanvasControl` — mostly-static content, redrawn only on selection/theme change,
per `rendering-interop.md`'s control-choice table): per-segment
`CanvasPathBuilder` arc geometry, fills and strokes from token colors resolved at
`CreateResources`, never per-`Draw`.

### Input: three modalities, full parity

Every wheel action — cycle selection, jump to a segment, invoke, dismiss — is
reachable by mouse wheel, pointer, and keyboard:

| Action | Mouse wheel | Pointer | Keyboard |
|---|---|---|---|
| Cycle selection | `PointerWheelChanged`: selection advances by `MouseWheelDelta / 120` detents, modulo N (WHEEL_DELTA = 120 per [PointerPointProperties.MouseWheelDelta](https://learn.microsoft.com/windows/windows-app-sdk/api/winrt/microsoft.ui.input.pointerpointproperties.mousewheeldelta); accumulate fractional deltas from free-spinning wheels) | hover moves selection to the hit segment | Left/Up = counter-clockwise, Right/Down = clockwise; Home/End = first/last |
| Invoke | click (press+release in segment) | click | Enter or Space |
| Dismiss | — | click in dead zone / light-dismiss outside | Esc |

The control handles [`UIElement.PointerWheelChanged`](https://learn.microsoft.com/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.uielement.pointerwheelchanged)
and marks it `Handled` while open so the page behind never scrolls. Keyboard
handling lives in `OnKeyDown` on the control; the wheel is a single tab stop
(`IsTabStop = true`) whose arrow keys move an *internal* selection — matching the
composite-control pattern of the
[keyboard accessibility guidance](https://learn.microsoft.com/windows/apps/design/accessibility/keyboard-accessibility),
with a visible focus/selection indicator drawn as part of the segment highlight.

### Interaction contract (non-negotiable)

- **No focus stealing.** The wheel opens only on explicit invocation (a chosen
  accelerator and/or a titlebar button — binding decided at implementation, never
  hover). On open it records the previously focused element, takes focus itself,
  and **restores focus on dismissal**. It never opens spontaneously from
  background events.
- **Esc always dismisses**, invoking nothing. Light-dismiss (click outside)
  behaves identically.
- **Narrator announces segments.** The wheel exposes a custom automation peer
  (derive from `FrameworkElementAutomationPeer` since the base is `Control`, per
  [Custom automation peers](https://learn.microsoft.com/windows/apps/design/accessibility/custom-automation-peers));
  each segment is exposed as a child peer with a localized `Name`, and selection
  changes raise the appropriate automation events (`RaiseAutomationEvent` /
  `RaisePropertyChangedEvent`) so selection tracking is audible, not just visible.
  `AutomationProperties.Name` covers the wheel itself. This is a `ux-reviewer`
  gate item, verified with Narrator on Windows — never asserted from Linux.
- Selection is **never color-only**: the selected segment gets a geometry change
  (thicker stroke / radial pop) plus the glow, so it survives HighContrast, where
  all glow treatments are disabled outright (same rule as
  `DYNAMIC_BACKGROUND_ENGINE.md`: HighContrast forces effects off).

### Ring treatment (seeded by MonadoGlowBorder + AnimatedProgressRing)

The look comes from the two recovered controls, ported to the WinUI 3 stack:

- The **glow halo** re-expresses MonadoGlowBorder's radial-gradient ellipse
  (§0: 3-stop alpha falloff, 666 ms opacity pulse) as a Composition
  `SpriteVisual` behind the ring — radial-gradient composition brush, opacity
  animated by a `ScalarKeyFrameAnimation` running on the compositor (off the UI
  thread, per [Composition animations](https://learn.microsoft.com/windows/apps/develop/composition/composition-animation)).
  The WPF `DropShadowEffect` glow becomes a Composition
  [`DropShadow`](https://learn.microsoft.com/windows/apps/develop/composition/composition-shadows)
  only where a true shadow is wanted; note the documented cost table — masked
  shadows and *animated blur radius* are High cost, so pulses animate **opacity**,
  never blur radius. Glow color is the token accent (`#00D9FF`) with the gold
  highlight token reserved for celebration moments (`GUI_UPGRADE_PLAN.md` §2) —
  the seeds' hardcoded `#00D4FF` does not survive.
- The **ring geometry** takes AnimatedProgressRing's intent (low-alpha circular
  track + accent arc) as the Win2D drawing described above; the indeterminate
  2 s rotation maps to a keyframe animation on the visual's
  `RotationAngleInDegrees` if a "working" wheel state is ever needed.
- **Spring open/close**: a `SpringVector3NaturalMotionAnimation` on `Scale`
  (0.9→1.0, `DampingRatio < 1` for a slight overshoot) started directly on the
  element via `UIElement.StartAnimation` — the WinUI 3 pattern, no
  `ElementCompositionPreview` detour
  ([XAML-Composition interop](https://learn.microsoft.com/windows/apps/develop/composition/xaml-comp-interop)) —
  plus an opacity fade. Under reduced motion (§3) the spring is replaced by a
  plain fast fade.

Frame-cost expectations are targets: the wheel is a transient surface — a
`CanvasControl` that redraws only on selection change plus compositor-side
animations; it adds **no** persistent render loop. `gui-perf-profiler` verifies
with the P3 debug overlay that an idle open wheel costs zero managed allocations
per frame and no continuous redraw.

## 2. Hologram & ether-laser effects

### HolographicPanel, ported honestly

What the seed actually implements (§0) is a bordered translucent card with a
static cyan glow and a *faux* scanline overlay. The WinUI 3 `HoloPanel` makes the
idea real:

- **Surface**: a `ContentControl` template — token surface brush at partial
  opacity over the shell background, 1–2 px accent border, corner radius from the
  control-corner token. **No backdrop sampling.** The dynamic background renders
  into swap-chain-backed surfaces (`CanvasAnimatedControl` in Ambient,
  `SwapChainPanel` in Full), and WinUI 3 supports neither transparency nor
  Acrylic/backdrop-brush sampling over a `SwapChainPanel`
  (`rendering-interop.md`, from the dxinterop docs) — so translucency is achieved
  compositionally: a semi-transparent token fill *reads* as translucent against
  the animated scene without ever sampling it. This constraint is structural, not
  a polish item.
- **Scanlines**: real ones this time — a Win2D pass drawing 1 px accent-tinted
  horizontal lines at a fixed pitch into a small `CanvasRenderTarget` once (at
  `CreateResources`/size change), displayed as a tiled/stretched overlay at low
  opacity, `IsHitTestVisible="False"` exactly as the seed's overlay was. A slow
  vertical drift, if used, is a Composition offset animation on the overlay
  visual — zero per-frame drawing. The recovered
  `docs/ui-xenoblade/Shaders/ScanLineShader.hlsl` remains a *candidate* for a
  Win2D custom effect ([Implementing custom effects](https://learn.microsoft.com/windows/apps/develop/win2d/custom-effects))
  in the Full tier only — `DYNAMIC_BACKGROUND_ENGINE.md` §1 already inventories
  why those shaders are seeds, not shippable code; that inventory is not
  duplicated here.
- **Glow border**: the MonadoGlowBorder treatment from §1, shared as one
  implementation, pulse disabled by default on panels (a dashboard of pulsing
  cards is noise; the pulse is reserved for attention states).

### Ether-laser beam accents

Panel/page transitions get a single light-beam accent: a thin accent-colored beam
with a soft glow that sweeps along the entering panel's edge and fades (~300–500 ms,
one-shot). Implementation: the beam (core line + wide low-alpha glow, optionally a
Win2D `GaussianBlurEffect` bloom pass per the
[Win2D tutorial](https://learn.microsoft.com/windows/apps/develop/win2d/quick-start))
is drawn **once** into a `CanvasRenderTarget`; the sweep animates the resulting
visual's offset/opacity/scale on the compositor. No per-frame redraw, no timer —
a one-shot Composition animation with a completion handler that releases the
visual.

### Budget: inside the Ambient tier, not beside it

Holo overlays and beam accents are **Ambient-tier content** in
`DYNAMIC_BACKGROUND_ENGINE.md`'s terms: they live inside that document's §4
Ambient budgets (they get no budget line of their own) and obey its rules —
visibility pausing, HighContrast ⇒ off, degradation order. When the background
engine steps down a tier, decorative overlays step down with it: Off tier means
static panels, no scanlines, no beams. The engine doc's numbers are referenced,
not restated, so there is exactly one place they can change.

## 3. Motion system

### When Composition, when storyboards

- **Composition** (`Microsoft.UI.Composition`) for everything continuous,
  physics-driven, input-driven, or decorative: it animates on the compositor's
  independent thread, immune to UI-thread jank
  ([Composition animations](https://learn.microsoft.com/windows/apps/develop/composition/composition-animation)).
  WinUI 3 runs `CompositionAnimation`s directly on elements via
  `UIElement.StartAnimation`; the compositor comes from
  `CompositionTarget.GetCompositorForCurrentThread()` on the UI thread
  ([interop page](https://learn.microsoft.com/windows/apps/develop/composition/xaml-comp-interop)).
  Two traps from that page + `rendering-interop.md`: the new rendering properties
  (`Scale`, `Translation`) and the old ones (`RenderTransform`, `Projection`) are
  **mutually exclusive** per element, and hand-managing an element's Visual via
  `ElementCompositionPreview` opts it out of the new properties — pick one lane
  per element.
- **XAML storyboards / VisualStateManager** for control-template state
  transitions (hover/pressed/disabled visual states) where `ThemeResource`
  re-resolution and template tooling matter, and for anything that must be
  authorable in a ResourceDictionary. Never for per-frame or layout-affecting
  motion (the seed's Margin-based slide-ins are the anti-pattern — WinUI 3 has no
  `ThicknessAnimation`, and layout animation is UI-thread-bound anyway; slides
  become `Translation` animations).

### The recovered catalog, mapped

| `Animations.xaml` seed (§0) | WinUI 3 equivalent | Notes |
|---|---|---|
| `PulseAnimation`, `GlowPulseAnimation` (666 ms opacity, forever) | `ScalarKeyFrameAnimation` on the glow visual's `Opacity`, iteration Forever | Decorative loop ⇒ stops under reduced motion; period becomes a motion token |
| `ScalePulseAnimation` (1.0→1.05) | `Vector3KeyFrameAnimation` or spring on `UIElement.Scale` | Direct `StartAnimation`, WinUI 3 pattern |
| `SlideInFromTop/Right` (Margin + fade, 500 ms) | `Translation` animation + opacity | Never animate Margin |
| `FadeIn/FadeOut` (300 ms) | Opacity keyframe or implicit show/hide animations | Base duration token |
| `ColorTransitionAnimation` (hardcoded cyan→blue, forever) | `ColorKeyFrameAnimation` on a `CompositionColorBrush`, colors from tokens | Forever border color-cycling is reserved for genuine attention states, not ambient decoration |
| `SpinAnimation` (2 s rotation) | Keyframe on `RotationAngleInDegrees`, or just WinUI's `ProgressRing` | Prefer the platform control |
| `ButtonHoverGlowAnimation` | Implicit animation triggered from hover VisualState | Composition executes, VSM triggers |
| `EnergyDischargeAnimation` (fade + scale×2, 800 ms) | One-shot scale+opacity keyframes | The celebration verb; pairs with the gold highlight token |

Implicit animations ([ImplicitAnimationCollection](https://learn.microsoft.com/windows/apps/develop/composition/composition-animation))
cover reposition/resize choreography on dashboard cards; springs
([natural motion](https://learn.microsoft.com/windows/apps/develop/composition/natural-animations))
cover the wheel and any element that should settle rather than stop; expressions
cover pointer parallax (§4).

### Motion tokens, beside the color tokens

Durations, easings, and physics constants are tokens with semantic names, owned
by `theme-designer` and living next to the §2 color tokens (in
`Themes/Tokens.xaml`, or a sibling `Motion.xaml` merged with it — one authority
either way):

- `MotionDurationFast` 150 ms · `MotionDurationBase` 300 ms ·
  `MotionDurationEmphasis` 500 ms · `MotionDurationCelebration` 800 ms ·
  `MotionPulsePeriod` 666 ms — values distilled from the recovered catalog, open
  to tuning; the names are the contract.
- `MotionEaseIn` / `MotionEaseOut` / `MotionEaseInOut` (the catalog's CubicEase
  set as `KeySpline`/easing resources) and spring constants
  (`MotionSpringDampingRatio` ≈ 0.6, `MotionSpringPeriod` ≈ 50 ms — the
  documented tuning knobs of `SpringVector3NaturalMotionAnimation`).
- Composition animations are built in code, so a small static `MotionTokens`
  class mirrors the XAML values; the XAML resource is the source of truth and the
  mirror is documented as such (same one-authority rule as colors).

No literal duration/easing in page XAML or view code — same rule as literal
colors, same `theme-designer`/`ux-reviewer` finding when violated.

### Reduced motion

The shell honors the OS animation setting via
[`UISettings.AnimationsEnabled`](https://learn.microsoft.com/uwp/api/windows.ui.viewmanagement.uisettings.animationsenabled)
(guidance: [Tailoring effects](https://learn.microsoft.com/windows/apps/develop/composition/composition-tailoring#animations-settings)).
A single `MotionSettings` service reads it at startup and subscribes to
`AnimationsEnabledChanged` (added in SDK 19041 — the shell's target SDK; min
platform is 17763, so guard the event subscription with `ApiInformation` and fall
back to read-at-startup). When animations are disabled:

- Decorative loops (pulse, spin, color cycling, scanline drift) stop entirely.
- Transitions and the wheel's spring collapse to plain fades at
  `MotionDurationFast` or instant.
- Pointer parallax and particle attraction (§4) are off.
- The background engine's own tiers are governed by its document; this service is
  the shell-side switch the effect layers consult.

Every animation site goes through `MotionSettings` — a raw `StartAnimation` on a
decorative visual without the check is a review finding.

## 4. Pointer interactivity

### Cursor parallax

Depth illusion on the dashboard: background layers shift slightly toward the
pointer. Implementation is an `ExpressionAnimation` per layer —
`offset = (pointer − center) * depthFactor` with clamping — with depth factors as
parameters (background ≈ 0.02, mid ≈ 0.05, glow accents ≈ 0.08; tuning values,
not commitments). The pointer position source: the candidate API is a
pointer-position `CompositionPropertySet` consumable by expressions
(`ElementCompositionPreview.GetPointerPositionPropertySet` in the UWP lineage) —
**verify its Windows App SDK availability against Microsoft Learn at
implementation time**, per the reference-file convention; the fallback is a
`PointerMoved` handler writing a `CompositionPropertySet` that the expressions
reference ([relation-based animations](https://learn.microsoft.com/windows/apps/develop/composition/xaml-comp-interop#use-expression-animations)) —
UI-thread writes, compositor-thread evaluation, no per-frame managed animation
code either way. Parallax obeys reduced motion (§3) and is a no-op when the
background tier is Off.

### Hover glow

Interactive cards/buttons get the MonadoGlowBorder-derived glow on hover: an
implicit/keyframe opacity animation on the pre-built glow visual (0 → hover
level over `MotionDurationFast`), triggered from the hover VisualState. The glow
visual exists from template-apply time — hover animates opacity only, allocating
nothing (gui-perf-profiler rule 1 applies to hover paths too: hover storms must
not produce per-event allocations).

### Particle attraction — a parameter, not an interop path

Pointer-attracted embers/particles in the dynamic background are **one more field
in the engine's existing parameter block**, not a new interop surface. Design:
extend `helios_bg_params` (`DYNAMIC_BACKGROUND_ENGINE.md` §2) with
`float pointer_pos[2]` (scene coordinates, NaN or a flag when the pointer is
outside the window) and `float pointer_strength` (0..1, 0 = feature off). The
block already crosses the boundary once per tick via `helios_bg_tick` and is
copied during the call — pointer data rides that copy, so this adds **zero**
additional per-frame interop calls, honors the same double-buffering, and bumps
`helios_bg_abi_version` on both sides in the same commit (the header's stated ABI
contract; the change belongs to `render-engineer` with the `cpp-perf-reviewer`
gate). The managed Ambient-tier sim consumes the identical parameters from the
same C#-side struct. Attraction strength 0 under reduced motion, when sound-style
"calm" settings demand it, or when the user disables it — the sim treats 0 as
"skip the attractor term", not as a branch per particle.

### Hit-test transparency rules

1. **Decorative layers never take input.** Every effect surface — background
   engine controls, scanline overlays, glow visuals, beams, parallax layers —
   is `IsHitTestVisible="False"` (the seed panel already did this for its
   overlay; it becomes a rule). Hit-testing requires visibility and hit-test
   visibility per the platform's routed-event model (see the remarks on
   [PointerWheelChanged](https://learn.microsoft.com/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.uielement.pointerwheelchanged));
   we use that switch deliberately and audit it in review.
2. **No full-window input-eating layers.** Nothing decorative may sit above
   interactive content *and* be hit-testable; the only overlay that takes input
   is the Monado wheel while open, and it is an explicit light-dismiss surface.
3. **Handin visuals stay decorative.** Visuals injected via
   `SetElementChildVisual` draw above the element and lack XAML accessibility
   guarantees (`rendering-interop.md`) — they are used sparingly, never for
   anything a user must perceive to operate the shell, and never hit-testable.
4. **Z-order is fixed**: background engine (bottom, behind NavigationView per
   `DYNAMIC_BACKGROUND_ENGINE.md` §1) → content → per-panel decorative overlays →
   wheel popup (top, only while open).

## 5. Spatial sound engine

Short, subtle UI cues with optional spatialization. Honest platform evaluation
first, then the contract.

### Primary path: AudioGraph + Windows Sonic (in-box, no license)

[`Windows.Media.Audio.AudioGraph`](https://learn.microsoft.com/windows/apps/develop/media-authoring-processing/audio-graphs)
is the right altitude for a cue player: file/frame input nodes → device output
node, with built-in spatial support via `AudioNodeEmitter` (position, shape,
decay, Doppler) and a listener on the device output node. Platform facts that
shape the design (all from the linked Learn page):

- Emitter-fed nodes must be **mono, 48 kHz** — the cue asset pipeline bakes cues
  to exactly that format; stereo or other rates throw.
- Spatialization defaults to Microsoft's HRTF processing;
  `AudioNodeEmitter.SpatialAudioModel` can be set to `FoldDown` for a cheap
  stereo approximation — the engine's low-cost fallback knob.
- Cue placement maps UI geometry to emitter position: a wheel segment at angle
  `θ_i` emits from azimuth `θ_i` at ~1 m; panel transitions emit from the panel
  edge. Subtle by design — centimeters of theater, not a game soundscape.

The lower-level Win32 surface,
[`ISpatialAudioClient`](https://learn.microsoft.com/windows/win32/api/spatialaudioclient/nn-spatialaudioclient-ispatialaudioclient)
(part of Windows Sonic, per its own docs), is the fallback/expansion path if
AudioGraph proves limiting: dynamic spatial audio objects positioned in 3D
([Render spatial sound](https://learn.microsoft.com/windows/win32/coreaudio/render-spatial-sound-using-spatial-audio-objects)).
Two honest notes from
[Microsoft Spatial Sound](https://learn.microsoft.com/windows/win32/coreaudio/spatial-sound):
when spatial sound is not enabled on the endpoint,
`ISpatialAudioClient::GetMaxDynamicObjectCount` returns **0** — the engine must
treat "no spatial" as normal and play plain stereo; and spatial-sound apps "abide
by the system mixing policy", so output rides the ordinary system mixer. The
user-selected output format (Windows Sonic for Headphones, Dolby Atmos, DTS) is
abstracted behind the same API — Windows Sonic for Headphones ships with Windows;
format upsells are the *user's* choice and cost the app nothing. For a handful of
UI cues, AudioGraph is the plan of record; `ISpatialAudioClient` is documented so
the evaluation isn't re-litigated later.

### Middleware option: Wwise (evaluated, not chosen)

Audiokinetic Wwise is the serious middleware option: an authoring application plus
a native runtime SDK linked into the app — which in HELIOS terms means a native
spoke and the full C++ lane (flat ABI, `cpp-perf-reviewer` gate), plus an
authoring pipeline and sound banks in the asset flow. Microsoft's spatial-sound
docs note that middleware vendors wrap Microsoft Spatial Sound as DSP plugins
("consult with your audio middleware solution provider for their level of
support" — [Spatial Sound](https://learn.microsoft.com/windows/win32/coreaudio/spatial-sound#enabling-microsoft-spatial-sound)),
so Wwise can sit on the same platform output. Licensing is Audiokinetic's,
registration-gated, and changes over time; free/indie tiers have historically
carried project-scope limits — **verify current terms at evaluation time and
assume a commercial license is required for a commercial enterprise product**.
Verdict: for a vocabulary of a half-dozen short cues, Wwise is integration weight
without payoff. Revisit only if the audio scope grows by an order of magnitude.

### THX: a quality bar, not a dependency

THX Spatial Audio is a **consumer product** (end-user spatial-audio software);
THX does not offer a general, publicly available SDK for third-party desktop
applications that this design could target (as of this writing — re-verify if
that changes). "THX-grade" in HELIOS discussions means the *quality bar* —
clean masters, consistent loudness across cues, no clipping or harshness, restraint —
never a THX dependency, certification, or branding claim.

### The contract (non-negotiable, owned by audio-engineer)

- **OFF by default.** HELIOS is an enterprise tool; sound is opt-in in settings.
- **Zero audio work when disabled**: no `AudioGraph` constructed, no assets
  loaded, no audio threads, no device activation. The `SoundService` is a no-op
  stub until the user opts in; toggling off tears the graph down.
- **Master toggle + volume slider** in shell settings; per-category toggles
  (navigation ticks vs. status cues) may follow, the master switch ships first.
- **Honors system mute/volume by construction** — cues play through the normal
  Windows audio session and system mixer (see the mixing-policy note above); the
  engine never bypasses or ducks other audio, never uses exclusive mode.
- **Cues are short (≤ ~300 ms) and subtle**; default volume errs low. No looping
  ambience in v1. Sound is never the sole signal for anything — every audible
  state change has a visual counterpart (ux-reviewer gate).
- Device loss/format change is silent degradation: catch, rebuild once
  opportunistically, otherwise stay silent — never surface an error dialog for a
  decorative cue.

## 6. Chroma / RGB lighting

Opt-in ambient lighting on the user's RGB peripherals, synced to the shell's
mood: the dynamic background engine already computes a palette (day/night lerp of
the canonical tokens — `DYNAMIC_BACKGROUND_ENGINE.md` §§1,3); the lighting bridge
consumes the engine's published palette snapshot and pushes 2–4 anchor colors to
devices.

- **Two device lanes, both optional at runtime:**
  - **Razer Chroma SDK** — Razer's own devices; requires Razer's Chroma runtime
    (Synapse) on the machine. Integration is via Razer's published SDK surfaces;
    developer terms are Razer's — verify current SDK terms at implementation
    time. Loaded/connected **dynamically**; runtime absent ⇒ the lane silently
    reports unavailable.
  - **OpenRGB** — vendor-neutral, open-source; exposes a local SDK server
    (network socket on localhost) that clients connect to, covering many vendors'
    devices with community-maintained support. OpenRGB itself is GPL-licensed:
    the shell talks to it **over the socket protocol from our own client code**
    (no linking); a license review of any client library is required before one
    is adopted rather than written.
- **OFF by default**, separate toggle per lane, nothing probed or connected until
  enabled — an enterprise desktop with neither runtime is the expected case, and
  the feature must be invisible there.
- **Update rate ≤ 2 Hz**, from a background-thread timer reading the engine's
  immutable palette snapshot (the same snapshot pattern as the engine's AI layer
  — zero work on any frame path, zero UI-thread involvement). Lighting is
  ambient, not reactive per-frame.
- **Silent degrade everywhere**: connect failures, device removal, runtime
  updates — log at debug level, back off retries (≤ 1/min), never a user-facing
  error. Disabling stops the timer and releases the connection; minimized shell
  pauses updates (the engine's clock is paused anyway), leaving devices on the
  last palette.
- Never requires elevation, never bundles vendor runtimes, never writes device
  firmware/settings beyond transient colors.

## 7. Facelift sequencing

This layer rides `GUI_UPGRADE_PLAN.md` — it does not fork it. P1 (canonical
tokens) is the prerequisite for every visual phase here; the wheel and holo work
land only after P3 (which ships the Win2D reference pattern and, critically, the
debug perf overlay — the instrument every claim below is measured with); sound
and lighting are independent opt-ins that touch no rendering path.

| Phase | Scope | Prereqs | Owner | Gates |
|---|---|---|---|---|
| **IX1** | Motion tokens + `MotionSettings` (reduced-motion service); catalog mapping of §3 applied to existing shell animations | P1 | theme-designer (tokens), ui-designer (service) | winui3-reviewer, ux-reviewer |
| **IX2** | Monado wheel control (§1): layout, input parity, automation peer, spring open/close, glow treatment | P3, IX1 | ui-designer | winui3-reviewer, ux-reviewer (Narrator/keyboard), gui-perf-profiler |
| **IX3** | HoloPanel + ether-laser transition accents (§2), inside Ambient-tier budgets | P3, IX1; composes with BG2 | ui-designer (render-engineer consulted if any custom-effect work) | winui3-reviewer, gui-perf-profiler; cpp-perf-reviewer only if the native spoke is touched |
| **IX4** | Pointer parallax + hover glow (§4); particle-attraction params into the engine ABI | IX1; ABI change lands with BG2 (managed) / BG4 (native) | ui-designer; render-engineer for the ABI bump | winui3-reviewer, gui-perf-profiler, cpp-perf-reviewer (ABI) |
| **IX5** | Spatial sound engine (§5): SoundService, cue assets, settings surface | none (independent) | **audio-engineer** | winui3-reviewer (settings UI), ux-reviewer (sound-never-sole-signal) |
| **IX6** | RGB lighting bridge (§6) | BG1 (palette snapshot exists) | ui-designer + render-engineer (snapshot plumbing) | winui3-reviewer, gui-perf-profiler (zero frame-path work) |

Every phase is one reviewable PR with the standard honesty note; every phase that
draws anything states overlay-measured results or "measurement pending" — the
`DYNAMIC_BACKGROUND_ENGINE.md` §4 rule ("no FPS or frame-cost claim … unless the
overlay measured it on real hardware") applies verbatim to this document.

### Non-goal boundary

When this effort is described as making HELIOS feel like "a full OS UI", that
means **the HELIOS platform's own UI surface** — its shell window(s), panels,
sounds, and opted-in peripheral lighting. It never means modifying Windows
itself: no shell replacement, no DWM/system-theme/lock-screen changes, no
system-wide input or audio hooks, no OS chrome outside the app's windows. HELIOS
manages Windows machines; it does not reskin Windows.
