# Hermes Fleet & Xcore-9s — Agent Fleet Design

How HELIOS dispatches work to an agent fleet: the Hermes Agent's kanban worker-lane
system as the fleet runtime, and the **Xcore-9s** worker pool (nine `xcore-agent`
workers) riding on it. Topology is declarative — `config/fleet/fleet-topology.json`.
Live bring-up happens in the hermes/xcore repos (roadmap PR5); this PR ships the
HELIOS-side contract, config, and routing.

## Architecture

```
helios-ai route agent_fleet_dispatch "<work item>"
        │  (config/aihub.json: agent_fleet_dispatch → hermes)
        ▼
CliProcessAgent("hermes") ──► hermes chat -q …          (interactive path)
                              hermes kanban board       (fleet path)
                                    │ fleet mode: pulls all non-archived tasks
                                    ▼
                    worker lanes, one per claimed task
                    spawn: hermes -p <assignee> chat -q <prompt>
                    env:   HERMES_KANBAN_TASK / _DB / _RUN_ID / _CLAIM_LOCK
                    exit:  kanban_complete | kanban_block | crash
                                    │
                     assignees xcore-1 … xcore-9  ("Xcore-9s" pool)
```

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
   env-var contract as the hub — no keys in Hermes config).
3. Create the board and register the nine Xcore assignees; set
   `maxConcurrentLanes` to bound parallel lanes independently of pool size.
4. Wire the gateway webhook (hermes `gateway/platforms/webhook.py`) if GitHub-event-driven
   dispatch is wanted; PR-review prompts must treat PR titles/bodies as untrusted input.
5. Dashboards: Hermes kanban dashboard plugin per board; HELIOS-side visibility arrives
   with the WinUI 3 AIHub page (GUI_THEME_ANALYSIS.md).

## Parallelism model

Three independent throttles, tuned separately:

| Layer | Knob | Where |
|---|---|---|
| Model capacity (tokens/min) | `modelCapacity` / `additionalModelDeployments[].capacity` | `infra/main.bicepparam` |
| Fleet lanes | `maxConcurrentLanes`, `poolSize` | `config/fleet/fleet-topology.json` |
| Hub fan-out | `CompareAsync` provider list; per-provider circuit breakers | `config/aihub.json` chains |

Backpressure flows naturally: a 429 at the model layer fails the lane's call → the lane
blocks the task → the board holds it until capacity returns; the hub's circuit breaker
meanwhile routes other traffic to fallback providers.
