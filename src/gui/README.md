# src/gui — HELIOS desktop shell

| Directory | What it is |
|---|---|
| `HELIOS.Shell/` | **The** WinUI 3 shell (Windows App SDK 1.6, net8.0-windows10.0.19041.0) — the GUI_THEME_ANALYSIS.md direction, bootstrapped ahead of roadmap PR6. Home with the shared Connect → Unify → Automate → Validate flow, AI Hub status, and Fabric connections bound to `helios-ai-api`. |
| `HELIOS.Shell.sln` | The shell's **own** solution and its only build entry point. |
| `MonadoBlade.GUI/` | Orphaned WPF experiment (no csproj references it). Mined for design intent only — do not build, extend, or port code from it. Quarantine to `legacy/` is a PR2 item. |

## One place to start

The shell opens Home first. Its GitHub, Linear and Slack links come from
`config/control-project.json`, copied beside the executable at build and publish time.
The parser accepts manifests up to 64 KiB from the application directory and HTTPS links
without embedded credentials, query strings or fragments. Invalid links stay disabled.

Home copies `pwsh -NoProfile -File ./connect.ps1 status`; run it from the repository
folder in PowerShell 7. It does not launch a shell or sign in on your behalf. The
setup guide explains the shared Claude Code, Codex and API configuration.

Fabric restores the original four view/view-model files from PR #186, source commit
`673e3d1680aff026250e12bc428dcd55fb2dfc98`, with these corrections:

- It uses the shell's injected `AIHubApiClient` and distinguishes a reachable API from
  unverified provider authentication, connector delivery, and Hermes/XCore workers.
- It shows local configuration presence without rendering environment values or URLs.
- Copy buttons handle clipboard failure; browser actions report launch failure.
- Setup is a copied command with potential identity changes explained. Verification
  remains separately available as a read-only command.

The Home and Fabric navigation items stay synchronized when Home shortcuts are used.
Home scrolls at narrow sizes; the navigation pane collapses automatically. Both pages
use the existing semantic theme brushes and type ramp, including high contrast.

## Build (Windows only)

Requirements:

- Windows 10 1809 (build 17763) or later / Windows 11.
- .NET 10 SDK (the repo-root `global.json` pins 10.0.100 with `rollForward:
  latestFeature`, so any newer 10.0.x band is accepted; the shell itself still
  targets `net8.0-windows10.0.19041.0`, which the .NET 10 SDK builds fine).
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

Direct loopback requests need no key. When `HELIOS_API_URL` points through Docker's
bridge or at a remote API, set the same access key used by the server; the client sends it
as `X-HELIOS-Api-Key`:

```powershell
$env:HELIOS_API_ACCESS_KEY = "replace-with-the-server-key"
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

## Fork & contribute GUI work

The one structural fact to internalize before a GUI PR: **the shell has its own solution
(`src/gui/HELIOS.Shell.sln`), built on Windows, while CI builds `HELIOS.sln` on Linux.**
Consequences:

- **Native compilation has its own Windows gate.** `.github/workflows/gui-windows.yml`
  builds `HELIOS.Shell.sln` on Windows for GUI changes. Inspect that specific result;
  Linux XML and architecture checks do not establish that XAML compiles or renders.
  Validate startup, Home shortcuts, narrow windows, keyboard navigation and contrast
  themes on Windows before release.
- **GUI PRs must keep the root csproj glob guards intact.** The exact rule: the root
  `HELIOS.Platform.csproj` recursively globs `**/*.cs` (and, via WPF default items,
  `**/*.xaml`); `src/gui/**` must stay on its `<Compile Remove>` / `<Page Remove>`
  lists. Files you add under `src/gui/` are covered by the existing `src/gui/**`
  entries — do not remove or narrow them. Any new C# directory you create *outside*
  `src/ai`/`src/mcp`/`src/gui` needs its own `<Compile Remove>` entry in the same
  commit, or it silently breaks the root WPF project (CLAUDE.md hard rule).
- **Never add `HELIOS.Shell` to `HELIOS.sln`** — the restore alone fails on the Linux
  runner and turns the main build permanently red (see the section above).

Where things live:

- **Design direction**: `docs/architecture/GUI_THEME_ANALYSIS.md` — WinUI 3 framework
  choice, the three v1 pages, and the token-based theme system (semantic brushes per
  theme dictionary, no literal colors in XAML). Coding conventions:
  `.claude/skills/winui3-shell`.
- **The API the dashboard binds to**: `helios-ai-api` (`src/ai/HELIOS.AIHub.Api`),
  default `http://localhost:5170`, overridable via `HELIOS_API_URL`. Direct loopback
  calls need no key; when the URL points through Docker's bridge or at a remote API, set
  `HELIOS_API_ACCESS_KEY` to the server's key — the client sends it as
  `X-HELIOS-Api-Key`, and the server answers 401 without it (see "REST API" in the root
  README).
- **Testing the shell against a locally running API**: exactly the "Build (Windows
  only)" flow above — `dotnet run --project src/ai/HELIOS.AIHub.Api` in one terminal,
  the shell in another. No provider keys are required: an all-`Unconfigured` provider
  table is a valid, expected dashboard state, and the "API not running" warning (with
  the resolved URL) is the designed no-API state, not a bug. The API-side smoke
  (healthz/status/401 checks) is in `docs/TEST_RUN_PLAYBOOK.md`.

**GUI-adjacent work that is NOT Windows-only** does not belong in this directory's
Windows lane and can be built and CI-verified on any platform:

- Theme/design *documentation* and token decisions → `docs/architecture/`
  (`GUI_THEME_ANALYSIS.md` and successors); merged docs auto-publish to the wiki via the
  Wiki Sync workflow.
- Changes to the API surface the shell consumes (new endpoints, response shapes) →
  `src/ai/HELIOS.AIHub.Api`, inside `HELIOS.sln`, covered by the normal Linux CI and the
  `.claude/skills/api-creator` recipe.

## Roadmap (PR6, per GUI_THEME_ANALYSIS.md / ROADMAP_MULTI_LLM.md)

- Routing page (editable task-routing grid) and Fleet page (Xcore-9s pool state); the
  NavigationView placeholders exist, disabled.
- Provider metrics (latency, success rate, tokens) + Win2D sparklines once the hub
  exposes `GetMetrics` over REST; per-provider enable toggles writing `config/aihub.json`.
- net8.0-windows → the net10 equivalent once the pinned Windows App SDK line documents
  net10 support (the rest of the platform is already on net10.0 — WASDK 1.6 documents
  .NET 8 only); `winui3-reviewer` agent gate on shell PRs.
- Live theme re-resolution for the readiness dot brushes (today they resolve at bind
  time — see `Helpers/ReadinessVisuals.cs`).
