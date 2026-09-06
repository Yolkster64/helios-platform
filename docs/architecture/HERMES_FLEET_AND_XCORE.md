# Hermes Fleets & Xcore-9s — Agent Fleet Design

How HELIOS dispatches work to agent fleets: the Hermes Agent's kanban worker-lane system
as the fleet runtime, and **four specialized Xcore-9 pools** — nine workers each, 36
total — every pool with its own Hermes fleet, board, tool grant, and autoscaling policy.
Topology is declarative in `config/fleet/fleet-topology.json`; live bring-up happens in
the hermes/xcore repos (roadmap PR5). This PR ships the HELIOS-side contract and routing.

## Architecture

```
helios-ai route agent_fleet_dispatch "<work item>"
        │  (config/aihub.json: agent_fleet_dispatch → hermes)
        ▼
CliProcessAgent("hermes") ──► hermes chat -q …        (interactive path)
                              hermes kanban board     (fleet path, per pool)
                                    │
   ┌────────────────┬───────────────┼────────────────┬────────────────┐
   ▼                ▼               ▼                ▼                │
xcore-9-code   xcore-9-infra   xcore-9-review   xcore-9-native        │
board:         board:          board:           board:                │
 xcore-code     xcore-infra     xcore-review     xcore-native         │
9 workers ea.  9 workers       9 workers        9 workers             │
codex-led      claude-led      claude-led       claude-led            │
hybrid ≤9      hybrid ≤9       hybrid ≤12       local ≤3              │
   │                │               ▲                │                │
   └────────────────┴───────────────┘────────────────┘                │
        handoffs go through boards, never pool-to-pool calls ─────────┘

each lane:  spawn  hermes -p <assignee> chat -q <prompt>
            env    HERMES_KANBAN_TASK / _DB / _RUN_ID / _CLAIM_LOCK
            exit   kanban_complete | kanban_block | crash
```

## The four pools

| Pool | Does | Leads with | Lanes |
|---|---|---|---|
| **xcore-9-code** | Feature implementation, refactors, tests | Codex → OpenAI → Claude | hybrid, 2 local + 5 burst |
| **xcore-9-infra** | Bicep/ARM, Terraform, Actions, config wiring | Claude → OpenAI | hybrid, 1 local + 6 burst |
| **xcore-9-review** | Code review, security, long-context audit — judges, never authors | Claude → claude-cli | hybrid, 1 local + 8 burst |
| **xcore-9-native** | C++ perf/GPU/kernel, rendering, WinUI 3 shell | Claude → OpenAI → Codex | **local only**, ≤3 |

Specialization is what makes the fleet worth more than 36 identical workers: each pool
carries only the skills, agents, and tools its work needs, so its context stays dense and
its provider chain matches the task's strength profile (see LLM_STRENGTHS_PLAYBOOK.md).
The review pool gets read-only tools deliberately — a reviewer that can edit is a
reviewer that "fixes" instead of reporting.

**xcore-9-native is local-only on purpose.** Native builds need the Windows SDK, the MSVC
toolchain, and a real GPU; generic burst runners have none of those, so bursting would
produce lanes that fail at compile. Switching it to hybrid requires a dedicated ARC scale
set with those labels first.

## Autoscaling (local / hybrid)

Each pool declares `minLocalLanes` kept warm, `maxLocalLanes` on the local host, and
`maxBurstLanes` on ARC runner scale sets. Lanes scale up when board queue depth exceeds
`scaleUpQueueDepth` (default 3) and scale down after `scaleDownIdleSeconds` (default 300)
idle. `mode` is `hybrid`, `local`, or `cloud`.

`scripts/fleet/scale-fleet.ps1` is the reconciler that enforces this policy on a live
run. Each invocation is exactly one reconciliation pass, so it drops straight into cron
or any external loop; `-Watch` adds an internal loop instead:

```powershell
pwsh scripts/fleet/scale-fleet.ps1 -DryRun            # decision table only, touches nothing
pwsh scripts/fleet/scale-fleet.ps1                    # one pass - cron/loop friendly
pwsh scripts/fleet/scale-fleet.ps1 -Watch             # every 60s until Ctrl+C (-IntervalSeconds to change)
```

A pass reads the latest running run's manifest and boards (the same
`.helios/fleet/<runId>/` contract fleet-status/stop-fleet use) and computes, for every
pool with an autoscaling block (the pool's block merged over `defaults.autoscaling`):

```text
queueDepth   = open tasks in the pool's lanes
               + claimed tasks whose 300s claim lease expired (crashed lanes)
desiredLocal = clamp(minLocalLanes, ceil(queueDepth / scaleUpQueueDepth), maxLocalLanes)
```

Scale-up spawns extra workers through start-fleet's spawn contract (same env vars, same
launch mechanics) and records them in the run manifest, so fleet-status and stop-fleet
treat them like any other worker. Scale-down happens only after the pool's queue has
been empty for `scaleDownIdleSeconds` — idle time is tracked as `lastNonEmptyAt` per
pool in `.helios/fleet/scale-state.json` (run-scoped; dry runs never write it) — and
stops the newest excess workers with stop-fleet's identity-verified kill (pid plus
recorded start time, never a stranger's reused pid). A queue that is merely shrinking
never triggers scale-down: excess lanes keep draining it.

**Cloud burst (hybrid pools).** When demand still exceeds `maxLocalLanes`, the excess
lanes (per pool capped at `maxBurstLanes`, and the sum capped at the participating
pools' combined `maxBurstLanes`) are aggregated across pools and offered to one Azure
VMSS. Lanes are not instances: each instance runs
`HELIOS_FLEET_VMSS_WORKERS_PER_INSTANCE` worker lanes (default 2, matching infra's
`fleetWorkersPerInstance`), and `az vmss scale` sets an absolute capacity, so a pass
makes at most one call. With the `az` CLI on PATH and `HELIOS_FLEET_VMSS_NAME` +
`HELIOS_FLEET_VMSS_RG` set (naming the scale set the `infra/` parameters provision),
that call is `az vmss scale --new-capacity ceil(totalBurstLanes / workersPerInstance)`;
otherwise the pass prints a `burst wanted: N lane(s) (VMSS not configured)` notice and
moves on — unconfigured burst is advisory, never an error. The reconciler only requests
capacity; VMSS scale-in is left to the scale set's own policy.

Every scaling action appends one advisory line to `.helios/fleet/scale-log.jsonl` so
the learning/insights side can correlate scaling decisions with task outcomes later:
local scales as `{at, pool, from, to, reason, burst: 0}`, an actual burst call as one
aggregate `{at, pool: "vmss-burst", pools, burst, instances, workersPerInstance,
reason}` entry listing the contributing pools.

Keeping a floor of warm local lanes matters more than it looks: the first lane on a cold
burst runner pays image pull plus toolchain setup, so a small always-on floor is what
makes short tasks feel instant while long queues still get cloud width.

## Tandem learning

The fleet feeds the hub's learning store without ever steering it. One cycle:

1. **Run and drain boards** — a fleet run (stub or real Hermes) works its pool
   boards as usual; every task ends on the board as `done` or `blocked`.
2. **Collect** — `python3 -m helios_agents fleet-collect --run-dir <runDir>
   --outcomes .helios/learning/outcomes.jsonl` turns finished board tasks into
   learning records tagged `source: "fleet-lane"` with provider `pool:<name>`
   (`src/ai/python/helios_agents/fleet_learning.py`); a sidecar ledger
   (`<outcomes>.fleet-collected.json`) keeps re-collection idempotent.
3. **Summarize** — `python3 -m helios_agents fleet-summary` reports per-pool
   tasks / blocked / block-rate over the fleet-lane records and correlates them
   with the scaling decisions in `.helios/fleet/scale-log.jsonl` (a `vmss-burst`
   entry credits every contributing pool).
4. **Advise** — `helios-ai fleet-plan [--topology <path>] [--json]` scores each
   pool's configured `providerChain`, per task type, against the order the hub's
   learned routing would prefer — the same F#-linear + native-neural
   `ChainReorderEngine` that routing uses — from **organic hub history only**.
   Each row is `{pool, taskType, configuredChain, learnedChain, sampleCount,
   engine (none|linear|neural)}`; the MCP twin is `helios_fleet_plan_get`.

**One command**: `pwsh scripts/fleet/learn-fleet.ps1` runs the whole cycle —
start (or attach with `-RunId`), seed synthetic tasks across every pool board
through the lock-aware enqueue, drain, stop, collect, summarize, advisory
plan — and writes `.helios/fleet/learning-report.json` (`{at, runId, seeded,
drained, collected, summary, fleetPlan}`); missing collect/summary/plan ops
degrade with a warning, never a failure.

**CI lane**: `.github/workflows/fleet-learning.yml` (**Fleet Learning
(informational)**) runs one stub cycle weekly (Mondays 04:41 UTC) and on
dispatch, with a runner choice — `ubuntu-latest` by default, `self-hosted` for
local-runner soak testing (pwsh + python3 assumed preinstalled). Informational
by contract: never make it a required check.

**Azure backend (opt-in)**: `deployLearningStorage=true` on `infra/main.bicep`
provisions `infra/modules/learning-storage.bicep` — a storage account plus the
`aihubOutcomes` table — and outputs the table endpoint to set as
`AZURE_LEARNING_TABLE_ENDPOINT`, which enables `learning.mode=azure` (or
`hybrid`). Off by default; the hub records to local JSONL
(`.helios/learning/outcomes.jsonl`) regardless.

**Honest boundaries.** Everything in this loop is advisory. Topology and
provider chains are config (`config/fleet/fleet-topology.json`) and are never
auto-mutated — `fleet-plan` / `helios_fleet_plan_get` only report. Fleet-lane
records never steer provider chains: `ChainReorderEngine.OrganicOnly` filters
the history the reorder engines see down to organic hub outcomes, so
`pool:<name>` records — lane outcomes, not provider outcomes — cannot influence
routing. And a green stub cycle proves the *wiring* (boards, claims,
terminations, collection contract), never model quality or routing improvement.

## Cross-pool coordination

Pools are peers and **never call each other directly** — the same hub-and-spoke rule the
languages follow. Work moves by handing a task to another pool's board, so every handoff
is recorded and replayable: code → review on completion, infra → review on authoring,
native → review when the interop boundary changes, and review → code when findings need
a fix.

- **HELIOS is the hub**: fleet dispatch is just another AIHub task type, so MCP clients
  (Claude Code, Copilot, Codex) can feed the fleet through `helios_ai_route` without
  knowing Hermes exists.
- **Hermes is the fleet runtime**: its kanban dispatcher runs either one-task mode or
  fleet mode (all non-archived tasks + events/runs), with per-board SQLite state.
  Contract reference: `hermes-agent-github/website/docs/user-guide/features/kanban-worker-lanes.md`.
- **Xcore-9s is capacity, not code**: nine worker identities (`xcore-1`…`xcore-9`)
  claiming tasks tagged for the pool's task types. Resize by editing `poolSize` — no
  code change. The name is config (`"xcore-9s"`), also not code.

## Worker-lane contract (what every lane must honor)

1. Spawned as `hermes -p <assignee> chat -q <prompt>` with the four `HERMES_KANBAN_*`
   env vars present.
2. Terminates through `kanban_complete` (result recorded) or `kanban_block`
   (reason recorded, task returns to the board). A crash releases the claim lock.
3. Lanes never talk to each other — coordination goes through the board (Kanban DB),
   mirroring the platform's hub-and-spoke rule.

## Setup runbook (PR5 executes this)

1. Install the Hermes CLI on the fleet host; `hermes` must be on PATH
   (`helios-ai status` then shows the `hermes` provider Ready).
2. Provision provider keys for workers via the HELIOS Key Vault (workers use the same
   env-var contract as the hub — no keys in Hermes config). Use the
   `keyvault-secrets-agent` and `identity-access-agent` so each pool's workers get a
   managed identity with `Key Vault Secrets User` rather than a shared static key.
3. Create one board per pool (`xcore-code`, `xcore-infra`, `xcore-review`,
   `xcore-native`) and register its nine assignees (`xcode-1…9`, `xinfra-1…9`,
   `xreview-1…9`, `xnative-1…9`); set each pool's `maxConcurrentLanes` to bound parallel
   lanes independently of pool size.
4. Wire the gateway webhook (hermes `gateway/platforms/webhook.py`) if GitHub-event-driven
   dispatch is wanted; PR-review prompts must treat PR titles/bodies as untrusted input.
5. Dashboards: Hermes kanban dashboard plugin per board; HELIOS-side visibility arrives
   with the WinUI 3 AIHub page (GUI_THEME_ANALYSIS.md).

## Local & workspace bring-up

The topology is runnable today, before PR5: `scripts/fleet/` reads
`config/fleet/fleet-topology.json` and brings pools up on any box with
PowerShell 7 — with the real Hermes CLI when it is on PATH, else a local stub.

```powershell
pwsh scripts/fleet/start-fleet.ps1 -DryRun                    # show the launch plan, touch nothing
pwsh scripts/fleet/start-fleet.ps1                            # start every pool
pwsh scripts/fleet/start-fleet.ps1 -Fleet xcore-9-code -PoolSize 3
pwsh scripts/fleet/fleet-status.ps1                           # per-pool running/exited + board tallies
pwsh scripts/fleet/fleet-status.ps1 -Json                     # machine-readable report
pwsh scripts/fleet/scale-fleet.ps1 -Watch                     # autoscaling reconciler (see Autoscaling section)
pwsh scripts/fleet/stop-fleet.ps1                             # SIGTERM the most recent running run
pwsh scripts/fleet/stop-fleet.ps1 -RunId <id>                 # stop a specific run (-All for every run)
```

`-Fleet` takes a pool name (`xcore-9-code`) or its board (`xcore-code`);
default `all`. Per run, start-fleet creates `.helios/fleet/<runId>/` (gitignored)
holding one JSON kanban board per pool (`boards/<board>.json`), worker logs
(`logs/`), and the `manifest.json` (pids, boards, locks) that fleet-status and
stop-fleet read. Every worker is launched with the four contract vars exported:
`HERMES_KANBAN_TASK` (the pool's task types, comma-separated — its lanes),
`_DB` (the board file), `_RUN_ID`, and `_CLAIM_LOCK` (the lockfile guarding
board mutations).

**Stub vs real Hermes.** When `hermes` is on PATH, lanes spawn through the
topology's spawn template (`hermes -p <assignee> chat -q <prompt>`). When it is
not, start-fleet prints a notice and falls back — never a crash — to the
dependency-free stub `python3 -m helios_agents.fleet_worker`
(src/ai/python), which honors the same worker-lane contract: poll the board,
claim open tasks in its lanes under the claim lock, resolve each as
`kanban_complete` (status `done`, result recorded) or `kanban_block` (status
`blocked`, reason recorded), release the lock on crash (stale-lock breaking),
and exit 0 on SIGTERM or after `HERMES_KANBAN_MAX_IDLE_POLLS` empty polls
(start-fleet defaults the stub to 2s polls, ~2 minutes idle). The stub does no
model work — it exists to exercise the fleet wiring end to end.

Environment-specific bring-up lives in CLOUD_SHELL_AND_LOCAL_FLEET.md: the Azure
Cloud Shell device-code auth bootstrap (`scripts/bootstrap/`), the WSL2 / Docker
(`fleet-stub` compose profile) / native-Windows fleet paths, and the runbook for
the opt-in Azure-VM burst capacity (`deployFleetVmss` + `scale-fleet.ps1`'s
`HELIOS_FLEET_VMSS_*` wiring). This page stays the fleet *design* reference.

Feed a live board through the lock-aware enqueue — workers mutate the board
under the claim lock, which a hand editor does not take, so hand-appending to
a board whose workers are running can be silently lost to a concurrent worker
save. From `src/ai/python`, with `HERMES_KANBAN_DB` / `HERMES_KANBAN_CLAIM_LOCK`
set to the run's board and lock (the manifest's `db` / `claimLock`):

```bash
python3 -m helios_agents.fleet_worker --enqueue \
  '{ "id": "T-1", "lane": "code_generation", "status": "open",
     "prompt": "add retry to the router" }'
```

Seeding a board by hand *before* its workers start is still fine (and the stub
tolerates torn reads, so a hand edit shows up as an idle poll, never a crash).

A task whose `lane` is not in the pool's task types is never claimed; one with
`"block": true` (or no prompt) exercises the `kanban_block` path.

**Codespaces / Cloud Shell.** Workspace mode engages automatically when
`CODESPACES` or `CLOUD_SHELL` is set (or force it with `-Workspace`): pool
sizes are capped to the topology's `workspaceProfile.poolSize` (per-pool or
defaults) when one is declared, else to half the declared size rounded up —
four pools of nine is more processes than a two-core workspace should carry.
An explicit `-PoolSize` is still subject to the cap. The stub is the normal
path there (no Hermes CLI in the image); idle workers exit on their own, so
seed boards promptly or raise `HERMES_KANBAN_MAX_IDLE_POLLS`.

## Parallelism model

Four independent throttles, tuned separately:

| Layer | Knob | Where |
|---|---|---|
| Model capacity (tokens/min) | `modelCapacity` / `additionalModelDeployments[].capacity` | `infra/main.bicepparam` |
| Fleet lanes per pool | `maxConcurrentLanes`, `poolSize`, `autoscaling.*` | `config/fleet/fleet-topology.json` |
| Burst runner capacity | `minRunners` / `maxRunners` per scale set | ARC values (GITHUB_ECOSYSTEM_DESIGN.md) |
| Hub fan-out | `CompareAsync` provider list; per-provider circuit breakers | `config/aihub.json` chains |

With four pools bursting concurrently the ceiling is 36 lanes, so size model capacity
against the sum, not against one pool. Pools leading with different providers is itself a
throttle: code (Codex/OpenAI) and review (Claude) draw on separate quotas, so a saturated
implementation queue does not starve reviews.

Backpressure flows naturally: a 429 at the model layer fails the lane's call → the lane
blocks the task → the board holds it until capacity returns; the hub's circuit breaker
meanwhile routes other traffic to fallback providers.
