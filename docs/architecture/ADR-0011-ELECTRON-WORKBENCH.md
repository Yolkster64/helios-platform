# ADR-0011: Electron Owns the HELIOS Product Interface

Status: Accepted direction; implementation and migration are incremental.

Decision date: 2026-09-26 UTC (2026-09-25 in America/Chicago).

Supersedes: [ADR-0010](ADR-0010-WINUI3-ONLY.md) for active product UI.

## Context

The owner requested a complete HELIOS overhaul using Electron, Electron Forge,
Electron Fiddle, plugins, APIs, and extensions, and clarified that Electron should
replace the existing Windows UI throughout the product. This direction includes
the launcher, settings, profile experiences, workbench, AIHub, USB wizard, and
eventual desktop shell. It is not a request for an extra web dashboard beside an
active WinUI product.

The repository already contains useful C# services, F# policy, Python analytics,
C++ acceleration, PowerShell automation, MCP contracts, and Azure infrastructure.
Reusing those boundaries avoids translating functioning native and service code
into renderer code. Existing WinUI and WPF-era sources also contain design and
provenance worth preserving during migration.

## Decision

`apps/desktop` is the active product UI in the existing canonical monorepo.
Electron owns application windows and the Chromium renderer; Electron Forge owns
development, packaging, and platform makers. Electron Fiddle is a separate lab for
small, reproducible experiments that graduate into the product through reviewed
changes. The first implementation uses CommonJS main/preload code and local
HTML/CSS/JavaScript without a mandatory renderer bundler.

All new HELIOS user-facing desktop experiences target this interface. Existing
`src/gui` is retained as migration evidence, not offered as a WinUI fallback inside
Electron. Its extraction into a separate GUI repository is deferred for reassessment
after Electron parity. No repository rename, deletion, merge, or production
deployment is implied by this architectural change.

## Runtime and module boundaries

| Layer | Responsibility | Contract and execution boundary |
|---|---|---|
| Electron renderer | Workbench, profile themes, status, launcher/settings views, USB plan review | Local assets and narrowly exposed preload functions; no credentials, shell, or filesystem primitives |
| Preload bridge | Translate named UI requests into bounded IPC calls | One method per capability; validate sender and payload again in main |
| Electron main | Window lifecycle, preferences, trusted resource IDs, capability policy, connector coordination | Owns side effects; returns bounded, serializable results |
| AIHub / MCP | Provider routing, model combinations, fleet planning, evidence and status | Existing C# API and governed MCP tools; provider code stays outside the renderer |
| F# and Python | Policy, mathematical analysis, evaluations and recommendations | Versioned request/result contracts, deadlines and concurrency limits |
| C++ / native services | Hardware, demanding graphics/audio, telemetry and performance-sensitive integration | Reviewed native adapter or separate service; explicit OS support and permission requirements |
| PowerShell / Azure | Operator automation, infrastructure validation and development plans | Existing authority and protected-environment gates remain effective |

The first desktop-to-service connection is an optional liveness read. An operator
sets `HELIOS_AIHUB_URL` explicitly to a loopback root URL; main requests `/healthz`
and validates its response. There is no automatic port scan, provider invocation,
or inference from a green process-health badge that providers are authenticated.
Later API and MCP adapters must report authentication and individual capabilities
separately from transport reachability.

New cross-module requests should extend the existing HELIOS contracts with a
version, request or event ID, correlation ID, module/capability, operation,
classification, source revision, and optional approval reference. Results carry
status, a bounded payload or error, timestamps, and any actual receipt identifier.
Do not claim this entire future envelope is implemented by the initial health read.
Cancellation, timeout, redaction, duplicate handling, and capability negotiation
must be defined before a module performs consequential operations.

## Plugins, APIs, and extensions

These are separate systems with different authority:

| Mechanism | Intended use | Initial state |
|---|---|---|
| Forge plugins, makers, publishers | Build transforms, Electron fuses, platform packages, eventual release publication | Fuses and platform makers configured; publication and signing require separate setup |
| HELIOS workbench modules | Pages and capabilities for profiles, AIHub, fleet, connectors, USB planning, native tools | Built-in catalog; not an arbitrary executable plugin installer |
| Native extensions | C++ or other specialist adapters for measurable performance or OS access | Capability manifest scaffold; executable loading remains future work |
| Electron/Chromium extensions | Selected development tools or explicitly supported extension APIs | No promise of Chrome Web Store parity or unrestricted browser-extension installation |
| External service adapters | GitHub, Slack, Linear, SharePoint, Azure/365, AI providers and MCP | Catalog and trusted links first; each adapter requires its own implementation and authorization |

Native work should run outside the renderer. Prefer a separate process/service
when isolation, crashes, privileges, or independent lifecycle matter. A reviewed
Node-API addon may be appropriate for a narrow low-latency operation; it needs
architecture/ABI packaging, resource ownership, timeout/cancellation behavior,
and crash analysis. Electron native modules must be built for the Electron runtime.
Do not add native dependencies solely because they are available.

The eventual HELIOS plugin host needs a versioned manifest, declared capabilities,
explicit activation, compatible host versions, integrity/provenance checks,
resource limits, failure isolation, and revocation. A settings toggle must never
silently grant a module arbitrary process execution or device access.

## Connectors and identity

The target is one readable connection center with independent states for transport,
account authorization, scopes, adapter readiness, and last verified operation.
GitHub remains source/change authority; Linear tracks delivery, Slack supports
coordination, and SharePoint stores knowledge/evidence. Those destinations do not
replace GitHub protected environments as deployment authority.

Desktop OAuth must use a provider-supported public-client flow in the system
browser, with PKCE where supported, or a service-side exchange when a confidential
client is required. Never embed a client secret in the distributed app. Connector
tokens belong to a main-process credential broker backed by appropriate OS storage
or a service identity; only connection summaries reach the renderer. Tenant IDs,
site URLs, workspace IDs, callback registration, scopes, consent, refresh,
revocation, and logout are explicit setup data, not values guessed from a URL.

ChatGPT's selected plugins are a separate authenticated surface. Successful reads
through them do not install a desktop adapter, export credentials, or authorize
silent background message posting. ChatGPT web sessions, OpenAI API access,
GitHub Copilot, and other providers are distinct entitlements and connections.
Remote websites open through approved resource IDs in the user's browser; they
are not given the application's preload bridge.

## Electron security and packaging contract

Renderers keep `nodeIntegration: false`, `contextIsolation: true`, and
`sandbox: true`. Restrictive content policy, local assets, denied unexpected
permissions/navigation/windows, and validated IPC are baseline architecture.
Every renderer request is untrusted; a valid channel name alone grants no
authority. The initial app exposes only its implemented bounded operations.

Main selects known external resources instead of accepting arbitrary URLs or
shell commands from page content. Network adapters use fixed operation paths,
timeouts, response-size bounds, redirect policy, and redacted errors. Preferences
contain presentation settings and module choices, never API tokens.

Forge makes desktop builds from the lockfile. Windows, macOS, and Linux packaging
are separate claims from OS launch tests, installer verification, code signing,
macOS notarization, and update validation. Release publication and automatic
updates remain disabled until those gates and recovery tests are implemented.
The Electron version is upgraded deliberately with regression checks; a package
being buildable does not mean its embedded runtime remains supported forever.

## Full Windows UI and native OS limits

Electron is the intended HELIOS interface for the application launcher, settings,
search, widgets, tray surfaces, profile switching, dynamic backgrounds, sound and
lighting controls, setup and USB flows. C++/Windows services may implement native
operations behind those views when beneficial. The visual layer should preserve
the Monado identity while honoring keyboard operation, reduced motion, contrast,
and background resource budgets.

An optional Explorer-replacement mode is a future delivery milestone. It needs
Windows-edition detection, a supported shell-launch mechanism where available,
per-user configuration, a separate native watchdog, crash/restart limits, a
known-good Explorer recovery route, and a tested uninstall/rollback path. It
starts disabled and is never enabled by launching the workbench. Verify it in a
disposable Windows environment before considering any workstation transition.

Electron starts in a user session; it does not become firmware, the boot manager,
Winlogon, the secure desktop, or the UAC consent surface. HELIOS can display its own
loading and unlock experience after sign-in, but native OS authentication and
protected operations retain their boundaries. A future USB executor is a separate
privileged component with exact target identity and reviewed operation plans; the
initial UI only produces and reviews plans.

The six profile names remain **Sysadmin, Developer, Studio, Gamer, Core, and
AI/Server**. Recovery and quarantine are storage/partition functions, not extra
profiles. Selecting Sysadmin in the UI grants no administrator rights.

## Migration and enforcement

The staged plan and acceptance gates live in
[the Electron migration runbook](../migration/electron-overhaul/README.md).
Existing production restrictions and repository cutover checks continue.
`config/ui/winui3-only.v1.json` and `validate_yolkster_cutover.py` stay intact:
their UI checks apply to the preserved `src/gui/HELIOS.Shell` tree and do not
validate or prohibit the Electron workbench. Electron gets separate tests and
Forge package gates. Removing a required check is not a migration strategy.

Update `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` together when
these boundaries change. Shared Claude/Copilot sections must remain identical.
Older WinUI design plans remain useful source material, but their global framework
direction is superseded by this ADR. A completed migration requires evidence of
functional parity and release readiness, not only this decision document.

## Primary references

Verified 2026-09-26; these describe upstream capabilities, not HELIOS completion:

- [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)
- [Electron security](https://www.electronjs.org/docs/latest/tutorial/security)
- [Native Node modules](https://www.electronjs.org/docs/latest/tutorial/using-native-node-modules)
- [Electron Chrome extension support](https://www.electronjs.org/docs/latest/api/extensions)
- [Forge configuration](https://www.electronforge.io/config/configuration) and [Fuses plugin](https://www.electronforge.io/config/plugins/fuses)
- [Electron Fiddle](https://www.electronjs.org/fiddle)
- [Windows Shell Launcher](https://learn.microsoft.com/en-us/windows/configuration/shell-launcher/)
