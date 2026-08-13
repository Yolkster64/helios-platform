# Parallelization & fleets — how Python work scales in HELIOS

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.*

Scope: the process model around `src/ai/python` — who fans out, who is throttled where,
and what a Python module may and may not spawn. Plus an honest multi-modal readiness
statement at the end.

## The four-process cap (the C# side of the boundary)

`PythonInsightsSpoke` (`src/ai/HELIOS.AIHub/Learning/PythonInsightsSpoke.cs`) is the
only class that talks to the Python spoke, and it enforces the concurrency bound:

- `SemaphoreSlim ProcessSlots = new(initialCount: 4, maxCount: 4)` — at most four live
  `python -m helios_agents` children, hub-wide (the field is `static`).
- `Timeout = TimeSpan.FromSeconds(30)` per invocation; a timed-out spoke returns `null`
  (advisory-data loss, never an orchestration failure).
- Cleanup is `process.Kill(entireProcessTree: true)`; if the OS cannot confirm exit,
  the slot is deliberately **not** released — the hub would rather run with three slots
  than admit a fifth live child.
- Unconfigured/missing interpreter degrades to `null` results, never an exception.

Rules for spoke ops that follow from this: an op must finish well under 30 s on
plausible inputs; it must be a single process — anything it spawns dies with it under
the tree-kill and would evade the cap while alive; and it must not hold state between
calls (each invocation is a fresh process). The C# hub owns fan-out: if a job needs
four parallel analyses, the hub makes four `InvokeAsync` calls and the semaphore
schedules them — the Python side never widens itself.

C# wrapper methods exist for `provider_summary`, `detect_drift`, `group_similar`,
`engine_catalog`, and `recommend_engines` (`PythonInsightsSpoke.cs`); the `keywords`
and `fleet_collect`/`fleet_summary` ops are on the same stdin boundary
(`helios_agents/__main__.py` `_OPS`) but are invoked today by scripts
(`scripts/fleet/learn-fleet.ps1`) rather than by the C# class.

## asyncio / multiprocessing: where they are (and are not)

Verified by grep over `src/ai/python`: there is **no** `asyncio`, `multiprocessing`, or
`concurrent.futures` anywhere in the spoke today. The only concurrency primitive in
production code is `threading.Event` as `fleet_worker`'s stop signal (set by its
SIGTERM/SIGINT handler), plus one thread in a lock-contention test.

That is the design, not a gap:

- Ops under the subprocess boundary are synchronous by contract — one request, one
  response, exit. Parallelism belongs to the caller (the semaphore above, or fleet
  lanes below).
- The SKILL's asyncio fan-out section applies to standalone agents that coordinate
  multiple LLM sub-calls routed back through the hub; no shipped spoke module does
  that, so do not add an event loop to `helios_agents` to "speed up" an op — split the
  input at the C# side instead.
- `multiprocessing` inside an op would multiply the four-process cap invisibly and its
  children are killed mid-write by the tree-kill. If an op is too slow, that is a
  signal the work belongs in the hub or the fleet, not in a wider spoke.

## The fleet worker-lane model (process-level parallelism)

Real scale-out is worker lanes polling kanban boards —
`docs/architecture/HERMES_FLEET_AND_XCORE.md` is the design reference; the
dependency-free stub `helios_agents/fleet_worker.py` implements the same contract for
boxes without the Hermes CLI (start-fleet falls back to it automatically, never a
crash).

Claim-lock protocol (`fleet_worker.py`):

- Board mutations happen only under a lockfile taken with `O_CREAT | O_EXCL`
  (`acquire_claim_lock`); the lock payload records `{pid, assignee, lockedAt}`.
- Stale locks are broken: dead holder pid (POSIX `os.kill(pid, 0)` probe) or, where no
  pid check is possible, age beyond `lock_stale_seconds` (default 30 s). A live holder
  makes the caller time out (`lock_timeout_seconds`, default 5 s) and just poll again.
- A claim is a lease, not ownership: a `claimed` task whose `claimedAt` is older than
  `claim_lease_seconds` (default 300 s) is claimable again, so a crashed lane never
  strands work.
- Board saves are atomic (tmp + `os.replace`), and a torn board read is an idle poll,
  never a lane crash.
- External appends must go through the lock-aware enqueue
  (`python3 -m helios_agents.fleet_worker --enqueue '<task JSON>'`) — hand-editing a
  live board loses tasks to concurrent worker saves.

Lifecycle: lanes poll (`poll_seconds`, code default 1.0 s; `start-fleet.ps1` exports
`HERMES_KANBAN_POLL_SECONDS=2` and `HERMES_KANBAN_MAX_IDLE_POLLS=60` for the stub,
about two minutes of idle), claim the first open task in their lanes
(`HERMES_KANBAN_TASK` spec; empty or `*` claims any), resolve it as `kanban_complete`
(status `done`, result) or `kanban_block` (status `blocked`, reason), and exit 0 on
SIGTERM/SIGINT or after `max_idle_polls` consecutive empty polls. Lanes never talk to
each other — coordination goes through the board, mirroring the hub-and-spoke rule.

## Throttle layers (platform-wide)

The table in HERMES_FLEET_AND_XCORE.md "Parallelism model" lists four layers (its
prose says "Three independent throttles" — trust the table):

| Layer | Knob | Where |
|---|---|---|
| Model capacity (tokens/min) | `modelCapacity` / `additionalModelDeployments[].capacity` | `infra/main.bicepparam` |
| Fleet lanes per pool | `maxConcurrentLanes`, `poolSize`, `autoscaling.*` | `config/fleet/fleet-topology.json` |
| Burst runner capacity | `minRunners` / `maxRunners` per scale set | ARC values (GITHUB_ECOSYSTEM_DESIGN.md) |
| Hub fan-out | `CompareAsync` provider list; per-provider circuit breakers | `config/aihub.json` chains |

(The spoke's four-process cap sits below all of these, bounding only advisory
analytics.) With four pools bursting, the ceiling is 36 lanes — size model capacity
against the sum. Backpressure composes: a 429 fails the lane's call → the lane blocks
the task → the board holds it until capacity returns, while the hub's circuit breaker
routes other traffic to fallbacks (HERMES_FLEET_AND_XCORE.md). Note `engines.py`'s
`PARALLELIZATION_CANDIDATES` ("task-parallel", "fleet-swarm-parallel", …) are all
maturity `concept` — advisory vocabulary, never selected or executed.

## The tandem learning cycle (how the spoke gets invoked)

`scripts/fleet/learn-fleet.ps1` runs one cycle end to end: start (or `-RunId` attach) a
fleet run → seed synthetic tasks via the lock-aware enqueue (default 12, round-robin
across pool boards, every 6th a `block`-path task) → drain by polling
`fleet-status.ps1 -Json` every 5 s → `stop-fleet.ps1` → then the spoke's fleet ops from
`src/ai/python`:

```
python3 -m helios_agents fleet-collect --run-dir <runDir> --outcomes .helios/learning/outcomes.jsonl
python3 -m helios_agents fleet-summary --outcomes .helios/learning/outcomes.jsonl --scale-log .helios/fleet/scale-log.jsonl
```

`fleet-collect` (`helios_agents/fleet_learning.py`) turns resolved board tasks into
JSONL records that mirror the C# `RoutingOutcome` field-for-field (`source:
"fleet-lane"` marks them advisory; the contract test in
`references/testing-and-libraries.md` pins the field names), deduped by a sidecar index
so re-collection is idempotent. `fleet-summary` computes per-pool block rates and mean
latencies, correlating `scale-log.jsonl` scale/burst events when offered. The cycle
ends with an advisory `fleet-plan` (soft-degrade, never auto-executed) and writes
`.helios/fleet/learning-report.json`.

## Multi-modal readiness (honest)

What is actually declared today — verified against the config files:

- `config/model-catalog.json`: each model carries `provider`, `model`, `class`,
  `contextTokens`, prices, `relativeSpeed`, `strengths` (plus optional `note`). There
  is **no vision, audio, image, or modality field of any kind**; `strengths` are text
  task types ("Task types (config/aihub.json taskRouting keys)" per the schema), and
  `config/schemas/model-catalog.schema.json` sets `additionalProperties: false`, so an
  undeclared capability flag would fail CI validation.
- `config/aihub.json`: providers declare `type`/`model`/key-or-endpoint env names only;
  no `taskRouting` key is vision- or audio-shaped.
- The hub's wire type is text-only: `ChatRequest(Prompt, System, Model, TaskType,
  MaxTokens, Temperature)` and `ChatResult.Text`
  (`src/ai/HELIOS.AIHub/Abstractions/ChatModels.cs`).
- The only modality-adjacent strings in the platform: `engines.py`'s
  `gaussian-blur-anomaly` candidate (family `"vision"`, maturity `concept` — a
  recovered prototype, never implemented) and the `"audio-engineer"` agent-name string
  in `config/fleet/fleet-topology.json`'s native-pool roster. Neither is a model
  capability.

The honest gap: HELIOS cannot accept, route, or account for an image or audio request
on any lane today. Do not write configs, docs, or catalog entries implying it can.

Touchpoints adding vision/audio would require (design pointers only):

1. **Catalog capability flags** — a per-model field (e.g. `modalities`) added in the
   same commit to `config/model-catalog.json`, `config/schemas/model-catalog.schema.json`
   (`additionalProperties: false` rejects it otherwise),
   `scripts/build/validate-model-catalog.py`, and the C# binder the schema description
   names (`src/ai/HELIOS.AIHub/Configuration/ModelCatalog.cs`).
2. **Provider request shapes** — `ChatRequest` is the single record every
   `IChatProviderAgent` implements (`Abstractions/ChatModels.cs`); attachments extend
   it and every adapter under `src/ai/HELIOS.AIHub/Providers/`.
3. **Routing** — new `taskRouting` keys in `config/aihub.json` (catalog `strengths`
   reference those keys), plus LLM_STRENGTHS_PLAYBOOK rows.
4. **Spoke ops** — `__main__._OPS` carries JSON text and file paths only. Media should
   follow the fleet ops' path-passing precedent (`fleet_collect` takes
   `runDir`/`outcomes` paths), never base64 blobs through a 30-second-capped stdin
   pipe; any new op stays under the four-process cap.
5. **Truthfulness precedent** — `config/aihub.json`'s `openai-codex` `$comment` records
   an unsmoked model claim as exactly that ("has not been live-smoked"); a modality
   flag added before a keyed smoke test must carry the same honesty.
