# GUI Finish & Upgrade Plan

Plan of record for completing the WinUI 3 shell (`src/gui/HELIOS.Shell`), consolidating
the theme system, and producing the platform's first real design assets. Grounded in a
full inventory of every UI artifact in the repo (2026-08); companion to
`GUI_THEME_ANALYSIS.md` (direction) and `ROADMAP_MULTI_LLM.md` PR6 (the WinUI tranche).

## 1. Where the GUI actually stands

- **Live shell**: `src/gui/HELIOS.Shell` — ~375 LOC, builds only via
  `src/gui/HELIOS.Shell.sln` on Windows. **1 of 3 planned pages** exists
  (`Views/AIHubPage.xaml`, the provider dashboard); of its planned card elements only
  the provider table is done. No Win2D reference yet. `Themes/Tokens.xaml` has 30 keys.
- **Known defect**: `Helpers/ReadinessVisuals.cs` resolves brushes at bind time; a
  theme switch leaves stale brushes until the next refresh (self-documented in the
  file as a PR6 polish item).
- **Blocker for the metrics cards**: the hub API has no metrics endpoint. The orphaned
  WPF `MonadoBlade.GUI/AIHubWindow.cs` models exactly the shape needed —
  `AverageLatency`, `SuccessRate`, `TokensUsed`, `CostPerMillion` per provider — but
  nothing on `helios-ai-api` serves it.
- **Zero image assets in the entire repository** — no app icon, no logo, nothing under
  any `Assets/` directory. The shell currently ships with default WinUI branding.
- **Six conflicting palettes** exist across live code, mockups, and reports (§2).
- **Recovered material**: `docs/ui-xenoblade` was a stray *bare git store* checked
  into the repo; 15 of its 27 files (the entire `Theme/`, `Components/`,
  `CustomControls/`, `Shaders/` trees) existed only inside its object store. They are
  now extracted as plain reference files and the store internals are deleted.

### Source-of-truth map (what to mine, from where)

| Artifact | Location | Value |
|---|---|---|
| Fullest color palette | `src/gui/MonadoBlade.GUI/Themes/MonadoColorPalette.xaml` | Complete ramp: accents, surfaces, borders, light mode, status, gradients |
| Typography ramp | `src/gui/MonadoBlade.GUI/Styles/Typography.xaml` | Full Material-3-style type scale with LineHeight/LetterSpacing — port to Fluent ramp |
| KPI card layout | `docs/WinUI3-Design/Presentation/DashboardPage.xaml` | 3-up metric card grid, directly reusable for AIHub + Fleet pages |
| Glow/holo component treatments | `docs/ui-xenoblade/Components/`, `CustomControls/` (recovered) | GlowButton, ServiceCard, HolographicPanel, MonadoGlowBorder, AnimatedProgressRing |
| Effect shaders | `docs/ui-xenoblade/Shaders/*.hlsl` (recovered) | Glow / particle / scanline — candidates for Win2D or the native rendering spoke |
| Wizard flow | `src/core/.../Phase10/BuilderUI/` | Step-wizard layout, the only non-duplicated layout idea in `src/core` |
| Telemetry widgets | `MonadoBlade.GUI/Systems/{FpsCounter,MemoryProfiler,FrameTimeHistogram}.xaml` | Perf overlay layouts for the profiling lane |

Provenance rule (extends the CLAUDE.md rule on `*_REPORT` docs): the root
`PHASE*`/`DARK_MODE_GUIDE`/`ACCESSIBILITY_COMPLIANCE_REPORT` docs and the in-tree
`REFACTORING_REPORT`/`COMPLETION_SUMMARY`/`DELIVERY_REPORT` files are ChatGPT-era
spec-dumps that document features which were never shipped (one claims "0 errors" on a
project with 14,912 warnings; another documents 27 files while shipping 12). Mine them
for *intent*, never cite them as state.

## 2. The palette decision (canonical tokens)

Six "HELIOS cyan" palettes are in play; the live shell inherited GitHub-dark surfaces
from a mockup rather than the Xenoblade-lineage navy of the design system:

| Source | Accent | Background | Status green |
|---|---|---|---|
| `HELIOS.Shell/Themes/Tokens.xaml` (**live**) | `#00D9FF` | `#0D1117` | `#3DDC97` |
| `docs/WinUI3-Design/.../HELIOSTheme.xaml` | `#00D9FF` | `#0D0D0D` | `#00C4A0` |
| `MonadoBlade.GUI/Themes/MonadoColorPalette.xaml` | `#00D9FF` | `#0A1428` | `#00FF41` |
| `docs/ui-xenoblade/Theme/Colors.xaml` (recovered) | `#00D4FF` | `#0A0E27` | `#00FF00` |
| `src/core/.../XenbladTheme.xaml` | `#00D4FF` | `#0F0F23` | `#4DFF00` |
| `DARK_MODE_GUIDE.md` (report-doc) | `#50C8FF` | `#0F0F14` | `#4CAF50` |

**Decision:**

- **Accent: `#00D9FF`** — three of four code artifacts agree; `#00D4FF` is the older
  WPF-era value; `#50C8FF` exists only in a report doc.
- **Dark surface: `#0A1428` (Monado navy)** with the MonadoColorPalette elevation ramp
  (`#0F1D2E` secondary, `#1A2838`/`#253548` surfaces, `#3A5A78`/`#1E3A4F` borders).
  The live `#0D1117` is GitHub's dark theme, an undocumented softening; the navy is
  the design system. Contrast of body text tokens must be re-checked (WCAG AA 4.5:1)
  when swapping — treat the DARK_MODE_GUIDE's "AAA verified" claims as unverified.
- **Status colors: keep the live shell's** `#3DDC97` green (the pure `#00FF00`/
  `#00FF41` greens fail contrast on navy and read as terminal-retro), keep live
  warning/error unless the theme-designer pass proves better tokens.
- **Gold accent `#FFD700`** (unique to the recovered Xenoblade palette) enters as an
  *optional highlight token* (`AccentGoldColor`) for the glow/celebration treatments
  only — never as a second primary.
- Light theme comes from MonadoColorPalette's light set (`#F5F7FA`/`#FFFFFF`/`#D0D8E0`).

All of this lands as **one canonical `Tokens.xaml`** (Light/Dark/HighContrast
dictionaries, semantic names, no literal colors anywhere else). Every other palette
file gains a header comment pointing at Tokens.xaml as the authority.

## 3. Upgrade phases

Each phase is one reviewable PR. The shell compiles only on Windows
(`dotnet build src/gui/HELIOS.Shell.sln -c Debug -p:Platform=x64`); Linux-side
verification is parse-level (well-formed XML, C# syntax, x:Bind/ThemeResource greps) —
every GUI PR must say so honestly in its body.

- **P1 — Token consolidation + type ramp.** Rebuild `Tokens.xaml` per §2; port
  `Typography.xaml`'s type scale onto the Fluent ramp (map Display/Headline/Title/
  Body/Label to `TextBlock` styles); fix `ReadinessVisuals.cs` stale-brush defect
  (resolve via `ThemeResource` lookup per invocation or listen to
  `ActualThemeChanged`). Owner: theme-designer agent, gate: winui3-reviewer.
- **P2 — Hub metrics REST seam.** `GET /v1/metrics` on `helios-ai-api`: per-provider
  `averageLatencyMs`, `successRate`, `tokensUsed`, `costPerMillion` aggregated from
  the learning store (`/v1/learning` records; advisory data is fine here — it is
  telemetry display, not routing). Loopback-only like the rest of `/v1/*`. This is
  ordinary Linux-CI C# with tests — it unblocks every dashboard card. Owner:
  api-creator skill flow, normal `HELIOS.sln` gate.
- **P3 — AIHub page completion.** Metrics cards (3-up KPI grid from
  `DashboardPage.xaml`) bound to `/v1/metrics`; Win2D `CanvasControl` sparklines
  (managed side only, per the rendering seam); wire into the existing
  `AIHubViewModel` refresh loop. Owner: ui-designer, gate: winui3-reviewer +
  gui-perf-profiler (frame cost of sparkline redraw).
- **P4 — Routing page.** Read-only grid of the task-routing table
  (`/v1/routing`), chain visualization per task type, provider readiness badges
  reusing `ReadinessVisuals`. Owner: ui-designer.
- **P5 — Fleet page.** KPI layout from DashboardPage + fleet status via
  `helios_fleet_status_get`'s REST twin (`/v1/*` addition if needed); pool/lane
  cards with the enforced `maxConcurrentLanes` caps surfaced. Owner: ui-designer.
- **P6 — Effects polish (opt-in).** Port GlowButton/HolographicPanel/MonadoGlowBorder
  treatments to WinUI 3 Composition; evaluate recovered HLSL shaders as Win2D custom
  effects vs native-spoke work per `rendering-gpu.md`; theme settings page
  (from `MonadoBlade.GUI/Views/ThemeSettings.xaml`); wizard flow only if a real
  setup scenario needs it. Owner: ui-designer + cpp lane, gates: winui3-reviewer,
  cpp-perf-reviewer, gui-perf-profiler.

## 4. Adobe design-asset track (parallel to P1)

The repo has no image assets at all. Using the Adobe MCP lane
(`adobe_mandatory_init` first, always):

1. **App icon** — HELIOS sun/monado mark on the `#00D9FF`-on-navy palette; deliver the
   WinUI icon set (Square44x44Logo, Square150x150Logo, StoreLogo scales) into
   `src/gui/HELIOS.Shell/Assets/` and reference from the csproj/manifest.
2. **Theme board** — one fixed-canvas board rendering §2's canonical tokens (accents,
   surface ramp, status set, gold highlight, type scale) as the visual reference the
   agents design against; committed under `docs/architecture/assets/`.
3. Optional: page mock renders for P4/P5 before XAML is written.

Adobe's visual-design skill covers fixed-canvas assets (icons, boards) — exactly these
deliverables; responsive app UI itself stays in XAML, never authored as Adobe HTML.

## 5. Agent roster (who does what)

| Agent | Role in this plan |
|---|---|
| `ui-designer` (existing) | Authors pages/XAML/view models (P3–P6); drafts markup through the hub's codegen lane, reconciles against the winui3-shell skill |
| `winui3-reviewer` (existing) | Gate on every GUI PR: threading, x:Bind correctness, theme regressions |
| `theme-designer` (new) | Owns Tokens.xaml and §2's decisions; runs the Adobe asset track; keeps every palette artifact pointed at the canonical tokens |
| `ux-reviewer` (new) | Reviews flows and information architecture against the three-page model; accessibility (contrast, keyboard, narrator) with *measured* claims only |
| `gui-perf-profiler` (new) | Owns frame-cost verification for Win2D/Composition work; ports MonadoBlade's FPS/frame-time widgets into a debug overlay when P3 lands |
| `cloudshell-bootstrapper` (existing) | Setup lane: Windows dev-box readiness for `HELIOS.Shell.sln` builds |
| `cpp-perf-reviewer` (existing) | Gate if P6 crosses into the native rendering spoke |

Dispatch model: pages and features fan out to `ui-designer` per phase; every PR gets
`winui3-reviewer` + `ux-reviewer` passes before the normal Codex review wave; the
profiler attaches wherever a `CanvasControl` or Composition animation appears.

## 6. Sequencing and gates

```
P1 tokens ──┬─► P3 AIHub page ─► P4 Routing ─► P5 Fleet ─► P6 effects
P2 REST  ───┘        ▲
Adobe assets ────────┘ (icon lands with first page PR that ships Assets/)
```

- P1 and P2 are independent and can run in parallel; P3 needs both.
- Every phase: parse-level Linux checks + honest "compiles on Windows only" PR note;
  P2 alone carries normal CI (`HELIOS.sln` build + tests).
- Root-csproj glob guards (`Compile Remove`/`Page Remove` for `src/gui/**` and
  `docs/**`) must survive every PR — they are the reason the broken WPF root project
  stays inert.
