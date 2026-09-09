# Six parts, one HELIOS repository

Choose the part you are changing; its code, focused checks and release boundary
stay visible together. `Yolkster64/helios-platform` remains the source repository.
These parts share contracts and can be tested separately; they are not new repos
or independently deployed services.

```bash
bash connect.sh parts
bash connect.sh parts gui --piece home
bash connect.sh test gui --piece themes
bash connect.sh workbench home --open
```

PowerShell uses the same arguments: `pwsh ./connect.ps1 parts` and
`pwsh ./connect.ps1 test usb`. The underlying helper is
`python3 scripts/bootstrap/components.py list`, `plan NAME` or `test NAME`.
Listing and planning execute nothing. Only `test NAME` runs its fixed check list.

| Part | Work here | Focused check | Release boundary |
|---|---|---|---|
| **Core** | `src/ai`, `src/mcp` | AIHub/MCP tests and Python analytics contracts | Shared libraries and API; remote hosting belongs to Cloud |
| **Desktop** | Native `App`, `MainWindow`, navigation and project definition | Host/package build on Windows | Hosts the GUI and owns packaging; Visual Studio MSBuild is required |
| **GUI** | Native `Views`, `ViewModels`, `Themes` and `config/ui` | Shared native build on Windows | Home, AIHub, Fabric, USB and Theme edit pieces; deployed with Desktop |
| **USB** | `src/ai/HELIOS.AIHub/Setup`, native USB page | Portable `UsbSetup` planner tests | Non-destructive plan data; no disk or boot execution |
| **Cloud** | `infra`, identity setup helpers | OIDC/identity tests against an inert CLI; Bicep and parameter compilation | `helios-deploy.yml` on `main`, through protected `azure-dev` |
| **Fleet** | AIHub `Fleet`, `scripts/fleet`, fleet topology and Python workers | Fleet readiness/topology/worker tests | Simulation and contracts; actual workers/cloud burst need separate activation |

`config/components.json` maintains descriptions, paths, dependencies, existing CI
workflows and build definitions. It cannot supply shell commands. The runner owns
six fixed test profiles, validates the map against its schema and runs only in
its own reviewed checkout. It never dispatches GitHub workflows, authenticates,
creates repositories or runs deployment/repair scripts.

Plans for Cloud and Fleet identify the existing protected workflow and its
read-only defaults (`what_if=true`, `deploy_confirmed=false`). They do not send a
workflow request. Bicep stays authoritative for HELIOS infrastructure. The shared
runtime's identity, cloud attachment and fleet activation are separate decisions,
with the current owner guidance in [OWNER_START_HERE.md](OWNER_START_HERE.md).

## Work on a GUI piece

GUI is a separate logical part with one source map, not a second copy of the
native project. `parts.gui.pieces` in `config/components.json` defines:

| Piece selector | Edit scope | Linked parts |
|---|---|---|
| `home` | Home view and view model | Core, Cloud |
| `aihub` | AIHub view, view model and API client | Core, Fleet |
| `fabric` | Fabric view and view model | Core, Cloud, Fleet |
| `usb` | USB setup view and view model | USB, Core |
| `themes` | Shared theme tokens and UI configuration | Desktop |

`bash connect.sh parts gui --piece home` returns `editPaths`, `selectedPiece`,
linked parts, workflow/build definitions and the shared test scope without
executing anything. `theme` is accepted as an alias for `themes`.
`bash connect.sh workbench home --open` prepares a separate human worktree using
the existing workspace helper and opens its workspace when an editor is available.
It keeps all work in this repository's shared history.

`bash connect.sh test gui --piece home` selects the Home edit context and builds
the **whole existing native project** on Windows. All pieces use that same
compilation: a selected piece is not an independently compiled or deployed app.
The underlying helper accepts `plan gui --piece home` and
`test gui --piece home`; `list_gui_pieces()` exposes the same metadata to the
native workbench. Desktop owns the host/package and Cloud retains its protected
workflow. No selector dispatches a release or changes a cloud resource.

Test output names each executed check and returns a failure status for missing
tools/files, an unsupported host, timeout, nonzero exit or missing/empty .NET test
receipt. Desktop and GUI native builds are unavailable on Linux; that is never counted as a passed
Windows build. Python checks require pytest, Cloud's twin-shell contracts require
PowerShell 7, and Bicep must be installed for Cloud compilation. The .NET SDK and
Visual Studio may restore their declared packages during tests; tests do not call
paid models or cloud deployment APIs.

.NET and pytest results use temporary TRX/JUnit counters; the two unittest
suites also check their collected/executed counts. Zero tests or skipped tests
are never reported as a passed component. Focused checks speed up local
work; the repository's required CI gates still apply to the combined change.
The [shared connection guide](CONNECT.md) remains the one starting point.
