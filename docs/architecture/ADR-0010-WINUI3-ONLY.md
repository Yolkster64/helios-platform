# ADR-0010: WinUI 3 Is the Only Active HELIOS Desktop Architecture

Status: Superseded for active product UI by [ADR-0011](ADR-0011-ELECTRON-WORKBENCH.md), 2026-09-26.

The decision below records the previous WinUI direction. The owner now requires
Electron + Forge for the complete HELIOS product interface. Keep the existing
`src/gui` tree, `config/ui/winui3-only.v1.json`, and its cutover validator intact
as scoped legacy-tree and provenance guards until a reviewed archival change.
They do not prohibit `apps/desktop`, validate Electron, or authorize a WinUI
fallback in the new workbench. The prior separate-GUI extraction is reassessed
after Electron parity; repository renaming and production permissions are unchanged.

## Decision

All new HELIOS desktop product work uses:

- C# and .NET 10;
- WinUI 3 through the Windows App SDK;
- `Microsoft.UI.Xaml`;
- `Microsoft.UI.Composition` for blade, aperture, rings, particles, glow, and transitions;
- single-project MSIX by default;
- Windows-hosted build and test jobs.

The active GUI solution lives under `src/gui` during the rename phase and is intended
to move to `Yolkster64/helios-gui` through a reviewed, provenance-preserving extraction.

## Explicitly rejected for active product code

- `<UseWPF>true</UseWPF>`;
- `System.Windows` UI types;
- `PresentationFramework` and `PresentationCore`;
- `Windows.UI.Xaml` / UWP;
- PowerShell `Add-Type` GUI hosts;
- a WPF bridge, fallback shell, animation host, or migration layer.

## Legacy exception

The repository currently contains a root `HELIOS.Platform.csproj` with WPF enabled.
It is already excluded from the portable solution and documented as non-compiling
legacy debt. This ADR does not pretend that file vanished. It creates one temporary,
explicit baseline entry so CI blocks every *new* WPF dependency while HC-002 removes
or archives the legacy root project through a separate reviewed change.

Recovered `.crdownload` files and WPF-era design prototypes remain inert evidence.
They are never compiled, packaged, executed, or imported into the WinUI solution.

## Enforcement

`validate_yolkster_cutover.py` validates the active GUI tree and the bounded legacy
baseline. A Windows job must compile `src/gui/HELIOS.Shell.sln`. The contract fails if
new WPF/UWP references appear outside the baseline or an active GUI project lacks
`<UseWinUI>true</UseWinUI>`.
