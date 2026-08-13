Versions and API claims mirror the cited repo files; update this file in the same PR that changes them.

# Interaction and motion (WinUI 3 / HELIOS.Shell)

Working knowledge for the interactive layer designed in
`docs/architecture/INTERACTIVE_SHELL_EXPERIENCE.md` (Monado wheel, holo effects,
motion system, pointer interactivity). Applies to `src/gui/HELIOS.Shell/`
(Windows App SDK 1.6, `net8.0-windows10.0.19041.0`, min platform 10.0.17763 —
`src/gui/HELIOS.Shell/HELIOS.Shell.csproj`). Platform behavior below is verified
against Microsoft Learn (XAML-Composition interop, natural/relation animations,
pointer input, custom automation peers, UISettings); budgets live in
`docs/architecture/DYNAMIC_BACKGROUND_ENGINE.md` §4 and are TARGETS, never claims.

## Composition animations: the three patterns

Get the compositor on the UI thread with
`CompositionTarget.GetCompositorForCurrentThread()`. In WinUI 3, animations start
**directly on elements** — `element.StartAnimation(anim)` — no
`ElementCompositionPreview.GetElementVisual` detour (that is the UWP pattern;
Learn "XAML and Composition interoperability"). Two traps:

- The new rendering properties (`Scale`, `Translation`, `RotationAngleInDegrees`)
  and the old ones (`RenderTransform`, `Projection`, `Transform3D`) are
  **mutually exclusive per element** — mixing them fails the API call. Pick one
  lane per element; hand-managing a Visual via `ElementCompositionPreview` also
  opts the element out of the new properties (`rendering-interop.md`).
- Composition animates on the compositor's independent thread — that is the whole
  point (immunity to UI-thread jank) — but *creating/starting* animations is
  UI-thread work; do it from the UI thread only.

**Implicit** (trigger-based): an `ImplicitAnimationCollection` on the visual maps
a property name ("Offset", "Opacity") to an animation that runs automatically on
any change — the tool for card reposition/fade choreography with zero call-site
code. **Spring** (physics): `Compositor.CreateSpringVector3Animation()` targeting
`Scale`/`Translation`; tune with `DampingRatio` (< 1 overshoots and settles — the
wheel's open feel; = 1 no overshoot) and `Period` (~50 ms is the documented
starting point). **Expression** (relation): a math string continuously driving
one property from another.

### Pointer-parallax expression

```csharp
var compositor = CompositionTarget.GetCompositorForCurrentThread();
var props = compositor.CreatePropertySet();                 // written from PointerMoved
props.InsertVector3("Pointer", Vector3.Zero);

var exp = compositor.CreateExpressionAnimation(
    "Clamp((props.Pointer - center) * depth, -limit, limit)");
exp.SetReferenceParameter("props", props);
exp.SetVector3Parameter("center", new Vector3(cx, cy, 0));
exp.SetScalarParameter("depth", 0.05f);                     // per-layer depth factor
exp.SetVector3Parameter("limit", new Vector3(24, 24, 0));
exp.Target = "Translation";
layerElement.StartAnimation(exp);
```

The `PointerMoved` handler only writes `props` (UI-thread write, compositor-thread
evaluation) — no per-frame managed animation code. Candidate improvement:
`ElementCompositionPreview.GetPointerPositionPropertySet` (UWP lineage) removes
the UI-thread write entirely — verify its Windows App SDK availability against
Learn before using it. Parallax layers are decorative: `IsHitTestVisible="False"`
and disabled under reduced motion (below).

## Custom radial control input (the Monado wheel pattern)

A composite custom control (segments inside one focusable control) needs all
three input modalities with parity — the contract is
`INTERACTIVE_SHELL_EXPERIENCE.md` §1; the mechanics:

- **Mouse wheel**: handle `UIElement.PointerWheelChanged`; read
  `e.GetCurrentPoint(this).Properties.MouseWheelDelta` — units of WHEEL_DELTA
  = 120 per detent (positive = away from user). Accumulate fractional deltas
  (free-spinning wheels send many small values), advance selection by whole
  detents, and set `e.Handled = true` while the wheel is open so the page never
  scrolls. Note some controls class-handle this event via
  `OnPointerWheelChanged` — in a custom control, override that instead of (or in
  addition to) subscribing.
- **Pointer**: polar hit test from the wheel center
  (`i = round(((atan2(dy,dx) + π/2) mod 2π) / (2π/N)) mod N`, radius-bounded);
  hover selects, click invokes, inner dead-zone click dismisses.
- **Keyboard**: the control is a single tab stop (`IsTabStop = true`); arrows
  cycle the internal selection, Home/End jump, Enter/Space invoke, Esc dismisses
  — the composite-control pattern from Learn "Keyboard accessibility". Draw a
  visible selection/focus indicator as part of the segment rendering; never rely
  on the default focus rect alone for a shaped control.
- **Focus discipline**: open only on explicit invocation; record the previously
  focused element, focus the wheel, restore focus on dismissal. Never open on
  hover; never steal focus from typing.

### AutomationPeer

Custom control deriving from `Control` ⇒ derive the peer from
`FrameworkElementAutomationPeer` and return it from `OnCreateAutomationPeer`
(Learn "Custom automation peers"). Segments are exposed as child peers
(`GetChildrenCore`) each with a localized `Name`; selection changes raise
automation events — check `AutomationPeer.ListenerExists(...)` first, then
`RaiseAutomationEvent`/`RaisePropertyChangedEvent` so Narrator tracks selection.
`AutomationProperties.Name` on the control itself. Narrator verification happens
on Windows only — never claim it from Linux.

## Reduced-motion detection

`Windows.UI.ViewManagement.UISettings.AnimationsEnabled` is the OS switch
(Settings → Accessibility → Visual effects; Learn "Tailoring effects and
experiences"). The `AnimationsEnabledChanged` event was added in SDK 19041 — the
shell targets 19041 but min platform is 17763, so guard the subscription with
`ApiInformation.IsEventPresent` and fall back to read-at-startup. Route every
animation site through one `MotionSettings` service; when animations are off:
decorative loops (pulse/spin/color-cycle/scanline drift) stop entirely,
transitions collapse to short fades or instant, parallax and particle attraction
are disabled. A bare `StartAnimation` on a decorative visual that skips the check
is a review finding.

## Hit-test transparency layering

Rules from `INTERACTIVE_SHELL_EXPERIENCE.md` §4, mechanics here:

- `IsHitTestVisible="False"` on every decorative element (effect overlays, glow
  hosts, parallax layers, background engine controls). Hit-testing requires the
  element to be visible *and* hit-test visible (routed-events model — see the
  PointerWheelChanged remarks on Learn); flipping the switch off makes the layer
  input-invisible while it still renders.
- Never place a hit-testable decorative layer above interactive content; the only
  input-taking overlay is the wheel popup while open (light-dismiss).
- Visuals injected with `ElementCompositionPreview.SetElementChildVisual`
  ("handin" visuals) draw on top of the element and **lack XAML accessibility
  guarantees** (`rendering-interop.md`) — decorative only, sparing, never
  load-bearing for comprehension.
- Fixed z-order: background engine → page content → decorative overlays → wheel
  popup.

## WPF → WinUI porting notes for the recovered seeds

The `docs/ui-xenoblade` seeds (`Components/Panels/HolographicPanel.xaml`,
`CustomControls/MonadoGlowBorder.cs`, `CustomControls/AnimatedProgressRing.cs`,
`Theme/Animations.xaml`) are design vocabulary with defects —
`INTERACTIVE_SHELL_EXPERIENCE.md` §0 has the honest per-file inventory. Porting
rules:

- **No WPF bitmap effects.** `DropShadowEffect` (HolographicPanel's glow) has no
  WinUI equivalent and the old `BitmapEffect` family is long dead. Shadows:
  `ThemeShadow` for standard elevation, or a Composition `DropShadow` on a
  `SpriteVisual` for the glow look (Learn "Composition shadows"). Cost table
  matters: masked shadows and **animated BlurRadius are High cost** — pulse the
  shadow/glow *Opacity*, keep blur radius static. Radial glow halos
  (MonadoGlowBorder's ellipse) become a radial-gradient composition brush on a
  SpriteVisual, or a Win2D-drawn sprite.
- **Storyboard → Composition** for anything continuous or decorative: WPF
  `DoubleAnimation`-on-Opacity loops become `ScalarKeyFrameAnimation` with
  `IterationBehavior.Forever`; rotation loops target `RotationAngleInDegrees`.
  Keep XAML VisualStateManager storyboards only for template state transitions
  where `ThemeResource` re-resolution matters.
- **No `ThicknessAnimation`** in WinUI 3 — the seeds' Margin-based slide-ins port
  to `Translation` animations (compositor-side, layout untouched).
- **No `LinearEase`** anywhere: it isn't a WPF type either (seed defect) — linear
  is a null easing in WPF and a linear easing function in Composition keyframes.
- **Hardcoded colors do not survive**: seeds carry the retired `#00D4FF`; all
  ported treatments take token brushes/colors (`GUI_UPGRADE_PLAN.md` §2), and
  durations/easings take the motion tokens (`INTERACTIVE_SHELL_EXPERIENCE.md`
  §3).
- **UserControl re-parenting hacks** (MonadoGlowBorder's Loaded-time tree
  surgery) become proper templated controls: `Control` subclass, generic.xaml
  template, template parts — the WinUI custom-control pattern the wheel also
  follows.
- Ring/arc drawing (AnimatedProgressRing's intent): Win2D `CanvasPathBuilder` arc
  geometry in a `CanvasControl` (redraw on state change only —
  `rendering-interop.md` control table), not retained-mode Shape hacks; or just
  use WinUI's `ProgressRing` when the platform control suffices.
