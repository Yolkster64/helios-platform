"""Fleet -> learning-store tandem lane.

Turns finished fleet-run board tasks (the ``.helios/fleet/<runId>/`` contract:
``manifest.json`` plus one kanban board per pool under ``boards/``) into
learning-store outcome records the C# hub can read back, and computes
per-pool fleet analytics over those records.

Record contract
---------------
Each appended JSONL line mirrors the C# ``RoutingOutcome`` record
(src/ai/HELIOS.AIHub/Learning/LearningStore.cs) field for field, using its
exact ``JsonPropertyName`` names and casing::

    {"outcomeId": ..., "timestamp": ..., "taskType": ..., "provider": ...,
     "model": "", "success": ..., "latencyMs": ..., "costUsd": 0.0,
     "quality": null, "pool": ..., "source": "fleet-lane"}

- ``outcomeId`` is a deterministic UUIDv5 of ``runId``, board, and task id,
  so retries and dual-store fan-out see the same stable identity.
- ``provider`` is ``pool:<poolName>`` and ``pool`` the bare pool name, both
  resolved from the task's board through the manifest's ``pools`` entries
  (``board`` -> ``pool``); a board the manifest does not know falls back to
  its own board name.
- ``taskType`` is the task's lane (``lane`` falling back to ``taskType`` —
  the same aliasing the fleet worker honors).
- ``success`` is ``status == "done"`` (``kanban_complete``); a ``blocked``
  task (``kanban_block``) records ``false``.
- ``latencyMs`` is the claim->resolve wall time. Boards DO record both ends:
  ``claim_next_task`` stamps ``claimedAt`` and ``finish_task`` stamps
  ``finishedAt`` (helios_agents.fleet_worker), both second-granularity
  ``%Y-%m-%dT%H:%M:%SZ`` UTC. When either stamp is missing or unparseable
  (e.g. a hand-resolved task) latency is recorded as 0.0.
- ``timestamp`` is the resolve time (``finishedAt``), falling back to
  ``claimedAt`` and finally to the current UTC time, so the field always
  parses as a ``DateTimeOffset`` on the C# side.
- ``model`` is empty, ``costUsd`` 0.0 and ``quality`` null: the fleet lane
  records dispatch outcomes, not model spend or ratings.
- ``source`` is ``"fleet-lane"`` — ADVISORY provenance, so adaptive routing
  excludes these records by design (see LearningStore.cs).

Idempotency / dedupe
--------------------
Running :func:`collect` twice over the same run must not double-append. The
mechanism is a sidecar index next to the outcomes file
(``<outcomes>.fleet-collected.json``) holding one ``[runId, board, taskId]``
triple per collected task. The board name is part of the key because
cross-pool handoffs may legitimately reuse a task id on another pool's
board. Records are appended before the index is persisted, so a crash
between the two re-appends at most one batch (at-least-once), never loses
one. A corrupt index raises instead of silently re-collecting everything.

Hub-and-spoke rule: stdlib only — no network, no providers, no state beyond
the run directory, the outcomes file, and its sidecar index.
"""

from __future__ import annotations

import calendar
import json
import os
import time
import uuid
from pathlib import Path
from typing import Any

FLEET_SOURCE = "fleet-lane"
POOL_PROVIDER_PREFIX = "pool:"
BURST_POOL = "vmss-burst"  # scale-log aggregate entries (scale-fleet.ps1)

# The board stamp contract (helios_agents.fleet_worker claimedAt/finishedAt).
_TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
_RESOLVED_STATUSES = frozenset({"done", "blocked"})


def _utc_now() -> str:
    return time.strftime(_TIMESTAMP_FORMAT, time.gmtime())


def _parse_stamp(value: Any) -> float | None:
    """Board stamp -> epoch seconds; None when missing/unparseable."""
    try:
        # Stamps are UTC (trailing Z is part of the contract); timegm keeps the
        # math DST-proof, same as fleet_worker's lease check.
        return float(calendar.timegm(time.strptime(str(value), _TIMESTAMP_FORMAT)))
    except (ValueError, OverflowError):
        return None


def _lane_of(task: dict[str, Any]) -> str:
    return str(task.get("lane") or task.get("taskType") or "")


def _load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _board_pools(manifest: dict[str, Any]) -> dict[str, str]:
    """Board name -> pool name from the manifest's ``pools`` entries."""
    pools = manifest.get("pools")
    mapping: dict[str, str] = {}
    for entry in pools if isinstance(pools, list) else []:
        if isinstance(entry, dict) and entry.get("board") and entry.get("pool"):
            mapping[str(entry["board"])] = str(entry["pool"])
    return mapping


def _index_path_for(outcomes: Path) -> Path:
    return outcomes.with_name(outcomes.name + ".fleet-collected.json")


def _load_index(index_path: Path) -> set[tuple[str, str, str]]:
    """Load the collected-task index as a set of (runId, board, taskId)."""
    if not index_path.exists():
        return set()
    try:
        data = _load_json(index_path)
        return {(str(r), str(b), str(t)) for r, b, t in data["collected"]}
    except (OSError, ValueError, KeyError, TypeError) as exc:
        # An empty fallback here would silently re-append every record ever
        # collected — the one failure mode dedupe exists to prevent.
        raise ValueError(
            f"collected-index {index_path} is unreadable ({exc}); fix or "
            "remove it before re-collecting") from exc


def _save_index(index_path: Path, index: set[tuple[str, str, str]]) -> None:
    """Atomic write (tmp + rename) so a crash never leaves a torn index."""
    payload = {"version": 1, "collected": [list(key) for key in sorted(index)]}
    tmp = index_path.with_name(index_path.name + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, index_path)


def _latency_ms(task: dict[str, Any]) -> float:
    claimed = _parse_stamp(task.get("claimedAt"))
    finished = _parse_stamp(task.get("finishedAt"))
    if claimed is None or finished is None:
        return 0.0
    return max(0.0, (finished - claimed) * 1000.0)


def _record(task: dict[str, Any], pool: str, outcome_id: str) -> dict[str, Any]:
    """One learning-store record; key order mirrors the C# declaration."""
    timestamp = str(task.get("finishedAt") or task.get("claimedAt") or "") or _utc_now()
    return {
        "outcomeId": outcome_id,
        "timestamp": timestamp,
        "taskType": _lane_of(task),
        "provider": POOL_PROVIDER_PREFIX + pool,
        "model": "",
        "success": str(task.get("status")) == "done",
        "latencyMs": _latency_ms(task),
        "costUsd": 0.0,
        "quality": None,
        "pool": pool,
        "source": FLEET_SOURCE,
    }


def collect(run_dir: str | Path, outcomes_path: str | Path) -> dict[str, Any]:
    """Append one learning-store record per newly resolved task in ``run_dir``.

    Reads ``manifest.json`` and every ``boards/*.json`` under ``run_dir``,
    emits records (module docstring) for tasks whose status is ``done`` or
    ``blocked``, and appends them as JSONL to ``outcomes_path``. Idempotent
    via the sidecar index; a board torn mid-save is skipped and picked up by
    the next pass (dedupe makes re-scanning safe).

    Returns ``{"runId", "collected", "skippedDuplicates", "pools"}`` where
    ``pools`` maps pool name -> records collected by THIS call.
    """
    run = Path(run_dir)
    manifest_path = run / "manifest.json"
    try:
        manifest = _load_json(manifest_path)
    except (OSError, ValueError) as exc:
        raise ValueError(f"{manifest_path} is not a readable fleet manifest ({exc})") from exc
    if not isinstance(manifest, dict):
        raise ValueError(f"{manifest_path} must hold a JSON object")
    run_id = str(manifest.get("runId") or run.name)
    board_pools = _board_pools(manifest)

    outcomes = Path(outcomes_path)
    index_path = _index_path_for(outcomes)
    index = _load_index(index_path)

    collected: list[dict[str, Any]] = []
    skipped = 0
    per_pool: dict[str, int] = {}
    for board_path in sorted((run / "boards").glob("*.json")):
        try:
            board = _load_json(board_path)
        except (OSError, ValueError):
            continue  # torn mid-save; the next collect pass picks it up
        if not isinstance(board, dict) or not isinstance(board.get("tasks"), list):
            continue
        board_name = str(board.get("board") or board_path.stem)
        pool = board_pools.get(board_name, board_name)
        for position, task in enumerate(board["tasks"]):
            if not isinstance(task, dict) or str(task.get("status")) not in _RESOLVED_STATUSES:
                continue
            task_id = str(task.get("id") or f"{board_path.name}#{position}")
            key = (run_id, board_name, task_id)
            if key in index:
                skipped += 1
                continue
            outcome_id = str(uuid.uuid5(
                uuid.NAMESPACE_URL,
                f"helios:fleet:{run_id}:{board_name}:{task_id}",
            ))
            collected.append(_record(task, pool, outcome_id))
            index.add(key)
            per_pool[pool] = per_pool.get(pool, 0) + 1

    if collected:
        outcomes.parent.mkdir(parents=True, exist_ok=True)
        payload = "".join(json.dumps(record) + "\n" for record in collected)
        with outcomes.open("a", encoding="utf-8") as handle:
            handle.write(payload)
        # Persisted AFTER the append: a crash in between re-appends (dedupe is
        # at-least-once), never loses a record.
        _save_index(index_path, index)

    return {
        "runId": run_id,
        "collected": len(collected),
        "skippedDuplicates": skipped,
        "pools": dict(sorted(per_pool.items())),
    }


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    """JSONL rows, skipping blank and torn lines — the same tolerance the C#
    reader applies (a crash mid-append must not poison the whole history)."""
    rows: list[dict[str, Any]] = []
    if not path.exists():
        return rows
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if isinstance(row, dict):
                rows.append(row)
    return rows


def _pool_of(record: dict[str, Any]) -> str:
    pool = str(record.get("pool") or "")
    if pool:
        return pool
    provider = str(record.get("provider") or "")
    if provider.startswith(POOL_PROVIDER_PREFIX):
        return provider[len(POOL_PROVIDER_PREFIX):]
    return provider or "unknown"


def fleet_summary(
    outcomes_path: str | Path, scale_log_path: str | Path | None = None
) -> dict[str, Any]:
    """Per-pool stats over ``source == "fleet-lane"`` learning records.

    Per pool: ``tasks`` (record count), ``blocked`` and ``blockRate``
    (share of success=false, i.e. kanban_block terminations), and
    ``meanLatencyMs`` over the recorded claim->resolve latencies.

    When ``scale_log_path`` is given, scaling actions from scale-log.jsonl
    are counted per pool and included as ``scaleEvents`` / ``burstEvents``:
    local scales are ``{at, pool, from, to, reason, burst: 0}`` entries and
    count toward their ``pool``; aggregate VMSS bursts are
    ``{at, pool: "vmss-burst", pools, ...}`` entries and credit every pool
    they list. A pool seen only in the scale log still appears (with zero
    task stats); a missing log file simply counts as zero events.
    """
    records = [r for r in _read_jsonl(Path(outcomes_path)) if r.get("source") == FLEET_SOURCE]
    by_pool: dict[str, list[dict[str, Any]]] = {}
    for record in records:
        by_pool.setdefault(_pool_of(record), []).append(record)

    scale_events: dict[str, int] = {}
    burst_events: dict[str, int] = {}
    if scale_log_path is not None:
        for entry in _read_jsonl(Path(scale_log_path)):
            pool = str(entry.get("pool") or "")
            if pool == BURST_POOL:
                listed = entry.get("pools")
                for burst_pool in listed if isinstance(listed, list) else []:
                    name = str(burst_pool)
                    burst_events[name] = burst_events.get(name, 0) + 1
            elif pool:
                scale_events[pool] = scale_events.get(pool, 0) + 1

    names = set(by_pool)
    if scale_log_path is not None:
        names |= set(scale_events) | set(burst_events)

    pools: dict[str, dict[str, Any]] = {}
    for name in sorted(names):
        rows = by_pool.get(name, [])
        blocked = sum(1 for row in rows if not row.get("success"))
        latencies = [float(row.get("latencyMs") or 0.0) for row in rows]
        stats: dict[str, Any] = {
            "tasks": len(rows),
            "blocked": blocked,
            "blockRate": round(blocked / len(rows), 4) if rows else 0.0,
            "meanLatencyMs": round(sum(latencies) / len(latencies), 2) if latencies else 0.0,
        }
        if scale_log_path is not None:
            stats["scaleEvents"] = scale_events.get(name, 0)
            stats["burstEvents"] = burst_events.get(name, 0)
        pools[name] = stats

    return {"totalFleetOutcomes": len(records), "pools": pools}
