# Dynamic Background Engine (design of record)

The living, AI-aware ambient background for the HELIOS shell (WinUI 3,
`src/gui/HELIOS.Shell`). This document is a DESIGN plus a phased plan — none of it is
implemented; nothing here compiles on Linux CI. The shell targets
`net8.0-windows10.0.19041.0` on Windows App SDK 1.6 today (`src/gui/README.md`) and
moves to net10/11 as WASDK majors land; every phase below builds only via
`dotnet build src/gui/HELIOS.Shell.sln -c Debug -p:Platform=x64` on Windows, and PR
bodies must say so per `GUI_UPGRADE_PLAN.md` §3.

Companions: `GUI_UPGRADE_PLAN.md` (P6 is the phase this engine fills; §2 is the
canonical palette), `GUI_THEME_ANALYSIS.md` ("Interop boundary"),
`.claude/skills/cpp-performance/SKILL.md` + `references/rendering-gpu.md` +
`references/particle-systems.md` (the native lane), and
`.claude/skills/winui3-shell/references/rendering-interop.md` (the managed seam).
Consuming agents: `render-engineer` (native spoke), `ui-designer` (managed side),
gated by `winui3-reviewer`, `cpp-perf-reviewer`, `gui-perf-profiler`.

## 1. Vision & tiers

An ambient scene behind the shell's content — behind the NavigationView, never
competing with it:

- **Day/night cycle.** Sun/moon arc position derived from the local clock (season
  adjusts day length; exact sunrise/sunset comes from the weather source once BG3
  wires it). Dawn/dusk/day/night are palette lerps anchored on the canonical
  `Tokens.xaml` palette from `GUI_UPGRADE_PLAN.md` §2 — the Monado navy `#0A1428`
  surface ramp and `#00D9FF` accent, with the optional `#FFD700` gold highlight
  reserved for glow/celebration moments. The engine reads token colors at startup and
  on `ActualThemeChanged` and lerps in its own parameter space; it never introduces
  literal colors outside `Tokens.xaml` (any new anchor tokens the lerp needs land in
  `Tokens.xaml` under `theme-designer` ownership).
- **Weather layers.** Wind-driven particle drift, rain, snow — parameterized by real
  local weather when available (§3), by season/clock heuristics otherwise.
- **Fire/ember particles** for the Monado glow accents — slow-rising embers near
  accent surfaces, the particle vocabulary of the recovered
  `docs/ui-xenoblade/Shaders/ParticleShader.hlsl`.
- **Scanline/holo overlays.** Port targets are the three recovered HLSL files
  (`docs/ui-xenoblade/Shaders/GlowShader.hlsl`, `ParticleShader.hlsl`,
  `ScanLineShader.hlsl`). They are design seeds, not shippable shaders: all three are
  pixel-shader fragments with no vertex/compute stage, `ParticleShader.hlsl` declares
  a sim (`Particle` struct, gravity/damping constants) it never executes, and two of
  them hardcode the WPF-era `#00D4FF` cyan that §2 of the upgrade plan retired. See
  `particle-systems.md` for the honest inventory and what a port changes.

### Performance tiers

| Tier | Renderer | Content | Scale |
|---|---|---|---|
| **Off** | None — a static XAML gradient brush from tokens | Day/night gradient recomputed at most once a minute (a timer tick that sets brush stops, not a render loop) | 0 particles |
| **Ambient** | Managed Win2D `CanvasAnimatedControl` | Gradient + drift/ember particles, scanline overlay as a cheap Win2D effect | A few hundred particles (TARGET: ≤ 512), GPU TARGET ≤ 2 ms/frame |
| **Full** | Native D3D12 spoke rendering into a `SwapChainPanel` | Everything: GPU compute particle sim, weather layers, ported glow/scanline passes | Tens of thousands of particles, GPU-resident |

Tier selection: user setting first (Off is always honored absolutely), then automatic
degradation — on battery / energy-saver, under thermal pressure, or on low-end
adapters (WARP / no dedicated VRAM) the engine steps Full → Ambient → Off. Candidate
APIs for the checks: `Windows.System.Power.PowerManager` (energy-saver/battery
status) and DXGI adapter descriptors — candidates to verify against Microsoft Learn
at implementation time, per the reference-file convention. Degradation is one-way
within a session unless the user re-selects; no oscillation.

## 2. Architecture along the established seam

The split is the one fixed by `rendering-gpu.md` and `rendering-interop.md`: **C#
decides when to redraw and owns the `SwapChainPanel` XAML element; C++ owns the
device, queue, and command lists.** Provider/scene data crosses as plain caller-owned
buffers, exactly like `src/ai/HELIOS.AIHub.Native/helios_aihub_native.h` does today.

### Managed side (`src/gui/HELIOS.Shell`, owner: ui-designer)

- **Off tier**: pure XAML — a `LinearGradientBrush` whose stops come from theme
  tokens. No Win2D, no native dependency, no render loop.
- **Ambient tier**: one Win2D `CanvasAnimatedControl` (continuously changing content
  → the swap-chain-backed control per `rendering-interop.md`). Resources created in
  `CreateResources` (re-runnable for device-lost), never per-`Draw`; zero per-frame
  managed allocations in `Update`/`Draw` (gui-perf-profiler rule 1).
- **Full tier**: a `SwapChainPanel` the shell owns; the native spoke renders into it.
  `SetSwapChain` runs on the UI thread (and again after `ResizeBuffers`); rendering
  and `Present` stay on the spoke's render thread — the UI-thread obligations are
  exactly the XAML touchpoints listed in `rendering-interop.md`.
- **Theme/token integration**: the engine's palette inputs are resolved from the
  token dictionary on the UI thread at startup and on `ActualThemeChanged`, then
  passed down as plain RGBA floats in the parameter block. HighContrast theme forces
  the Off tier (an animated background under a contrast theme is an accessibility
  regression, not a feature).
- **Visibility/occlusion pausing — NEVER burn frames when minimized.** Window
  minimized, hidden, or deactivated-and-occluded ⇒ `CanvasAnimatedControl.Paused =
  true` (Ambient) or stop ticking the spoke entirely (Full). The sim clock freezes
  with the render loop and resnaps to wall-clock time on resume (the day/night phase
  is recomputed from the clock, so nothing drifts). A backgrounded shell must profile
  at 0% GPU for this engine.

### Native spoke (new project, owner: render-engineer)

Candidate location: `src/gui/HELIOS.Shell.Native/` inside `HELIOS.Shell.sln`
(Windows-only, like everything under `src/gui/`; the root csproj's existing
`src/gui/**` glob guards cover its C# stubs — `GUI_UPGRADE_PLAN.md` §6).

- **Particle simulation**: structure-of-arrays layout, SIMD update loops (AVX2
  baseline with the scalar fallback + runtime dispatch pattern from
  `cpp-performance/SKILL.md`; note the platform direction — .NET 11 raises the
  managed x64 instruction-set baseline into the AVX2 era, so an AVX2 native baseline
  matches where the shell is heading — verify the exact floor when the shell actually
  retargets). Full tier moves the sim to GPU compute shaders with GPU-resident state
  and indirect draw; see `particle-systems.md` for both lanes.
- **Fixed-timestep sim + interpolated render**: the simulation steps at a fixed dt;
  render interpolates between the last two sim states. Frame-rate changes alter
  smoothness, never physics.
- **Flat C ABI** (the `SKILL.md` "Interop boundary (STRICT)" rules verbatim: no C++
  types, exceptions, or STL across the boundary; status codes, never throw; consumed
  via source-generated `LibraryImport`; the spoke never calls back into managed code,
  never performs I/O, never reads `config/aihub.json`, never talks to another spoke):

```c
/* Pattern per helios_aihub_native.h — status codes, caller-owned memory, noexcept
 * boundary; bump the ABI version constant together on both sides on any change. */
typedef struct helios_bg_params {
    float    wind[2];            /* wind vector, scene units/sec            */
    float    emission_embers;    /* particles/sec                           */
    float    emission_weather;   /* particles/sec (rain/snow)               */
    int32_t  weather_kind;       /* 0 clear, 1 rain, 2 snow (enum, stable)  */
    float    palette[4][4];      /* RGBA anchors resolved from Tokens.xaml  */
    float    time_of_day;        /* 0..1 fraction of the local day          */
    float    intensity;          /* 0..1 overall scene energy               */
} helios_bg_params;

HELIOS_API int32_t helios_bg_abi_version(void);
HELIOS_API helios_status helios_bg_init(const helios_bg_init_desc* desc, void** out_handle);
HELIOS_API helios_status helios_bg_resize(void* handle, uint32_t width, uint32_t height,
                                          float composition_scale_x, float composition_scale_y);
HELIOS_API helios_status helios_bg_tick(void* handle, const helios_bg_params* params,
                                        double wall_clock_seconds);
HELIOS_API helios_status helios_bg_render(void* handle);
HELIOS_API helios_status helios_bg_teardown(void* handle);
```

  `helios_bg_tick` copies the parameter block into internal state during the call —
  the spoke never retains a caller pointer past return, mirroring the
  `helios_aihub_native.h` memory contract. The C# side double-buffers the block so a
  tick in flight never observes a torn write (`particle-systems.md`, "Memory").
  Swap-chain wiring: the spoke creates device/queue/swap chain
  (`CreateSwapChainForComposition` per `rendering-gpu.md`) and returns the
  `IDXGISwapChain*` as an opaque handle for the shell to pass to
  `ISwapChainPanelNative::SetSwapChain` on the UI thread. If the opaque-handle path
  proves awkward in practice, the sanctioned fallback is the `SKILL.md` alternative —
  a C++/WinRT runtime class consumed as a `.winmd` — with every other rule (sole C#
  caller, no I/O, no spoke-to-spoke) unchanged.

## 3. The "smart AI" layer, honestly scoped

The AI chooses **parameters**; the engine renders **deterministically**. No
generative frames, ever. Budget: the AI layer is allowed exactly **zero ms on the
frame path** — everything below runs on background tasks that publish an immutable
snapshot the sim thread reads.

1. **Local heuristics first (always available).** Clock → day phase; date → season;
   season+phase → default palette lerp, wind, and emission defaults. This layer has
   no dependencies and is the permanent fallback.
2. **Real weather, one optional keyless API.** Open-Meteo is the named no-key option
   (free, no API key; an external service — a non-repo candidate until BG3 wires it).
   Never a paid or keyed weather service. Poll ≤ 1 request / 15 minutes, cached with
   stale-on-failure semantics (§4 network budget; contract details in
   `particle-systems.md`, "Network"). No location permission → heuristics only.
3. **Advisory hub hook (BG5).** A small prompt through the hub — `helios-ai route
   general_query` (task chain from `config/aihub.json`) or `POST /v1/route` on
   `helios-ai-api` — can suggest a scene mood (calm/focused/celebratory intensity
   nudge) from recent activity via the learning-store insights (`GET /v1/insights`).
   Rules, non-negotiable:
   - **Advisory only**: the response adjusts `intensity`/palette bias within clamped
     ranges; it can never select a renderer, tier, or resource load.
   - **Cached and rate-limited**: ≤ 1 hub call/hour, result cached; repeated failures
     back off to daily.
   - **Never blocking**: fired from a background task; the render path reads the last
     published snapshot. Hub down, slow, or absent ⇒ heuristics, silently.
   - Malformed/out-of-range responses are discarded — the parser clamps and never
     trusts the model with more than a mood enum and a 0..1 intensity.

## 4. Performance budgets & gates

All numbers below are **TARGETS** — design budgets to be verified with the debug perf
overlay from `GUI_UPGRADE_PLAN.md` P3 (the gui-perf-profiler's instrument). Per the
provenance rule in `GUI_UPGRADE_PLAN.md` §1, the repo's old "60+ FPS" report docs are
the anti-pattern: **no FPS or frame-cost claim may appear in any PR, doc, or report
for this engine unless the overlay (or PIX/VS frame analysis) measured it on real
hardware.** Budgets are commitments to measure against, not achievements.

| Budget (TARGET) | Off | Ambient | Full |
|---|---|---|---|
| CPU per frame | 0 (no loop) | ≤ 1 ms | ≤ 1 ms (sim on GPU) |
| GPU per frame | 0 | ≤ 2 ms | ≤ 4 ms |
| Working set delta | ~0 | ≤ 32 MB | ≤ 128 MB |
| Per-frame GC allocations (managed side) | 0 | **0** (gui-perf-profiler rule: nothing allocated in `Update`/`Draw`) | **0** (tick marshaling must not allocate) |
| Minimized/hidden | 0 everything | 0 everything | 0 everything |

- The engine is a background: its combined budget must leave the foreground UI its
  full frame. If the overlay shows the shell missing 60 Hz vsync with the engine on,
  the engine degrades a tier — the dashboard always wins.
- **Measurement plan**: land the P3 debug overlay first (FPS, frame-time histogram,
  managed allocation counter — ported from
  `src/gui/MonadoBlade.GUI/Systems/{FpsCounter,FrameTimeHistogram,MemoryProfiler}.xaml`
  per `gui-perf-profiler.md`); every BG phase's PR states overlay results the human
  measured on Windows, or states that measurement is pending. Native-tier GPU cost is
  measured with PIX markers around the sim and render passes (`rendering-gpu.md`,
  "Debug layers, DRED, PIX markers").
- **Network budget**: weather poll ≤ 1/15 min, cached; hub mood call ≤ 1/hour,
  cached. Zero network on the frame path; zero network when Off.
- Zero-allocation rule applies to the steady state; pools are allocated once at tier
  init (`particle-systems.md`, "Memory").

## 5. Phased plan

Each phase is one reviewable PR; every PR carries the honest "compiles on Windows
only, parse-level checks on Linux" note per `GUI_UPGRADE_PLAN.md` §3. Gates listed
are in addition to the normal review wave.

| Phase | Scope | Owner | Gates |
|---|---|---|---|
| **BG1** | Static gradient + day/night palette lerp. Managed only, Off tier is the whole feature; ships with/behind P1 tokens (needs the canonical `Tokens.xaml`). Settings toggle (Off/Ambient/Full enum, only Off functional). | ui-designer (tokens: theme-designer) | winui3-reviewer |
| **BG2** | Win2D ambient particles — wind drift + Monado embers, Ambient tier, `CanvasAnimatedControl`, visibility pausing, tier auto-degrade skeleton. | ui-designer | winui3-reviewer, gui-perf-profiler |
| **BG3** | Weather layers (rain/snow) + Open-Meteo wiring with the caching contract; sunrise/sunset replaces the clock approximation. | ui-designer (managed sim), render-engineer consulted on layout | winui3-reviewer, gui-perf-profiler |
| **BG4** | Native spoke Full tier: D3D12 device/queue/swap chain into `SwapChainPanel`, GPU compute particle sim, port the three recovered HLSL shaders into real passes (fixing what §1 lists — see `particle-systems.md`). | render-engineer | cpp-perf-reviewer, gui-perf-profiler, winui3-reviewer (shell touchpoints) |
| **BG5** | AI mood hook (advisory, §3 rules), settings surface for it (default off). | ui-designer + render-engineer (parameter plumbing) | winui3-reviewer, gui-perf-profiler |

Sequencing: BG1 → BG2 → BG3 → BG4 → BG5; BG4 additionally needs the P3 overlay
landed (nothing native ships without the instrument that measures it). BG2/BG3 are
worthwhile even if BG4 never ships — Ambient is the default tier; Full is the
enthusiast tier.
