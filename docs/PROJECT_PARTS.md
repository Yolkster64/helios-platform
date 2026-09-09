# Five parts, one HELIOS repository

Choose the part you are changing; its code, focused checks and release boundary
stay visible together. `Yolkster64/helios-platform` remains the source repository.
These parts share contracts and can be tested separately; they are not new repos
or independently deployed services.

```bash
bash connect.sh parts
bash connect.sh parts cloud
bash connect.sh test fleet
```

PowerShell uses the same arguments: `pwsh ./connect.ps1 parts` and
`pwsh ./connect.ps1 test usb`. The underlying helper is
`python3 scripts/bootstrap/components.py list`, `plan NAME` or `test NAME`.
Listing and planning execute nothing. Only `test NAME` runs its fixed check list.

| Part | Work here | Focused check | Release boundary |
|---|---|---|---|
| **Core** | `src/ai`, `src/mcp` | AIHub/MCP tests and Python analytics contracts | Shared libraries and API; remote hosting belongs to Cloud |
| **Desktop** | `src/gui`, `config/ui` | Repository contract and WinUI build on Windows | Native application; Visual Studio MSBuild is required |
| **USB** | `src/ai/HELIOS.AIHub/Setup`, native USB page | Portable `UsbSetup` planner tests | Non-destructive plan data; no disk or boot execution |
| **Cloud** | `infra`, identity setup helpers | OIDC/identity tests against an inert CLI; Bicep and parameter compilation | `helios-deploy.yml` on `main`, through protected `azure-dev` |
| **Fleet** | AIHub `Fleet`, `scripts/fleet`, fleet topology and Python workers | Fleet readiness/topology/worker tests | Simulation and contracts; actual workers/cloud burst need separate activation |

`config/components.json` maintains descriptions, paths, dependencies, existing CI
workflows and build definitions. It cannot supply shell commands. The runner owns
five fixed test profiles, validates the map against its schema and runs only in
its own reviewed checkout. It never dispatches GitHub workflows, authenticates,
creates repositories or runs deployment/repair scripts.

Plans for Cloud and Fleet identify the existing protected workflow and its
read-only defaults (`what_if=true`, `deploy_confirmed=false`). They do not send a
workflow request. Bicep stays authoritative for HELIOS infrastructure. The shared
runtime's identity, cloud attachment and fleet activation are separate decisions,
with the current owner guidance in [OWNER_START_HERE.md](OWNER_START_HERE.md).

Test output names each executed check and returns a failure status for missing
tools/files, an unsupported host, timeout, nonzero exit or missing/empty .NET test
receipt. Desktop is unavailable on Linux; that is never counted as a passed
Windows build. Python checks require pytest, Cloud's twin-shell contracts require
PowerShell 7, and Bicep must be installed for Cloud compilation. The .NET SDK and
Visual Studio may restore their declared packages during tests; tests do not call
paid models or cloud deployment APIs.

.NET and pytest results use temporary TRX/JUnit counters; the two unittest
suites also check their collected/executed counts. Zero tests or skipped tests
are never reported as a passed component. Focused checks speed up local
work; the repository's required CI gates still apply to the combined change.
The [shared connection guide](CONNECT.md) remains the one starting point.
