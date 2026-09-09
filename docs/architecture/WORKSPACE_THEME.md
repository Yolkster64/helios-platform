# Workspace theme: Tokens.xaml to VS Code, the devcontainer, and Pages

The HELIOS colour identity has one authority: `src/gui/HELIOS.Shell/Themes/Tokens.xaml`,
the Monado token pack (decision record `GUI_UPGRADE_PLAN.md` section 2; direction
`GUI_THEME_ANALYSIS.md`, "Theme system"; pack rules `src/gui/HELIOS.Shell/Themes/README.md`).
This document derives the editor and container chrome from that file so the workspace
a contributor opens looks like the shell they are building. It is a derivation, not a
second palette: every hex value below is a literal of `Tokens.xaml`, and
`scripts/verify/theme-contrast.py` fails if one is not.

The shell's `Default` dictionary (WinUI's dark) feeds the dark scheme; its `Light`
dictionary feeds the light scheme. The sibling packs (`Tokens.GitHubDark.xaml`,
`Tokens.SolarLight.xaml`, `Tokens.HighContrast.xaml`) are not mapped: the workspace
follows the default pack, and `HighContrast` is left to the operating system on purpose.

## Where the tokens flow

```text
src/gui/HELIOS.Shell/Themes/Tokens.xaml            (canonical; read-only for this lane)
  |
  |-- WinUI 3 shell ........ App.xaml merges the pack; pages consume {ThemeResource}
  |                          keys only (no literal colour outside Themes/Tokens*.xaml)
  |
  |-- VS Code .............. workspace.code-workspace
  |                          settings.workbench.colorCustomizations (theme-scoped blocks)
  |                          + window.title, files.exclude, extension recommendations
  |
  |-- Codespaces / Dev Containers
  |                          .devcontainer/devcontainer.json
  |                          customizations.vscode.settings: the identical block
  |                          (theme-contrast.py fails on any drift between the two)
  |
  '-- GitHub Pages dashboard  the github-control lane's Pages manifest takes the hex
                              table below as its colour source; nothing here implements it
```

| Consumer | File | What it takes | Owner |
| --- | --- | --- | --- |
| WinUI 3 shell | `src/gui/HELIOS.Shell/Themes/Tokens.xaml` | The semantic brushes, per theme dictionary | GUI lane (winui3-shell) |
| VS Code (local clone) | `workspace.code-workspace` | `workbench.colorCustomizations`, `window.title`, `files.exclude` | this document |
| Codespaces / Dev Containers | `.devcontainer/devcontainer.json` | The same `workbench.colorCustomizations` block under `customizations.vscode.settings` | this document |
| GitHub Pages dashboard | the github-control lane's Pages manifest | The token-to-hex table below | github-control lane (not implemented here) |

## How the chrome is applied: theme-scoped, never forced

`workbench.colorTheme` is not set by the repository; the contributor's own theme stays.
The customizations are declared under VS Code theme-scope keys, so they apply only
while a matching theme is active:

| Scope key | Draws from | Matches |
| --- | --- | --- |
| `[Default Dark Modern][Default Dark+][Dark (Visual Studio)][Visual Studio Dark][Abyss][Kimbie Dark][Monokai][Monokai Dimmed][Red][Solarized Dark][Tomorrow Night Blue]` | `Tokens.xaml` `Default` | The eleven built-in ordinary dark themes, by name (VS Code's default **Default Dark Modern** included); add another dark theme's name to the key to opt it in |
| `[Default Light Modern][Default Light+][Light (Visual Studio)][Quiet Light][Solarized Light]` | `Tokens.xaml` `Light` | The five built-in light themes; add another light theme's name to the key to opt it in |

Consequences worth knowing:

- Dark is the default experience because a fresh VS Code uses Default Dark Modern.
- The high-contrast themes (`Default High Contrast`, `Default High Contrast Light`) are in
  neither scope, matching the shell's rule that user contrast themes win. That is why the dark
  key names its themes instead of matching `[*Dark*]`: a wildcard also matches
  `Default High Contrast` and any third-party high-contrast theme whose name contains "Dark",
  and would replace the accessibility colours those themes exist to provide.
- One setting disables everything: choose a theme outside both scopes. Adding
  `"workbench.colorCustomizations": {}` to user settings does **not** cancel the block,
  because VS Code merges object settings across scopes and workspace or remote values
  outrank user values. Locally, opening the folder (`code .`) instead of the
  `.code-workspace` file also drops the block; in a container the devcontainer spec
  applies the block as default values in the machine-scope settings file, which
  **Preferences: Open Remote Settings (JSON)** opens for editing.
- `editor.background` / `editor.foreground` are part of the scheme. Because the block
  is theme-scoped, a dark theme's syntax colours land on `#0A1428` and a light theme's
  on `#F5F7FA`, both close to the backgrounds those syntax colours were designed for.

## Palette mapping, dark (Tokens.xaml `Default`)

| Token | Hex | Role in the shell | VS Code keys |
| --- | --- | --- | --- |
| `SurfaceBrush` | `#0A1428` | Base surface | `titleBar.activeBackground`, `editor.background`, `tab.activeBackground`, `breadcrumb.background`, `panel.background`, `terminal.background`, `statusBar.noFolderBackground`, `terminal.ansiBlack` |
| `TextOnAccentBrush` | `#0A1428` | Text on the accent fill (same value as `SurfaceBrush`) | `activityBarBadge.foreground`, `badge.foreground`, `button.foreground`, `statusBarItem.remoteForeground`, `statusBarItem.errorForeground`, `statusBarItem.warningForeground`, `statusBar.debuggingForeground` |
| `SurfaceSecondaryBrush` | `#0F1D2E` | Second surface step | `activityBar.background`, `sideBar.background`, `statusBar.background`, `titleBar.inactiveBackground`, `editorGroupHeader.tabsBackground`, `tab.inactiveBackground`, `editor.lineHighlightBackground` |
| `CardSurfaceBrush` | `#1A2838` | Cards, inputs, popups | `sideBarSectionHeader.background`, `editorWidget.background`, `input.background`, `dropdown.background`, `quickInput.background`, `menu.background`, `notifications.background`, `list.inactiveSelectionBackground`, `list.hoverBackground` |
| `SurfaceElevatedBrush` | `#253548` | Highest surface; selection fills | `list.activeSelectionBackground`, `editor.selectionBackground`, `terminal.selectionBackground`, `menu.selectionBackground`, `quickInputList.focusBackground`, `button.secondaryBackground` |
| `CardStrokeBrush` | `#1E3A4F` | Dividers | `titleBar.border`, `activityBar.border`, `sideBar.border`, `sideBarSectionHeader.border`, `tab.border`, `statusBar.border`, `panel.border`, `terminal.border`, `menu.border`, `notifications.border` |
| `BorderStrongBrush` | `#3A5A78` | Emphasised borders | `input.border`, `dropdown.border`, `editorWidget.border` |
| `TextPrimaryBrush` | `#E8F1F8` | Body text | `titleBar.activeForeground`, `sideBar.foreground`, `sideBarTitle.foreground`, `sideBarSectionHeader.foreground`, `editor.foreground`, `editorLineNumber.activeForeground`, `editorWidget.foreground`, `tab.activeForeground`, `breadcrumb.focusForeground`, `statusBar.foreground`, `list.activeSelectionForeground`, `list.inactiveSelectionForeground`, `list.hoverForeground`, `input.foreground`, `dropdown.foreground`, `quickInput.foreground`, `menu.foreground`, `menu.selectionForeground`, `notifications.foreground`, `panelTitle.activeForeground`, `button.secondaryForeground`, `button.hoverBackground` (inverted hover), `terminal.foreground`, `terminal.ansiWhite`, `terminal.ansiBrightWhite` |
| `TextSecondaryBrush` | `#8FA3B8` | Secondary text | `titleBar.inactiveForeground`, `activityBar.inactiveForeground`, `descriptionForeground`, `editorLineNumber.foreground`, `tab.inactiveForeground`, `breadcrumb.foreground`, `input.placeholderForeground`, `panelTitle.inactiveForeground`, `terminal.ansiBlue` |
| `HeliosAccentBrush` | `#00D9FF` | The one accent | `activityBar.foreground`, `activityBar.activeBorder`, `activityBarBadge.background`, `badge.background`, `button.background`, `focusBorder`, `progressBar.background`, `textLink.foreground`, `tab.activeBorderTop`, `panelTitle.activeBorder`, `editorCursor.foreground`, `terminalCursor.foreground`, `list.focusOutline`, `list.highlightForeground`, `inputOption.activeBorder`, `statusBarItem.remoteBackground`, `editorInfo.foreground`, `terminal.ansiCyan`, `terminal.ansiBrightCyan`, `terminal.ansiBrightBlue` |
| `AccentGoldBrush` | `#FFD700` | Highlight only, never chrome | `terminal.ansiBrightYellow` (a glyph colour, not a second accent) |
| `StatusSuccessBrush` / `ProviderReadyBrush` | `#3DDC97` | Ready | `gitDecoration.addedResourceForeground`, `gitDecoration.untrackedResourceForeground`, `editorGutter.addedBackground`, `terminal.ansiGreen`, `terminal.ansiBrightGreen` |
| `StatusWarningBrush` / `ProviderDegradedBrush` | `#FFB454` | Degraded | `gitDecoration.modifiedResourceForeground`, `editorGutter.modifiedBackground`, `editorWarning.foreground`, `statusBar.debuggingBackground`, `statusBarItem.warningBackground`, `terminal.ansiYellow` |
| `StatusErrorBrush` | `#FF6B84` | Error | `gitDecoration.deletedResourceForeground`, `gitDecoration.conflictingResourceForeground`, `editorGutter.deletedBackground`, `editorError.foreground`, `statusBarItem.errorBackground`, `terminal.ansiRed`, `terminal.ansiBrightRed`, `terminal.ansiMagenta`, `terminal.ansiBrightMagenta` |
| `ProviderUnconfiguredBrush` | `#8FA1B1` | Unconfigured / dimmed | `disabledForeground`, `gitDecoration.ignoredResourceForeground`, `terminal.ansiBrightBlack` |

## Palette mapping, light (Tokens.xaml `Light`)

| Token | Hex | Role in the shell | VS Code keys |
| --- | --- | --- | --- |
| `SurfaceBrush` | `#F5F7FA` | Base surface | `titleBar.activeBackground`, `editor.background`, `tab.activeBackground`, `breadcrumb.background`, `panel.background`, `terminal.background`, `statusBar.noFolderBackground` |
| `SurfaceSecondaryBrush` | `#FFFBFE` | Second surface step | `activityBar.background`, `sideBar.background`, `statusBar.background`, `titleBar.inactiveBackground`, `editorGroupHeader.tabsBackground`, `tab.inactiveBackground`, `editor.lineHighlightBackground` |
| `CardSurfaceBrush` / `SurfaceElevatedBrush` | `#FFFFFF` | Cards, inputs, popups | `sideBarSectionHeader.background`, `editorWidget.background`, `input.background`, `dropdown.background`, `quickInput.background`, `menu.background`, `notifications.background`, `list.inactiveSelectionBackground`, `list.hoverBackground` |
| `TextOnAccentBrush` | `#FFFFFF` | Text on the accent fill | `activityBarBadge.foreground`, `badge.foreground`, `button.foreground`, `statusBarItem.remoteForeground`, `statusBarItem.errorForeground`, `statusBarItem.warningForeground`, `statusBar.debuggingForeground` |
| `CardStrokeBrush` | `#D0D8E0` | Dividers; also the only mid-tone surface, so selection fills | `titleBar.border`, `activityBar.border`, `sideBar.border`, `sideBarSectionHeader.border`, `tab.border`, `statusBar.border`, `panel.border`, `terminal.border`, `menu.border`, `notifications.border`, `list.activeSelectionBackground`, `editor.selectionBackground`, `terminal.selectionBackground`, `menu.selectionBackground`, `quickInputList.focusBackground`, `button.secondaryBackground` |
| `BorderStrongBrush` | `#A0A8B0` | Emphasised borders | `input.border`, `dropdown.border`, `editorWidget.border` |
| `TextPrimaryBrush` | `#1A2838` | Body text | Every primary foreground listed for the dark scheme, plus `button.hoverBackground`, `list.highlightForeground` (see the contrast note), `terminal.ansiBlack`, `terminal.ansiBrightWhite` |
| `TextSecondaryBrush` | `#5A6B78` | Secondary text | `titleBar.inactiveForeground`, `activityBar.inactiveForeground`, `descriptionForeground`, `editorLineNumber.foreground`, `tab.inactiveForeground`, `breadcrumb.foreground`, `input.placeholderForeground`, `panelTitle.inactiveForeground`, `terminal.ansiBlue` |
| `HeliosAccentBrush` | `#007694` | The one accent | The same accent keys as the dark scheme except `list.highlightForeground`; `terminal.ansiCyan`, `terminal.ansiBrightCyan`, `terminal.ansiBrightBlue` |
| `AccentGoldBrush` | `#FFD700` | Decorative glow in the shell | Not used: 1.30:1 on light surfaces, so it cannot be a glyph colour |
| `StatusSuccessBrush` / `ProviderReadyBrush` | `#17794E` | Ready | `gitDecoration.addedResourceForeground`, `gitDecoration.untrackedResourceForeground`, `editorGutter.addedBackground`, `terminal.ansiGreen`, `terminal.ansiBrightGreen` |
| `StatusWarningBrush` / `ProviderDegradedBrush` | `#A85800` | Degraded | `gitDecoration.modifiedResourceForeground`, `editorGutter.modifiedBackground`, `editorWarning.foreground`, `statusBar.debuggingBackground`, `statusBarItem.warningBackground`, `terminal.ansiYellow`, `terminal.ansiBrightYellow` |
| `StatusErrorBrush` | `#CC0044` | Error | `gitDecoration.deletedResourceForeground`, `gitDecoration.conflictingResourceForeground`, `editorGutter.deletedBackground`, `editorError.foreground`, `statusBarItem.errorBackground`, `terminal.ansiRed`, `terminal.ansiBrightRed`, `terminal.ansiMagenta`, `terminal.ansiBrightMagenta` |
| `ProviderUnconfiguredBrush` | `#5F6E7A` | Unconfigured / dimmed | `disabledForeground`, `gitDecoration.ignoredResourceForeground`, `terminal.ansiBrightBlack`, `terminal.ansiWhite` |

## Terminal ANSI slots

The pack has no blue or magenta text token, so those slots reuse tokens rather than
invent colours: ANSI blue is the slate `TextSecondaryBrush`, bright blue and cyan are
the accent, magenta is the error token. Every slot is contrast-gated as text on
`terminal.background` (dark `ansiBlack` excepted: it equals the background, the
dark-terminal convention).

| Slot | Dark | Light |
| --- | --- | --- |
| `terminal.ansiBlack` | `#0A1428` `SurfaceBrush` | `#1A2838` `TextPrimaryBrush` |
| `terminal.ansiBrightBlack` | `#8FA1B1` `ProviderUnconfiguredBrush` | `#5F6E7A` `ProviderUnconfiguredBrush` |
| `terminal.ansiRed` / `ansiBrightRed` | `#FF6B84` `StatusErrorBrush` | `#CC0044` `StatusErrorBrush` |
| `terminal.ansiGreen` / `ansiBrightGreen` | `#3DDC97` `StatusSuccessBrush` | `#17794E` `StatusSuccessBrush` |
| `terminal.ansiYellow` | `#FFB454` `StatusWarningBrush` | `#A85800` `StatusWarningBrush` |
| `terminal.ansiBrightYellow` | `#FFD700` `AccentGoldBrush` | `#A85800` `StatusWarningBrush` |
| `terminal.ansiBlue` | `#8FA3B8` `TextSecondaryBrush` | `#5A6B78` `TextSecondaryBrush` |
| `terminal.ansiBrightBlue` | `#00D9FF` `HeliosAccentBrush` | `#007694` `HeliosAccentBrush` |
| `terminal.ansiMagenta` / `ansiBrightMagenta` | `#FF6B84` `StatusErrorBrush` | `#CC0044` `StatusErrorBrush` |
| `terminal.ansiCyan` / `ansiBrightCyan` | `#00D9FF` `HeliosAccentBrush` | `#007694` `HeliosAccentBrush` |
| `terminal.ansiWhite` | `#E8F1F8` `TextPrimaryBrush` | `#5F6E7A` `ProviderUnconfiguredBrush` |
| `terminal.ansiBrightWhite` | `#E8F1F8` `TextPrimaryBrush` | `#1A2838` `TextPrimaryBrush` |

## Contrast check (measured, never inherited)

Ratios are WCAG 2.x relative-luminance contrast, computed by
`scripts/verify/theme-contrast.py` (standard library only). Gates: text pairs at least
**4.5:1** (AA, normal text); interactive indicators (focus ring, active borders, cursors,
progress bar) at least **3:1** (WCAG 1.4.11). Plain dividers are not gated: 1.4.11
exempts boundaries that are not needed to identify a component, and the pack's stroke
tokens sit at 1.55:1 (`#1E3A4F` on `#0A1428`), 2.07:1 (`#3A5A78` on `#1A2838`),
1.34:1 (`#D0D8E0` on `#F5F7FA`) and 2.41:1 (`#A0A8B0` on `#FFFFFF`), which is what
the shell itself ships.

Text tokens against every surface they are placed on, dark:

| Text token | Hex | on `#0A1428` | on `#0F1D2E` | on `#1A2838` | on `#253548` | Worst |
| --- | --- | --- | --- | --- | --- | --- |
| `TextPrimaryBrush` | `#E8F1F8` | 16.06:1 | 14.87:1 | 13.08:1 | 10.92:1 | 10.92:1 |
| `TextSecondaryBrush` | `#8FA3B8` | 7.08:1 | 6.56:1 | 5.77:1 | 4.82:1 | 4.82:1 |
| `HeliosAccentBrush` | `#00D9FF` | 10.82:1 | 10.01:1 | 8.81:1 | 7.36:1 | 7.36:1 |
| `AccentGoldBrush` | `#FFD700` | 13.09:1 | 12.12:1 | 10.66:1 | 8.90:1 | 8.90:1 |
| `StatusSuccessBrush` / `ProviderReadyBrush` | `#3DDC97` | 10.39:1 | 9.62:1 | 8.46:1 | 7.07:1 | 7.07:1 |
| `StatusWarningBrush` / `ProviderDegradedBrush` | `#FFB454` | 10.41:1 | 9.64:1 | 8.48:1 | 7.08:1 | 7.08:1 |
| `StatusErrorBrush` | `#FF6B84` | 6.72:1 | 6.22:1 | 5.47:1 | 4.57:1 | 4.57:1 |
| `ProviderUnconfiguredBrush` | `#8FA1B1` | 6.91:1 | 6.39:1 | 5.63:1 | 4.70:1 | 4.70:1 |

Light (the `#D0D8E0` column is the selection fill; only `TextPrimaryBrush` is placed
on it as text):

| Text token | Hex | on `#F5F7FA` | on `#FFFBFE` | on `#FFFFFF` | on `#D0D8E0` | Worst as used |
| --- | --- | --- | --- | --- | --- | --- |
| `TextPrimaryBrush` | `#1A2838` | 13.93:1 | 14.58:1 | 14.95:1 | 10.38:1 | 10.38:1 |
| `TextSecondaryBrush` | `#5A6B78` | 5.14:1 | 5.38:1 | 5.51:1 | 3.83:1 (not placed) | 5.14:1 |
| `HeliosAccentBrush` | `#007694` | 4.87:1 | 5.10:1 | 5.23:1 | 3.63:1 (not placed) | 4.87:1 |
| `StatusSuccessBrush` / `ProviderReadyBrush` | `#17794E` | 5.04:1 | 5.28:1 | 5.41:1 | 3.76:1 (not placed) | 5.04:1 |
| `StatusWarningBrush` / `ProviderDegradedBrush` | `#A85800` | 4.82:1 | 5.04:1 | 5.17:1 | 3.59:1 (not placed) | 4.82:1 |
| `StatusErrorBrush` | `#CC0044` | 5.36:1 | 5.61:1 | 5.75:1 | 3.99:1 (not placed) | 5.36:1 |
| `ProviderUnconfiguredBrush` | `#5F6E7A` | 4.89:1 | 5.12:1 | 5.25:1 | 3.65:1 (not placed) | 4.89:1 |

Text on accent and status fills (badges, buttons, status-bar items):

| Pair | Ratio |
| --- | --- |
| `#0A1428` on `#00D9FF` (dark badge, button, remote item) | 10.82:1 |
| `#0A1428` on `#FFB454` (dark warning item, debugging bar) | 10.41:1 |
| `#0A1428` on `#FF6B84` (dark error item) | 6.72:1 |
| `#0A1428` on `#E8F1F8` (dark button hover) | 16.06:1 |
| `#FFFFFF` on `#007694` (light badge, button, remote item) | 5.23:1 |
| `#FFFFFF` on `#A85800` (light warning item, debugging bar) | 5.17:1 |
| `#FFFFFF` on `#CC0044` (light error item) | 5.75:1 |
| `#FFFFFF` on `#1A2838` (light button hover) | 14.95:1 |

One placement was changed by the gate: the light accent `#007694` measures 3.63:1 on
the `#D0D8E0` selection fill, so `list.highlightForeground` in the light scheme is
`TextPrimaryBrush` (`#1A2838`, 10.38:1) and match highlights rely on the bold weight
VS Code already applies. In the dark scheme the accent stays (7.36:1 on `#253548`).

The full pair table (161 pairs at the time of writing, all passing) is generated, not
maintained by hand:

```bash
python3 scripts/verify/theme-contrast.py             # text report, exit 1 on any failure
python3 scripts/verify/theme-contrast.py --markdown  # the same as Markdown rows
python3 scripts/verify/theme-contrast.py --json      # machine-readable
```

The script checks three things and exits 1 if any fails: every gated pair in both
scoped blocks; provenance (each dark hex is a literal of the `Default` dictionary,
each light hex a literal of the `Light` dictionary, parsed from `Tokens.xaml` at run
time); and drift (the `devcontainer.json` block equals the `workspace.code-workspace`
block, and every hex the blocks use appears in this document).

## Maintenance

1. Change colours only in `Tokens.xaml` (the GUI lane). This lane never edits it.
2. Re-derive: update the matching keys in `workspace.code-workspace`, copy the whole
   `workbench.colorCustomizations` object into `.devcontainer/devcontainer.json` under
   `customizations.vscode.settings` (the script fails until the two are identical),
   and update the tables above (the script fails until every hex is mentioned).
3. Run `python3 scripts/verify/theme-contrast.py`; both files must also stay strict
   JSON (`python3 -m json.tool`), which is what `quality.yml` enforces for `*.json`
   and `*.code-workspace`.
4. A shell pack switch (the P6 selection UI in `Themes/README.md`) does not move the
   workspace chrome by itself; re-derive from the chosen pack if that is wanted.
5. The Pages dashboard reads the tables in this document through the github-control
   lane's manifest; changing a hex here is the signal for that lane to update it.
