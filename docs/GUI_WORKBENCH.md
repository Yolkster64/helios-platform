# GUI Workbench

HELIOS has one repository and two related native parts: **GUI** holds views,
view-models, reusable controls and themes; **Desktop** hosts and packages them.
The module map lives in `config/components.json`, under `parts.gui.pieces`.
Home, AIHub, Fabric, USB and Themes are focused edit areas within the same WinUI
application. They share one native build, not five competing applications.

## Open the workbench

From the repository, prepare an isolated editing branch and open the themed editor:

```bash
bash connect.sh workbench --open
```

Use `workbench usb --open` for a USB-focused working area. Omit `--open` and add
`--json` for unattended preparation. Existing edits are preserved; new worktrees
start from committed source. In VS Code, **Run Task → HELIOS: GUI preview
(Windows)** builds the native shell and starts its fixture page. The other HELIOS
tasks run part checks or build GUI. Visual Studio's Windows MSBuild must be on
the terminal PATH; a Developer PowerShell session provides it.

Choose **Workbench** in the desktop navigation or **Open GUI Workbench** on Home.
For a session that opens directly into local fixtures, launch the built application:

```powershell
.\src\gui\HELIOS.Shell\bin\x64\Release\net8.0-windows10.0.19041.0\HELIOS.Shell.exe --workbench
```

The exact `--workbench` flag opens the preview before any runtime page is created.
No AIHub API client is needed by Workbench. It loads only the installed component
map and bundled theme files, then renders fixed sample data. There is no provider
call, credential check, disk operation or deployment.

## Edit, preview, test, build

1. Choose a GUI piece. Workbench shows its source files and linked project parts
   from the same manifest used by the component runner. Missing or invalid metadata
   produces an unavailable message; the preview still works.
2. Edit the source in your isolated checkout. For the shared status card, edit
   `src/gui/HELIOS.Shell/Controls/StatusCard.xaml`. Both AIHub and Workbench use that
   control. Start the shell under a Windows debugger to use XAML Hot Reload; new
   classes, code-behind handlers and some binding changes require a rebuild.
3. Exercise **Unconfigured**, **Ready**, **Degraded** and **Long text** fixtures.
   These are display examples, not service readiness. The sample action only changes
   a local message. Check keyboard focus, wrapping and scrolling at narrow sizes.
4. Preview Monado, GitHub Dark, Solar Light or High Contrast tokens in light, dark
   or Windows-selected brightness. Only the sample surface changes. This does not
   persist a theme preference or restyle the whole application. For full high
   contrast validation, enable a Windows contrast theme and check the whole shell.
5. Run the GUI component checks, which also build the Desktop host on Windows. Workbench
   displays the commands and workflow paths but never executes them or claims their
   result.

```powershell
pwsh -NoProfile -File ./connect.ps1 test gui
```

Portable metadata tests run independently:

```bash
dotnet test tests/HELIOS.AIHub.Tests -c Release --filter FullyQualifiedName~GuiWorkbench
```

The GUI/Windows workflow builds all native pages and creates the
`helios-desktop-win-x64` artifact. A piece selection narrows editing scope; it does
not skip shared-build validation. Downloading a build is separate from releasing
or deploying it. Cloud resources stay within the Cloud part and its protected
workflow. Workbench does not query live CI or deployment status.

## Open a real page deliberately

The module action is an allowlisted navigation choice:

- **Home** opens project guidance and real browser links.
- **AIHub** and **Fabric** say **Open page with configured runtime**. Opening either
  leaves local fixtures and performs the existing configured API/status checks.
- **USB** opens the shared local planning page with manual inventory.
- **Themes** focuses the local palette preview.

Manifest strings cannot name arbitrary page classes, executables or URLs to run.
The map is limited to 64 KiB; malformed, oversized, duplicate or incomplete GUI
metadata disables module navigation. Test commands remain fixed display text.

## Source and validation boundaries

`Controls/StatusCard` owns reusable visual presentation. `GuiWorkbenchCatalog`
reads the inert component map. `WorkbenchPageViewModel` holds fixtures and display
state. `WorkbenchPage` owns only native navigation and the preview theme surface.
No second server, web frontend, PowerShell GUI host or provider implementation is
introduced.

The shell retains the current Windows App SDK 1.6 / net8.0-windows target, built
with .NET 10 SDK/Visual Studio MSBuild. The metadata parser is source-linked into
portable .NET 10 tests. Those tests verify input handling, not XAML compilation,
accessibility or visual correctness. The Windows build and interactive checks
remain release gates; see [native build instructions](../src/gui/README.md).
