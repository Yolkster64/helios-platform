# src/gui — HELIOS desktop shell

| Directory | What it is |
|---|---|
| `HELIOS.Shell/` | **The** WinUI 3 shell (Windows App SDK 1.6, net8.0-windows10.0.19041.0) — the GUI_THEME_ANALYSIS.md direction, bootstrapped ahead of roadmap PR6. NavigationView shell + AI Hub provider dashboard bound to `helios-ai-api`. |
| `HELIOS.Shell.sln` | The shell's **own** solution and its only build entry point. |
| `MonadoBlade.GUI/` | Orphaned WPF experiment (no csproj references it). Mined for design intent only — do not build, extend, or port code from it. Quarantine to `legacy/` is a PR2 item. |

## Build (Windows only)

Requirements:

- Windows 10 1809 (build 17763) or later / Windows 11.
- .NET 8 SDK.
- Visual Studio 2022 17.10+ with the **Windows application development** workload
  (or plain `dotnet` CLI — the WinUI XAML compiler ships via the
  `Microsoft.WindowsAppSDK` NuGet package, so VS is convenient but not mandatory).
- To *run* the produced exe: the [Windows App SDK 1.6 runtime](https://learn.microsoft.com/windows/apps/windows-app-sdk/downloads)
  must be installed, because the project is unpackaged (`WindowsPackageType=None`) and
  deliberately **not** self-contained (`WindowsAppSDKSelfContained` unset).

```powershell
# from the repo root, on Windows
dotnet build src/gui/HELIOS.Shell.sln -c Debug -p:Platform=x64
dotnet run --project src/gui/HELIOS.Shell/HELIOS.Shell.csproj -p:Platform=x64
```

Point the dashboard at a running hub API first:

```powershell
dotnet run --project src/ai/HELIOS.AIHub.Api   # serves /v1/status
$env:HELIOS_API_URL = "http://localhost:5170"  # optional; this is the default
```

If the API is not running, the dashboard shows a graceful "API not running" warning with
the resolved URL and the command to start it — that state is expected, not a bug.

## Why this is NOT in HELIOS.sln (and must never be added)

`dotnet build HELIOS.sln -c Release` runs on **Linux** CI (`dotnet-build.yml`). WinUI 3 /
Windows App SDK projects target `net8.0-windows10.0.19041.0` and require the Windows
XAML compiler and Windows-only NuGet assets: on a Linux runner the restore itself fails.
Adding `HELIOS.Shell` to `HELIOS.sln` would turn the main build permanently red — and a
check that can never be green is worse than no check (pipelines-config skill). Hence the
separate `HELIOS.Shell.sln`.

Related repo invariant: the root `HELIOS.Platform.csproj` recursively globs `**/*.cs`
(and, via WPF default items, `**/*.xaml`); `src/gui/**` is on its `<Compile Remove>` /
`<Page Remove>` lists. Keep it there when adding files here.

## Roadmap (PR6, per GUI_THEME_ANALYSIS.md / ROADMAP_MULTI_LLM.md)

- **Windows CI**: a `windows-latest` job building `src/gui/HELIOS.Shell.sln` — a *new*
  workflow, not a change to the existing Linux jobs. Deliberately not added yet to keep
  this change-set out of `.github/workflows/`.
- Routing page (editable task-routing grid) and Fleet page (Xcore-9s pool state); the
  NavigationView placeholders exist, disabled.
- Provider metrics (latency, success rate, tokens) + Win2D sparklines once the hub
  exposes `GetMetrics` over REST; per-provider enable toggles writing `config/aihub.json`.
- net8.0 → net10.0 with the rest of the platform; `winui3-reviewer` agent gate on shell PRs.
- Live theme re-resolution for the readiness dot brushes (today they resolve at bind
  time — see `Helpers/ReadinessVisuals.cs`).
