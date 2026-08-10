"""Local fleet-worker stub honoring the Hermes kanban worker-lane contract.

Stands in for the real Hermes CLI when it is not on PATH, so
``scripts/fleet/start-fleet.ps1`` can bring the topology in
``config/fleet/fleet-topology.json`` up on any box. Each worker polls a JSON
kanban board, claims open tasks in its lanes under lockfile semantics, and
terminates every claimed task through the fleet contract: ``kanban_complete``
(result recorded) or ``kanban_block`` (reason recorded). The stub does no model
work — it exists so the fleet wiring is exercisable end to end.

Env contract (exported by start-fleet.ps1, mirrors the Hermes lane spawn):

- ``HERMES_KANBAN_DB``          path to the JSON board file (required)
- ``HERMES_KANBAN_TASK``        lane spec: comma-separated task types this
  worker claims; empty or ``*`` claims any lane
- ``HERMES_KANBAN_RUN_ID``      run identifier recorded on claims
- ``HERMES_KANBAN_CLAIM_LOCK``  lockfile path guarding board mutations
  (defaults to ``<db>.lock``)

Stub-only knobs: ``HERMES_KANBAN_ASSIGNEE``, ``HERMES_KANBAN_POLL_SECONDS``
(default 1.0), ``HERMES_KANBAN_MAX_IDLE_POLLS`` (default 30; <= 0 polls
forever), ``HERMES_KANBAN_LOG_FILE`` (worker reopens stderr onto this file, so
it stays loggable after its launcher exits). The worker exits 0 on
SIGTERM/SIGINT or once the board has had no claimable task for that many
consecutive polls.

Run: ``python3 -m helios_agents.fleet_worker`` from ``src/ai/python``.

Feeding a live board: hand-editing the board JSON while workers are running is
unsafe — workers load and save the board under the claim lock, which external
editors do not take, so a hand-appended task can be silently dropped by a
concurrent worker save. Use the lock-aware enqueue instead (same env
contract; exits without polling)::

    python3 -m helios_agents.fleet_worker --enqueue \
        '{"id": "T-1", "lane": "code_generation", "status": "open", "prompt": "..."}'

Seeding a board by hand before its workers start is still fine.

Hub-and-spoke rule: no network, no providers, no state beyond the board file
named by the contract. Logs go to stderr only; stdout stays silent.
"""

from __future__ import annotations

import argparse
import calendar
import json
import os
import signal
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

RESOLUTION_COMPLETE = "kanban_complete"
RESOLUTION_BLOCK = "kanban_block"

ENV_DB = "HERMES_KANBAN_DB"
ENV_TASK = "HERMES_KANBAN_TASK"
ENV_RUN_ID = "HERMES_KANBAN_RUN_ID"
ENV_CLAIM_LOCK = "HERMES_KANBAN_CLAIM_LOCK"
ENV_ASSIGNEE = "HERMES_KANBAN_ASSIGNEE"
ENV_POLL_SECONDS = "HERMES_KANBAN_POLL_SECONDS"
ENV_MAX_IDLE_POLLS = "HERMES_KANBAN_MAX_IDLE_POLLS"
ENV_LOG_FILE = "HERMES_KANBAN_LOG_FILE"


@dataclass(frozen=True)
class WorkerConfig:
    """Everything one worker lane needs; built from the env contract."""

    db_path: Path
    lock_path: Path
    lanes: frozenset[str] | None  # None means any lane
    assignee: str
    run_id: str
    poll_seconds: float = 1.0
    max_idle_polls: int = 30
    lock_timeout_seconds: float = 5.0
    lock_stale_seconds: float = 30.0
    # A claim is a lease, not ownership forever: a worker that crashes between
    # claiming and finishing must not strand the task in "claimed" (the fleet
    # contract's recovery guarantee). After this many seconds a claimed task
    # becomes claimable again.
    claim_lease_seconds: float = 300.0


def _log(message: str) -> None:
    try:
        print(message, file=sys.stderr, flush=True)
    except OSError:  # pragma: no cover - a dead log sink must never kill the lane
        pass


def _utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def parse_lanes(spec: str) -> frozenset[str] | None:
    """Parse the HERMES_KANBAN_TASK lane spec; None means claim any lane."""
    lanes = frozenset(part.strip() for part in spec.split(",") if part.strip())
    if not lanes or "*" in lanes:
        return None
    return lanes


def load_board(db_path: Path) -> dict[str, Any]:
    with db_path.open(encoding="utf-8") as handle:
        board: Any = json.load(handle)
    if not isinstance(board, dict) or not isinstance(board.get("tasks"), list):
        raise ValueError(f"kanban DB {db_path} must be an object with a 'tasks' list")
    return board


def save_board(db_path: Path, board: dict[str, Any]) -> None:
    """Atomic write (tmp + rename) so pollers never read a half-written board."""
    tmp = db_path.with_name(db_path.name + ".tmp")
    tmp.write_text(json.dumps(board, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, db_path)


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except OSError:  # e.g. EPERM: exists but owned by someone else
        return True
    return True


def _lock_is_stale(lock_path: Path, stale_seconds: float) -> bool:
    """A crash must release the claim lock (design contract): a lock whose
    holder pid is dead — or, when no live-pid check is possible, one older than
    ``stale_seconds`` — is stale and may be broken."""
    pid = 0
    try:
        holder: Any = json.loads(lock_path.read_text(encoding="utf-8"))
        if isinstance(holder, dict):
            pid = int(holder.get("pid", 0))
    except (OSError, ValueError):
        pid = 0
    if pid and sys.platform != "win32":  # os.kill(pid, 0) is a probe only on POSIX
        return not _pid_alive(pid)
    try:
        age = time.time() - lock_path.stat().st_mtime
    except OSError:
        return False  # lock vanished — nothing to break
    return age > stale_seconds


def acquire_claim_lock(
    lock_path: Path,
    assignee: str,
    timeout_seconds: float,
    stale_seconds: float = 30.0,
) -> bool:
    """Take the board claim lock via O_CREAT|O_EXCL lockfile semantics.

    Stale locks (dead holder) are broken; a live holder makes this return
    False once ``timeout_seconds`` elapses — the caller just polls again.
    """
    deadline = time.monotonic() + max(0.0, timeout_seconds)
    while True:
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            if _lock_is_stale(lock_path, stale_seconds):
                lock_path.unlink(missing_ok=True)
                continue
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.02)
        else:
            payload = {"pid": os.getpid(), "assignee": assignee, "lockedAt": _utc_now()}
            os.write(fd, json.dumps(payload).encode("utf-8"))
            os.close(fd)
            return True


def release_claim_lock(lock_path: Path) -> None:
    lock_path.unlink(missing_ok=True)


def _lane_of(task: dict[str, Any]) -> str:
    return str(task.get("lane") or task.get("taskType") or "")


def _claim_expired(task: dict[str, Any], lease_seconds: float) -> bool:
    claimed_at = str(task.get("claimedAt") or "")
    try:
        # claimedAt is UTC (the trailing Z is part of the contract). mktime treats
        # the tuple as local time and is one hour wrong during DST outside UTC.
        claimed = calendar.timegm(time.strptime(claimed_at, "%Y-%m-%dT%H:%M:%SZ"))
    except (ValueError, OverflowError):
        return True  # unparseable claim stamp: treat the lease as expired
    return (time.time() - claimed) >= lease_seconds


def _claimable(task: dict[str, Any], lanes: frozenset[str] | None, lease_seconds: float) -> bool:
    status = str(task.get("status", "open"))
    if status == "claimed":
        # Stale lease from a crashed worker — reclaimable.
        if not _claim_expired(task, lease_seconds):
            return False
    elif status != "open":
        return False
    return lanes is None or _lane_of(task) in lanes


def claim_next_task(config: WorkerConfig) -> dict[str, Any] | None:
    """Claim the first open task in this worker's lanes; None when there is
    nothing claimable (or the lock could not be taken before timeout)."""
    if not config.db_path.exists():
        return None
    if not acquire_claim_lock(
        config.lock_path, config.assignee, config.lock_timeout_seconds, config.lock_stale_seconds
    ):
        return None
    try:
        try:
            board = load_board(config.db_path)
        except (ValueError, OSError) as exc:
            # Boards are fed by hand-editing JSON; a torn or invalid read is an
            # idle poll, never a lane crash.
            _log(f"{config.assignee}: board read failed ({exc}); will retry")
            return None
        tasks: list[Any] = board["tasks"]
        for task in tasks:
            if isinstance(task, dict) and _claimable(task, config.lanes, config.claim_lease_seconds):
                task["status"] = "claimed"
                task["assignee"] = config.assignee
                task["runId"] = config.run_id
                task["claimedAt"] = _utc_now()
                save_board(config.db_path, board)
                return dict(task)
        return None
    finally:
        release_claim_lock(config.lock_path)


def work_task(task: dict[str, Any]) -> tuple[str, str]:
    """Decide the lane's termination for a claimed task.

    The stub blocks anything it cannot honestly complete — an explicit
    ``"block": true`` marker or a missing/empty prompt — and completes the rest
    with a stub result, so both contract exits stay exercisable locally.
    """
    if bool(task.get("block", False)):
        return RESOLUTION_BLOCK, str(task.get("blockReason") or "task marked block=true")
    prompt = str(task.get("prompt") or "").strip()
    if not prompt:
        return RESOLUTION_BLOCK, "task has no prompt"
    return RESOLUTION_COMPLETE, f"stub-completed: {prompt[:120]}"


def finish_task(config: WorkerConfig, task_id: str, resolution: str, payload: str) -> bool:
    """Record the task's termination on the board under the claim lock.

    ``kanban_complete`` -> status ``done`` with ``result``;
    ``kanban_block``    -> status ``blocked`` with ``reason``.
    Returns False when the task vanished or the lock could not be taken.
    """
    if resolution not in (RESOLUTION_COMPLETE, RESOLUTION_BLOCK):
        raise ValueError(
            f"unknown resolution {resolution!r}; expected "
            f"{RESOLUTION_COMPLETE!r} or {RESOLUTION_BLOCK!r}")
    if not acquire_claim_lock(
        config.lock_path, config.assignee, config.lock_timeout_seconds, config.lock_stale_seconds
    ):
        return False
    try:
        try:
            board = load_board(config.db_path)
        except (ValueError, OSError) as exc:
            _log(f"{config.assignee}: board read failed while finalizing ({exc})")
            return False
        tasks: list[Any] = board["tasks"]
        for task in tasks:
            if isinstance(task, dict) and str(task.get("id", "")) == task_id:
                task["resolution"] = resolution
                task["finishedAt"] = _utc_now()
                if resolution == RESOLUTION_COMPLETE:
                    task["status"] = "done"
                    task["result"] = payload
                else:
                    task["status"] = "blocked"
                    task["reason"] = payload
                save_board(config.db_path, board)
                return True
        return False
    finally:
        release_claim_lock(config.lock_path)


def enqueue_task(config: WorkerConfig, task: dict[str, Any]) -> bool:
    """Append ``task`` to the board under the claim lock.

    The lock-aware alternative to hand-editing a live board: workers mutate
    the board while holding the claim lock, so an external append that does
    not take the lock can be silently lost to a concurrent worker save. This
    takes the lock, re-loads the board, appends, and saves atomically.
    Returns False when the lock could not be taken before timeout or the
    board is missing/unreadable.
    """
    if not isinstance(task, dict):
        raise TypeError(f"task must be a JSON object (dict), got {type(task).__name__}")
    if not acquire_claim_lock(
        config.lock_path, config.assignee, config.lock_timeout_seconds, config.lock_stale_seconds
    ):
        _log(f"{config.assignee}: enqueue failed - claim lock busy")
        return False
    try:
        try:
            board = load_board(config.db_path)
        except (ValueError, OSError) as exc:
            _log(f"{config.assignee}: enqueue failed - board read failed ({exc})")
            return False
        tasks: list[Any] = board["tasks"]
        tasks.append(task)
        save_board(config.db_path, board)
        return True
    finally:
        release_claim_lock(config.lock_path)


def run_worker(config: WorkerConfig, stop: threading.Event | None = None) -> int:
    """Poll-claim-resolve loop; exits 0 on stop signal or sustained idleness."""
    stop = stop if stop is not None else threading.Event()
    idle_polls = 0
    handled = 0
    while not stop.is_set():
        task = claim_next_task(config)
        if task is None:
            idle_polls += 1
            if config.max_idle_polls > 0 and idle_polls >= config.max_idle_polls:
                _log(f"{config.assignee}: no open tasks for {idle_polls} polls; exiting")
                break
            if stop.wait(config.poll_seconds):
                break
            continue
        idle_polls = 0
        task_id = str(task.get("id", ""))
        resolution, payload = work_task(task)
        if finish_task(config, task_id, resolution, payload):
            handled += 1
            _log(f"{config.assignee}: task {task_id or '<no id>'} -> {resolution}")
        else:
            _log(f"{config.assignee}: task {task_id or '<no id>'} vanished before finalize")
    _log(f"{config.assignee}: done ({handled} task(s) handled)")
    return 0


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name, "")
    try:
        return float(raw) if raw else default
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "")
    try:
        return int(raw) if raw else default
    except ValueError:
        return default


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="python3 -m helios_agents.fleet_worker",
        description="Local kanban worker-lane stub (see module docstring).")
    parser.add_argument(
        "--assignee",
        default=os.environ.get(ENV_ASSIGNEE, "") or f"stub-{os.getpid()}",
        help="worker identity recorded on claims (env HERMES_KANBAN_ASSIGNEE)")
    parser.add_argument(
        "--poll-seconds", type=float,
        default=_env_float(ENV_POLL_SECONDS, 1.0),
        help="seconds between board polls (env HERMES_KANBAN_POLL_SECONDS)")
    parser.add_argument(
        "--max-idle-polls", type=int,
        default=_env_int(ENV_MAX_IDLE_POLLS, 30),
        help="empty polls before a clean exit; <= 0 polls forever "
             "(env HERMES_KANBAN_MAX_IDLE_POLLS)")
    parser.add_argument(
        "--log-file",
        default=os.environ.get(ENV_LOG_FILE, ""),
        help="append stderr logging to this file so the worker keeps a log "
             "sink after its launcher exits (env HERMES_KANBAN_LOG_FILE)")
    parser.add_argument(
        "--enqueue", metavar="TASK_JSON", default="",
        help="append one task (a JSON object) to the board under the claim "
             "lock, then exit without polling - the safe alternative to "
             "hand-editing a board its workers are running against")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    log_file = str(args.log_file)
    if log_file:
        # Own the log sink: launchers exit, inherited pipes break, but a file
        # descriptor this process opened stays writable for the worker's life.
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        sys.stderr = open(log_path, "a", buffering=1, encoding="utf-8")
    db_value = os.environ.get(ENV_DB, "")
    if not db_value:
        _log(f"{ENV_DB} is not set; the kanban env contract requires it "
             "(normally exported by scripts/fleet/start-fleet.ps1)")
        return 2
    config = WorkerConfig(
        db_path=Path(db_value),
        lock_path=Path(os.environ.get(ENV_CLAIM_LOCK, "") or db_value + ".lock"),
        lanes=parse_lanes(os.environ.get(ENV_TASK, "")),
        assignee=str(args.assignee),
        run_id=os.environ.get(ENV_RUN_ID, "") or "local",
        poll_seconds=max(0.01, float(args.poll_seconds)),
        max_idle_polls=int(args.max_idle_polls),
    )
    config.lock_path.parent.mkdir(parents=True, exist_ok=True)

    if args.enqueue:
        try:
            task: Any = json.loads(str(args.enqueue))
        except ValueError as exc:
            _log(f"--enqueue is not valid JSON: {exc}")
            return 2
        if not isinstance(task, dict):
            _log("--enqueue expects a single JSON object, e.g. "
                 '\'{"id": "T-1", "lane": "code_generation", "status": "open", '
                 '"prompt": "..."}\'')
            return 2
        if not enqueue_task(config, task):
            return 1
        _log(f"{config.assignee}: enqueued task "
             f"{str(task.get('id') or '') or '<no id>'} onto {config.db_path}")
        return 0

    stop = threading.Event()

    def _handle_signal(signum: int, frame: object) -> None:
        _log(f"{config.assignee}: received signal {signum}; shutting down")
        stop.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(sig, _handle_signal)
        except (ValueError, OSError):  # pragma: no cover - non-main thread / platform
            pass

    _log(f"{config.assignee}: polling {config.db_path} "
         f"(lanes: {', '.join(sorted(config.lanes)) if config.lanes else 'any'}; "
         f"run {config.run_id})")
    return run_worker(config, stop)


if __name__ == "__main__":
    sys.exit(main())
