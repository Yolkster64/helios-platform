# Cloud Shell & Local Fleet Bring-Up

Operational companion to HERMES_FLEET_AND_XCORE.md (fleet *design*) and
infra/README.md (Azure *resources*): how to get a working cross-LLM shell in Azure
Cloud Shell, how to bring the fleet up on WSL2 / Docker / native Windows, and the
runbook for the opt-in Azure-VM burst capacity.

## Azure Cloud Shell — optimal use

Cloud Shell is the reference hosted environment: `az` is pre-authenticated, `gh`,
`python3`, and PowerShell 7 are in the image, and everything auths by device-code
flow (a URL plus a one-time code you complete in any browser), so the same scripts
work identically from Cloud Shell, a Codespace, an SSH box, or a laptop.

### Bootstrap (device-code auth)

One command brings the shell to readiness — the unified `setup-all` surface
(absorption ledger epic E1):

```bash
pwsh scripts/setup/setup-all.ps1 -Fix           # readiness inventory + install missing AI CLIs
```

It verifies the toolchain (`scripts/build/verify-readiness.ps1`), the GitHub/Azure
auth state (the connect scripts' verify-only modes — read-only, never a login flow),
the AI CLI fleet (`scripts/bootstrap/setup-ai-clis.ps1`; `-Fix` installs what's
missing via npm), the fleet topology, and the MCP registration, then prints one
INVENTORY table with a fix command per gap (`-Json` for machine output; exit 0 ready,
2 attention needed). Auth is never mutated: when the inventory says so, run the
device-code logins yourself — or use the full interactive bring-up, which chains the
auth flows, the smoke test, and the same inventory:

```bash
scripts/bootstrap/cloud-shell-setup.sh          # CLI fleet + both auth flows + smoke test + inventory
```

The pieces, each usable on its own (details in `scripts/bootstrap/README.md`):

| Script | Role |
| --- | --- |
| `scripts/bootstrap/connect-github.sh` | `gh auth login --web` device-code flow. **Source it** to also export `GITHUB_MODELS_TOKEN` from the gh token — flips the `github-models` provider to Ready with no manually-handled key. |
| `scripts/bootstrap/setup-ai-clis.ps1` | Installs/verifies the `cliAgents` CLIs from `config/aihub.json` (`claude`, `codex`, `copilot` via npm; verifies `gh` for gh-models) and prints per-CLI headless-auth guidance. `-VerifyOnly` reports without installing. |
| `scripts/bootstrap/connect-azure.sh` | `az login --use-device-code`; detects Cloud Shell's implicit login and skips. `--subscription <id>` selects a subscription. |
| `scripts/bootstrap/connect-azure.ps1` | Azure PowerShell twin (`Connect-AzAccount -UseDeviceAuthentication`), same Cloud Shell detection. |
| `scripts/bootstrap/load-env-from-keyvault.sh` | **Source it** after Azure login: pulls `openai-api-key` / `anthropic-api-key` / `github-models-token` from the Key Vault at `AZURE_KEY_VAULT_URI` into the env vars `config/aihub.json` names. |
| `scripts/bootstrap/azure-up.sh` / `azure-up.ps1` | End-to-end cloud bring-up: login → resource group → `infra/main.bicep` deployment → writes endpoint wiring to `.helios/azure.env` and points `AIHUB_CONFIG` at `config/aihub.cloud.json`. |

Secrets policy holds throughout: nothing writes a key to disk — `gh`/`az` keep
tokens in their own stores, Key Vault values land only in process environment
variables (CLAUDE.md hard rule).

### What Cloud Shell detection already does

`scripts/fleet/start-fleet.ps1` auto-engages **workspace mode** when the
`CLOUD_SHELL` (or `CODESPACES`) environment variable is set — or force it with
`-Workspace`. Pool sizes are capped to the topology's `workspaceProfile.poolSize`
(else half the declared size, rounded up), because four pools of nine is more
processes than a two-core Cloud Shell should carry. The Python stub worker is the
normal path there (no Hermes CLI in the image); idle stub workers exit on their
own, so seed boards promptly or raise `HERMES_KANBAN_MAX_IDLE_POLLS`.

### Run in Cloud Shell vs run locally

| Run **in Cloud Shell** | Run **locally** (WSL2 / Windows / macOS) |
| --- | --- |
| Control-plane work: `azure-up.sh`, `az deployment group what-if/create`, `bicep build infra/main.bicep --stdout`, Key Vault reads | Anything needing local runtimes: `ollama` (the `offline` route), the real Hermes CLI, Docker |
| Small fleet experiments via the stub (workspace-capped pool sizes) | Full-size fleet runs (`start-fleet.ps1` with all four pools), `scale-fleet.ps1 -Watch` reconciler loops |
| Device-code auth flows (they exist for exactly this environment) | Editor-integrated agents (`copilot` inline completion, `claude`/`codex` CLI sessions against a checkout) |
| `helios-ai status` / `routing` smoke tests against the cloud profile | `dotnet build` / `dotnet test` inner loops (Cloud Shell storage and cores make this slow) |

Cloud Shell sessions are ephemeral and time-limited: treat it as the *auth +
deploy + verify* surface, not as a fleet host. Long-running lanes belong on a
local box or on the VMSS burst capacity below.

## Local fleet bring-up

All three paths read `config/fleet/fleet-topology.json` and honor the same
worker-lane contract (HERMES_FLEET_AND_XCORE.md, "Worker-lane contract").

### WSL2 (and any Linux/macOS shell)

The Linux path works in WSL2 exactly as-is — PowerShell 7 (`pwsh`) plus `python3`
is the only requirement:

```powershell
pwsh scripts/fleet/start-fleet.ps1 -DryRun     # launch plan, touches nothing
pwsh scripts/fleet/start-fleet.ps1             # start every pool (stub when hermes is absent)
pwsh scripts/fleet/fleet-status.ps1            # per-pool running/exited + board tallies
pwsh scripts/fleet/stop-fleet.ps1              # SIGTERM the most recent running run
```

On Unix, workers are launched via `sh -c 'exec … </dev/null >out 2>err'` so each
worker owns its log file descriptors and outlives the launching script. Run state
lives under `.helios/fleet/<runId>/` (boards, logs, manifest). Keep the checkout
on the WSL2 filesystem (`~/…`, not `/mnt/c/…`) — board polling and claim-lock
churn on the 9P mount is an order of magnitude slower.

### Docker (compose fleet profile)

`docker-compose.yml` ships an opt-in **`fleet-stub`** service (profile `fleet`)
running the dependency-free kanban worker against a bind-mounted board — no
network, no provider keys:

```bash
mkdir -p .helios/fleet                       # pre-create so the bind mount isn't root-owned
docker compose --profile fleet up fleet-stub
```

The service polls `/fleet/board.json` (host side: `${FLEET_BOARD_DIR:-./.helios/fleet}`)
forever (`HERMES_KANBAN_MAX_IDLE_POLLS=0`), claims lanes from `FLEET_LANES`
(empty = any lane), and remaps to `${FLEET_UID}:${FLEET_GID}` so claims/locks stay
writable on both sides. Pair it with `docker compose up -d helios-ai-api` for the
hub API on `127.0.0.1:5170`.

### Native Windows (start-fleet.ps1 IsWindows path)

The same `start-fleet.ps1` commands work in Windows PowerShell 7. The `$IsWindows`
branch differs from Unix in two deliberate ways:

- Workers are spawned with `Start-Process -WindowStyle Hidden` (no `sh -c exec`
  wrapper), and the stub is passed `--log-file <path>` so the worker opens its own
  log sink — stdout/stderr redirection through the parent's pipes would die with
  the launching script.
- Stop paths skip the Unix `kill -TERM` graceful phase and use `Stop-Process`
  after the same pid-plus-start-time identity check, so a reused pid is never
  killed by mistake.

Native Windows is also where the real Hermes CLI plus the xcore-9-native pool
belong (Windows SDK, MSVC, GPU — see HERMES_FLEET_AND_XCORE.md, "The four pools").

## Azure-VM burst runbook (fleet VMSS)

### State of the switch: OFF by default, doubly gated

`infra/modules/fleet-vmss.bicep` provisions the burst scale set, but
`infra/main.bicep` deploys it only when **both** gates open:

- `deployFleetVmss` (bool, default `false`), AND
- a non-empty `vmssAdminPublicKey` (string, default `''` — SSH-key-only auth, so a
  keyless VMSS would be undeployable anyway; a public key is not a secret, which is
  why the parameter is deliberately not `@secure()`).

`main.bicep` encodes this as `var fleetVmssEnabled = deployFleetVmss &&
vmssAdminPublicKey != ''`, and `infra/main.bicepparam` pins `deployFleetVmss =
false`, so redeploying the live stack with defaults creates nothing new.

### Enabling burst capacity

What-if first, then deploy, passing your SSH public key at deploy time:

```bash
az deployment group what-if -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters deployFleetVmss=true vmssAdminPublicKey="$(cat ~/.ssh/id_ed25519.pub)"

az deployment group create -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters deployFleetVmss=true vmssAdminPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
```

Sizing knobs (all `infra/main.bicep` params, defaults in parentheses):
`vmssAdminUsername` (`heliosadmin`), `fleetVmSku` (`Standard_B2s`),
`fleetBurstMinInstances` (0 — scale-to-zero), `fleetBurstMaxInstances` (5, the
topology `maxBurstLanes`), `fleetScaleDownIdleSeconds` (300),
`fleetWorkersPerInstance` (2), `fleetPool` (`cloud-burst`), `fleetRepoUrl` /
`fleetRepoRef` (public repo cloned anonymously by cloud-init — never credentials).
The deployment outputs `fleetVmssName` (the `az vmss scale` target) and
`fleetVmssPrincipalId` (grant it `Key Vault Secrets User` if cloud lanes must read
provider keys).

### Wiring the reconciler

`scripts/fleet/scale-fleet.ps1` requests burst capacity when demand exceeds
`maxLocalLanes`, via one absolute `az vmss scale --new-capacity` call per pass.
It needs the `az` CLI on PATH and:

| Env var | Meaning |
| --- | --- |
| `HELIOS_FLEET_VMSS_NAME` | Scale set name — the `fleetVmssName` deployment output |
| `HELIOS_FLEET_VMSS_RG` | Its resource group (e.g. `rg-helios-ai`) |
| `HELIOS_FLEET_VMSS_WORKERS_PER_INSTANCE` | Lanes per instance (default 2 — keep matched to infra's `fleetWorkersPerInstance`) |

Unset vars are advisory, never an error: the pass prints
`burst wanted: N lane(s) (VMSS not configured)` and moves on. The reconciler only
requests capacity; scale-in is left to the scale set's own CPU-driven autoscale
(<25% for `fleetScaleDownIdleSeconds`).

### Known limitation — burst lanes seed EMPTY boards

There is **no shared board transport yet**. Each VMSS instance cloud-inits its own
local seed board (`/var/lib/helios-fleet/boards/<pool>.json`, `{ "tasks": [] }`)
while the host run's boards live on the host filesystem
(`.helios/fleet/<runId>/boards/`). Burst lanes therefore prove the runtime path
(toolchain, systemd lanes, worker contract, outcome attribution via
`HELIOS_FLEET_POOL`) but **do not drain the host queue**. Until shared board
storage lands (Azure Files mount or a queue-backed board — see infra/README.md,
"Fleet burst capacity (VMSS)"), treat the VMSS hook as capacity pre-provisioning,
not as productive throughput.
