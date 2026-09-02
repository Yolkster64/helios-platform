# HELIOS Shell theme packs

`Tokens.xaml` is the **single canonical color authority** for all HELIOS UI
(decision record: `docs/architecture/GUI_UPGRADE_PLAN.md` section 2). It is the
**Monado** pack (navy + cyan accent) and is the only pack merged by `App.xaml` today.

Sibling packs carry **identical semantic keys**, so pages never know which pack is
active — every page consumes tokens exclusively via `{ThemeResource}`:

| Pack | File | Character |
|---|---|---|
| Monado (default) | `Tokens.xaml` | Cyan accent on the Monado-navy elevation ramp |
| GitHub Dark | `Tokens.GitHubDark.xaml` | The shell's pre-P1 live palette, preserved as an alternate |
| Solar Light | `Tokens.SolarLight.xaml` | Light-first pack from MonadoColorPalette's light set |
| High Contrast | `Tokens.HighContrast.xaml` | Every token maps to a system color |

Each pack is a full `Default`/`Light`/`HighContrast` theme-dictionary set.
`Typography.xaml` is the type ramp (Display/Headline/Title/Body/Label `TextBlock`
styles); its foregrounds consume only semantic tokens, never literal colors.

## Selection and persistence

Per-profile pack selection **persists in local app settings**; the selection UI and
the runtime pack-swap path land in P6 (`GUI_UPGRADE_PLAN.md` section 3). The swap
contract: replace the merged token dictionary, then call
`Helpers/ReadinessVisuals.Refresh(...)` — no brush may survive a pack switch stale.

## Contrast policy (measured, never inherited)

Every text-token/surface-token pair in every pack was verified with computed WCAG 2.x
relative-luminance ratios; body-text tokens hold at least 4.5:1 on every surface token
in their dictionary. The worst-case ratio is documented inline next to each token in
the pack files. High Contrast ratios are OS-defined and deliberately not claimed.
Report-doc compliance claims (`DARK_MODE_GUIDE.md`, `ACCESSIBILITY_COMPLIANCE_REPORT`)
are unverified and must never be cited as evidence.
