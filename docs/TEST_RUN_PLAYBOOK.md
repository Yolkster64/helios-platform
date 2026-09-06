# Test-Run Playbook

Copy-pasteable smoke runs for every surface in the repo, with the outcome you should
expect from each. Run them top to bottom for a full shakedown, or jump to the surface you
are touching. All commands run from the repo root unless noted.

Legend for requirements:

- **Keyless** — works with zero provider credentials configured.
- **Needs credentials** — marked inline; nothing below silently requires a secret.
- **Windows-only** — marked inline; everything else runs on Linux/macOS/WSL2 too.

Prerequisites for the core lanes: .NET SDK 8, PowerShell 7 (`pwsh`), Python 3.10+, Git.
Optional lanes need Docker, a Bicep compiler (`bicep` or `az`), or Terraform — each lane
says so. `pwsh scripts/build/verify-readiness.ps1` checks your box in one command.

## 1. Setup: `setup-all.ps1` (keyless)

```bash
pwsh scripts/setup/setup-all.ps1            # human table
pwsh scripts/setup/setup-all.ps1 -Json      # machine-readable; nothing else on stdout
pwsh scripts/setup/setup-all.ps1 -Fix       # also installs missing AI CLIs via npm
```

**Expected**: an `== INVENTORY ==` table (or JSON object) with one row per component —
`toolchain`, `github-auth`, `azure-auth`, `ai-clis`, `fleet-topology`,
`mcp-registration` — each `ready` or `needs-attention` with a `Next command` to fix.

- Exit code **0** = every component ready; **2** = at least one needs attention. A 2 on a
  fresh box is normal (auth not done yet, CLIs not installed yet) — it is a to-do list,
  not a failure.
- Auth is **never** mutated in any mode. When the inventory flags `github-auth` or
  `azure-auth`, run the device-code logins yourself:
  `scripts/bootstrap/connect-github.sh` / `scripts/bootstrap/connect-azure.sh`.
- `-Json` semantics: the object has `ready` (bool) and `components[]` with
  `component`/`status`/`detail`/`nextCommand`; pipe to `ConvertFrom-Json` or `jq`.

## 2. Build + tests (keyless)

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release --no-build
(cd src/ai/python && python3 -m pytest tests -q)
```

**Expected**:

- Build: `0 Error(s)` (warnings exist and are tolerated). If errors mention
  `src/core/HELIOS.Platform`, you re-added the deliberately excluded core project — see
  `CLAUDE.md`.
- .NET tests: `Passed! - Failed: 0, Passed: 124, ...` (124 as of this writing; the
  count only grows — `Failed: 0` is the invariant).
- Python spoke: `68 passed` (68 as of this writing) on the dependency-free path. Tests
  needing numpy/scikit-learn only run after `pip install '.[ml]'` — their absence is not
  a failure.

Optional native spoke (needs CMake + a C++ compiler; AIHub degrades to managed fallbacks
without it):

```bash
./scripts/build/build-native.sh
```

## 3. CLI smokes (keyless)

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- status
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- engines
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- absorb-status
```

**Expected**:

- `status`: one line per provider — `✓ ... Ready` or `· ... Unconfigured` with the exact
  env var to set (e.g. `Set ANTHROPIC_API_KEY (or configure the Key Vault secret
  'anthropic-api-key')`). All-`Unconfigured` on a keyless box is correct behavior.
- `engines`: a JSON engine catalog with `"total_engines"`, per-engine
  `"maturity"`/`"runtime_available"`, and a `"truthfulness"` note. Deterministic and
  local — no network.
- `absorb-status`: a JSON summary of `config/absorption/pr-watchlist.json` — `"upstream"`,
  `"total"`, `"by_status"` (e.g. `candidate`/`benchmarked`), and the candidate list.

**Needs credentials**: `ask`, `route`, `tandem`, and `compare` call real providers — at
least one provider env var (or a running `ollama`) must be configured, and tokens cost
money. They are deliberately not part of the keyless smoke.

## 4. REST API (keyless to run; key only for non-loopback)

Terminal 1:

```bash
dotnet run --project src/ai/HELIOS.AIHub.Api -c Release
```

Terminal 2:

```bash
curl http://localhost:5170/healthz         # expect: {"status":"ok"}
curl http://localhost:5170/v1/status       # expect: JSON provider array (same as CLI status)
```

**Access-key behavior** (the thing to verify before exposing the API anywhere):

- Loopback callers never need a key — the two curls above return 200 with no header.
- Any non-loopback caller gets **HTTP 401** unless `HELIOS_API_ACCESS_KEY` is set on the
  server and the caller sends the same value as `X-HELIOS-Api-Key`. The easiest honest
  way to see the 401 is through Docker's bridge — see the Docker lane below.
- The key is a local gate only; hosted use still needs identity-aware ingress in front.

## 5. MCP server (keyless for the read-only tools)

Registered in `.mcp.json`; Claude Code started in the repo root picks it up
automatically (verify with `/mcp`). To poke it interactively without a client:

```bash
npx @modelcontextprotocol/inspector -- dotnet run --project src/mcp/HELIOS.Mcp -c Release
```

**Expected**: the inspector lists the `helios_*` tools (`helios_ai_status`,
`helios_providers_list`, `helios_task_routing_get`, `helios_engine_catalog_get`,
`helios_engine_mix_recommend`, `helios_infra_validate`, `helios_absorb_status_get`,
`helios_fleet_status_get`, `helios_foundry_agent_list`, `helios_foundry_agent_create`,
the operator-context tools `helios_operator_profile_get`/
`profile_save`/`context_sync`/`next_steps_get`, plus the provider-calling
`helios_ai_ask`/`route`/`tandem`/`compare`). Calling `helios_ai_status` returns the same
readiness data as the CLI.

**Needs credentials**: the `helios_ai_*` provider-calling tools and the two Foundry
tools; everything else named `*_get`/`*_list`/`helios_infra_validate` is a local read.
The Foundry pair is NOT local: with `AZURE_FOUNDRY_PROJECT_ENDPOINT` set,
`helios_foundry_agent_list` authenticates via `DefaultAzureCredential` and reads the
Azure project (a credentialed Azure read, despite the `_list` name), and
`helios_foundry_agent_create` is a credentialed Azure **mutation** that persists an
agent on the project; with the endpoint unset, list degrades to `{ configured: false }`
and create refuses. `helios_infra_validate` also needs a Bicep compiler on PATH.
`helios_operator_profile_save` and `helios_operator_context_sync` write only gitignored
files under `.helios/operator/`; Azure inventory is opt-in, read-only, and degrades to a
`not-authenticated` status without an `az login`. Client wiring for Copilot/Codex/Cursor:
`docs/mcp/CLIENT_SETUP.md`.

## 6. Docker (needs Docker; keyless)

API container:

```bash
export HELIOS_API_ACCESS_KEY='replace-with-a-local-secret'
docker compose up --build -d helios-ai-api

curl http://localhost:5170/healthz                       # expect: {"status":"ok"}
curl -i http://localhost:5170/v1/engines                 # expect: HTTP 401 — no key sent
curl -H "X-HELIOS-Api-Key: $HELIOS_API_ACCESS_KEY" \
  http://localhost:5170/v1/engines                       # expect: 200, engine catalog JSON
```

The 401 is the compose-specific check: host traffic crosses Docker's bridge, so Kestrel
does not see it as loopback and the access key is enforced. That is the designed
behavior, not a regression. Tear down with `docker compose down`.

Fleet-stub profile (no network, no provider keys, no model work):

```bash
mkdir -p .helios/fleet
export FLEET_UID="$(id -u)" FLEET_GID="$(id -g)"
docker compose --profile fleet up fleet-stub
```

**Expected**: the `fleet-stub` service starts and polls `/fleet/board.json` forever
(`HERMES_KANBAN_MAX_IDLE_POLLS=0`). With no board seeded it idles — stop it with
Ctrl-C, or feed it. Note the compose stub reads **only** `.helios/fleet/board.json`;
the fleet lane's `seed-absorption-tasks.ps1` seeds a *running fleet run's* per-pool
boards (`.helios/fleet/<runId>/boards/…`), a different surface this container never
polls. Feed the compose board with the lock-aware enqueue instead:

```bash
[ -f .helios/fleet/board.json ] || echo '{"tasks": []}' > .helios/fleet/board.json
(cd src/ai/python && HERMES_KANBAN_DB="$(git rev-parse --show-toplevel)/.helios/fleet/board.json" \
  python3 -m helios_agents.fleet_worker --enqueue \
  '{"id": "demo-1", "lane": "code_generation", "status": "open", "prompt": "demo task"}')
```

## 7. Local fleet (keyless; stub workers unless Hermes is installed)

Order matters: `seed-absorption-tasks.ps1` and `fleet-status.ps1` operate on a *running*
run, so start one first.

```bash
pwsh scripts/fleet/start-fleet.ps1 -DryRun
```

**Expected**: a `Fleet plan` listing the four pools from
`config/fleet/fleet-topology.json` (`xcore-9-code`, `xcore-9-infra`, `xcore-9-review`,
`xcore-9-native`, 9 workers each) and `Dry run - nothing created, nothing started.`
Without the Hermes CLI on PATH you also get a NOTICE that workers fall back to the local
Python stub — expected on most boxes.

Real single-worker run, seed, status, stop:

```bash
pwsh scripts/fleet/start-fleet.ps1 -Fleet xcore-9-infra -PoolSize 1
pwsh scripts/fleet/seed-absorption-tasks.ps1 -DryRun -Max 2   # plan only; -Board defaults to xcore-infra
pwsh scripts/fleet/seed-absorption-tasks.ps1 -Max 2           # actually enqueue 2 tasks
pwsh scripts/fleet/fleet-status.ps1                           # per-pool running/exited + board tallies
pwsh scripts/fleet/stop-fleet.ps1                             # SIGTERM the most recent running run
```

**Expected**: run state appears under `.helios/fleet/<runId>/` (boards, logs, manifest);
`fleet-status` shows the worker and task counts; re-seeding is idempotent (existing
`absorb-pr-<N>` task ids are skipped). Running `seed-absorption-tasks.ps1` or
`fleet-status.ps1` with **no** run started fails with a pointer to `start-fleet.ps1` —
that error is the designed guidance, not a bug. Stub workers claim tasks but do no model
work. On WSL2 keep the checkout on the Linux filesystem (`~/…`, not `/mnt/c/…`).

Scale reconciler (advisory without Azure config):

```bash
pwsh scripts/fleet/scale-fleet.ps1 -DryRun
```

**Expected**: a single reconcile pass. With no running fleet run it prints
`nothing to reconcile` and exits cleanly; during a run, without the
`HELIOS_FLEET_VMSS_*` env vars, any burst demand prints `VMSS not configured` and moves
on (advisory, never an error).

## 8. Absorption benchmark (keyless; needs Git + network to github.com)

Benchmark one watchlist PR (see `helios-ai absorb-status` for current candidates — #294
is one as of this writing):

```bash
pwsh scripts/absorption/absorb-pr.ps1 -PrNumber 294
```

> **Trust boundary (enforced)**: the gate *executes the merged tree* — the candidate
> PR's own `build-native.sh`, MSBuild targets, and pytest conftests run on your
> machine with your environment. The script now **refuses (exit 3)** on a
> credential-bearing host (provider API keys in env, or `~/.config/gh` / `~/.azure`
> present) unless you pass `-AcceptCredentialExposure` or set
> `HELIOS_ABSORB_ACCEPT_CREDENTIALS=1`. For a PR you haven't read, use the keyless
> hosted lane, which runs the same script on a disposable runner with a read-only
> token and no secrets (it sets the opt-in itself), and publishes the report as an
> artifact:
>
> ```bash
> gh workflow run absorption-benchmark.yml -f pr_number=294
> ```

**Expected**: the script fetches the upstream PR head (`M0nado/helios-platform` —
public, read-only, no credentials), trial-merges it in a disposable worktree, runs the
same gate CI runs, and writes a scored report to `.helios/absorption/pr-222.json` with
per-step results and a verdict. **A merge-conflict outcome is a valid result** — the
report records the conflicting files and the verdict; it is evidence, not a failed run.
Nothing merges automatically; `-Apply` only keeps the scratch worktree for deliberate
cherry-picking. Each benchmark also POSTs an advisory outcome to a running
`helios-ai-api` if one is reachable — best-effort, silently skipped otherwise.

Afterwards, update the PR's `status` in `config/absorption/pr-watchlist.json`
(`candidate → benchmarked → absorbed | rejected`) with the reason.

## 9. Infra validation (read-only; needs `bicep` or `az`, plus Terraform for its lane)

Bicep (the source of truth):

```bash
bicep build infra/main.bicep --stdout >/dev/null           # or: az bicep build --file infra/main.bicep
az bicep build-params --file infra/main.bicepparam --stdout >/dev/null
```

**Expected**: exit 0, no output. Nothing touches a subscription.

ARM freshness (the generated mirror must not drift — CI enforces this on every
`infra/**` PR):

```bash
bicep build infra/main.bicep --outfile infra/arm/main.json
git diff --stat infra/arm/main.json
```

**Expected**: no diff, or a diff confined to `metadata._generator` (Bicep CLI
version/templateHash — CI strips that before comparing, so a toolchain version bump alone
never fails the gate). Any other diff means the Bicep changed without regenerating the
ARM mirror: commit the regenerated file. Never hand-edit `infra/arm/main.json`.

Terraform mirror (validate-only; no backend, no cloud access):

```bash
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform validate
```

**Expected**: `fmt -check` silent, `validate` prints `Success! The configuration is
valid.` Remember: Terraform is an independent mirror — changes land in Bicep first
(`infra/README.md`, "Three dialects").

## 10. GUI shell (Windows-only)

The shell builds only on Windows, from its own solution — it is deliberately not in
`HELIOS.sln`:

```powershell
dotnet build src/gui/HELIOS.Shell.sln -c Debug -p:Platform=x64
dotnet run --project src/gui/HELIOS.Shell/HELIOS.Shell.csproj -p:Platform=x64
```

**Expected**: with `helios-ai-api` running (lane 4), the dashboard shows live provider
readiness; without it, a graceful "API not running" warning with the resolved URL — that
state is expected, not a bug. Full build requirements, access-key wiring, and the
contribution rules: [`src/gui/README.md`](../src/gui/README.md).

## Quick reference: what needs what

| Lane | Credentials | Extra tools | Platform |
|---|---|---|---|
| setup-all, build+tests, CLI smokes, MCP reads | none | — | any |
| CLI `ask`/`route`/`tandem`/`compare`, MCP `helios_ai_*` | ≥1 provider key (or ollama) | — | any |
| REST API local | none (key only for non-loopback) | — | any |
| Docker lanes | none (compose sets a local-only key) | Docker | any |
| Fleet local | none | pwsh + python3 | any (stub); Hermes CLI optional |
| Absorption benchmark | none | Git + network to github.com | any |
| Infra validation | none | bicep/az; terraform | any |
| GUI shell | none | .NET 10 SDK (global.json) + .NET 8 desktop runtime (shell TFM) + Windows App SDK runtime | **Windows** |
