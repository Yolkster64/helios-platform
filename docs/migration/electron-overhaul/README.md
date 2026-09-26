# HELIOS Electron Overhaul

Direction accepted 2026-09-26 UTC. This is the implementation and acceptance
record for [ADR-0011](../../architecture/ADR-0011-ELECTRON-WORKBENCH.md).

Observed build/test results and environment limitations are recorded in
[VERIFICATION.md](VERIFICATION.md).

## What this change establishes

The complete HELIOS product UI moves to Electron. `apps/desktop` is the workbench,
Electron Forge is its build/package tool, and
`experiments/electron-fiddle/profile-lab` is the first focused lab. Existing C#,
F#, Python, C++, MCP, and infrastructure code keeps its specialist boundaries.
The previous Windows UI source remains available for parity checks and provenance.

The initial slice establishes an offline workbench, six profiles, presentation
preferences, a built-in capability catalog, USB planning, and a bounded optional
AIHub liveness read. It does not establish desktop OAuth, remote writes, native
plugin execution, real disk operations, Explorer replacement, or production
release readiness. Verify actual run results in the change's build/test evidence;
the presence of this plan is not evidence that every gate passed.

## Run and develop

From the repository root, use Node/npm versions compatible with
`apps/desktop/package.json`:

```bash
npm --prefix apps/desktop ci
npm --prefix apps/desktop start
npm --prefix apps/desktop test
npm --prefix apps/desktop run package
npm --prefix apps/desktop run make
```

`start` launches Electron Forge development mode. `package` creates an application
bundle and `make` invokes the configured platform maker. Run makers on their
supported operating systems: Squirrel for Windows and ZIP for the other configured
targets. A generated ZIP or unsigned application is not a signed release installer.
Keep install/build output out of source control; use the checked-in lockfile.

The workbench is usable without cloud accounts or a running AIHub. To opt into a
local health read, run the existing API in one terminal with an explicit binding:

```bash
ASPNETCORE_URLS=http://127.0.0.1:5080 dotnet run \
  --project src/ai/HELIOS.AIHub.Api -c Release --no-launch-profile
```

Then start the desktop in another terminal:

```bash
HELIOS_AIHUB_URL=http://127.0.0.1:5080 npm --prefix apps/desktop start
```

On PowerShell, set each variable with `$env:NAME = 'value'` before its command.
The repository's existing development launch profile uses port 5170; this example
uses `--no-launch-profile` to make the selected 5080 binding explicit. If an API is
already running at another loopback port, set `HELIOS_AIHUB_URL` to that root URL.
There is no default background scan. The desktop validates `/healthz`; service
liveness does not verify provider credentials or call any paid model.

## Fiddle workflow

Open the `experiments/electron-fiddle/profile-lab` files in Electron Fiddle: main,
preload, renderer, HTML, and styles. Select an Electron version compatible with the
app and run the small experiment there. The lab is intended for profile controls,
visuals, preload boundaries, and focused Electron API exploration; it is not the
full product or a connector-authentication shortcut.

Keep lab changes self-contained, describe what was observed, then port accepted
behavior into `apps/desktop` with its tests. Fiddle does not replace Forge's package,
maker, signing, or release checks. Never paste tokens into a lab or publish an
experiment containing private tenant/workspace URLs.

## Target module map

| Module | Product responsibility | Reused specialist boundary | Acceptance before consequential operation |
|---|---|---|---|
| Workbench and profiles | Navigation, saved layouts, themes, six profile experiences | Electron main preferences | Restart persistence, keyboard navigation, reduced motion, no elevation from profile changes |
| Launcher and settings | App search/launch, system settings views, notifications and tray | Reviewed Windows/native adapters | Known application identity, bounded operations, clear platform availability |
| AIHub and fleet | Routing, provider comparisons, Hermes/XCore status, evaluations, task history | Existing AIHub API and MCP | Real readiness states, bounded cancellation, actual receipts and provider cost controls |
| Connection center | GitHub, ChatGPT/OpenAI, Copilot, Slack, Linear, SharePoint, Azure/365 | Main-process broker and service-side adapters | Provider-supported auth, scoped access, refresh/revocation, one verified read before writes |
| USB wizard | Device/ISO/driver plans, partition intent, recovery/quarantine/vault review | Future privileged Windows executor | Fresh device identity, plan digest, explicit approval, rollback/recovery evidence |
| Native extensions | C++ graphics/audio/telemetry and OS specialists | Isolated processes or reviewed native addons | Versioned manifest, capability enforcement, crash isolation, OS/ABI packaging |
| Visual and sound system | Monado scenes, responsive blade/rings, weather/backdrops, audio and Chroma | Renderer graphics plus native adapters where measured | Motion/contrast controls, performance budget, offscreen/idle throttling, real device capability checks |
| Shell mode | Optional Explorer replacement using the same Electron product UI | Supported Windows shell mechanisms and separate watchdog | Supported edition, recovery login/path, bounded restart loop, uninstall and rollback proven |
| Delivery and evidence | Builds, diagnostics, release history, project links | GitHub Actions and protected environments | Matching-platform checks, signed artifacts, checksums, staged updates and recovery |

The profile names are **Sysadmin, Developer, Studio, Gamer, Core, AI/Server**.
Recovery, quarantine, DevDrive, and vault belong to storage/setup design, not new
profiles. The interface may preview them before any native executor exists.

## Connector discovery evidence and limits

Read-only discovery during this migration session on 2026-09-26 established:

| Surface | Observed in the ChatGPT session | What this means for the Electron app |
|---|---|---|
| GitHub | Repository/PR read tools were reachable | Source inspection is possible; desktop OAuth and API adapter readiness remain separate |
| Slack | Read tools were reachable | No desktop token, background sync, or message-posting implementation is implied |
| Linear | Read tools were reachable | No desktop workspace connection or issue-write capability is implied |
| SharePoint | Site and file metadata were reachable; the attempted Markdown content response was null | Metadata access is evidenced; complete source-document extraction and desktop Graph access are not |

These observations are a session snapshot, not persistent product health. Do not
copy private workspace identifiers, tenant/site URLs, message bodies, or tokens
into this public repository. Configure scoped destinations privately when each
adapter is implemented. A catalog entry or browser link is not an authenticated
integration and should never display as one.

The source migration must also distinguish open PRs from merged capabilities.
At inspection, [PR #253](https://github.com/Yolkster64/helios-platform/pull/253)
was open at `cb56753b925011b134435a4b39156eb07f369966` with 188 changed files.
That snapshot is not proof it will remain open. Re-check its head and merge status
before integrating it; do not document an unmerged `--serve` bridge as available
on canonical main. The health example above uses the existing API project directly.

## Delivery sequence and acceptance

| Stage | Deliverable | Required evidence | State in this migration slice |
|---|---|---|---|
| E0 — Establish authority | ADR, Electron app root, mirrored agent instructions, preserved legacy checks | One canonical repository; no disabled production guard or erased source history | Direction and scaffolding established |
| E1 — Offline workbench | Profiles, preferences, module catalog, USB plan view, bounded health read, Fiddle lab | Core tests; observed renderer behavior; Forge packaging; failures reported honestly | Initial implementation; use PR verification for platform results |
| E2 — Read-only integration | Main-process adapters for AIHub/MCP and the selected collaboration tools | Real auth states; least-scoped authorized reads; timeout, retry, revocation and redaction tests | Planned |
| E3 — Coordinated work | Reviewable GitHub/Linear changes, explicit Slack communication, SharePoint evidence linkage | Preview/change intent, returned IDs, idempotency, provenance and cancellation | Planned |
| E4 — Native and USB | Native extension host, device inventory, reviewed USB executor | Windows VM/hardware evidence, exact target checks, failure recovery, privilege separation | Planned; current USB flow is planning only |
| E5 — Desktop shell | Launcher/settings/tray parity, dynamic visuals/audio, optional Explorer mode | Accessibility/performance measurements, supported editions, watchdog and rollback drills | Planned |
| E6 — Release and cutover | Signed multi-platform distribution, updates, archival parity decision | OS launch/install tests, signatures/notarization as applicable, update rollback, source/license map | Planned |

Stages describe dependencies, not dates or claims of completion. E2 can be built
adapter by adapter while E1 evolves. E4 and E5 require a suitable Windows validation
environment and deliberate review of privileged operations. GUI parity is a feature
inventory with behavior and evidence, not a visual resemblance or a copied folder.

## Verification and rollback

Keep existing service gates for touched service code and the existing cutover gate:

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release
(cd src/ai/python && python3 -m pytest tests)
bicep build infra/main.bicep --stdout
python3 scripts/validation/validate_yolkster_cutover.py
pwsh scripts/verify/instructions-drift.ps1
```

The cutover check guards repository authority, disabled production, and the
preserved WinUI tree through `config/ui/winui3-only.v1.json`. It is deliberately not
repurposed to claim Electron readiness. Windows-only legacy UI builds keep their
existing runner boundary. Desktop tests and Forge checks are additional gates;
report a missing SDK or unavailable OS as unverified, not passed.

Before enabling later adapters, verify unauthorized IPC and payload rejection,
resource allowlists, malformed/oversized API responses, explicit loopback binding,
corrupt preference recovery, and offline behavior. Before release, measure startup,
idle CPU/memory, scene rendering, foreground responsiveness, and background
throttling on stated hardware; set budgets from those measurements rather than
inventing performance claims.

The initial app must not alter the Windows shell, disk layout, drivers, credentials,
or cloud resources during launch. It can be closed without restoring any OS shell
configuration. A future shell deployment must ship its own tested Explorer recovery
and uninstall path before it can be activated. Legacy source is retained for
engineering comparison, but the new product does not embed a WinUI fallback.

Production remains disabled. GitHub protected environments remain deployment
authority. Plugin activation, a Sysadmin theme, an AI recommendation, a chat message,
and a health badge cannot grant deployment or privileged-device authority.
