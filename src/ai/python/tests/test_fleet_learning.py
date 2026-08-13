"""Fleet -> learning-store collector and per-pool fleet analytics."""

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

from helios_agents import __main__ as boundary
from helios_agents import fleet_learning

SPOKE_DIR = Path(__file__).resolve().parent.parent
LEARNING_STORE_CS = (
    Path(__file__).resolve().parents[2] / "HELIOS.AIHub" / "Learning" / "LearningStore.cs")

CLAIMED = "2026-08-13T10:00:00Z"
FINISHED = "2026-08-13T10:00:02Z"  # claim->resolve = 2000 ms


def _task(task_id, lane, status, claimed=CLAIMED, finished=FINISHED, **extra):
    """A board task shaped the way fleet_worker claims and resolves them."""
    task = {"id": task_id, "lane": lane, "status": status, "prompt": "p"}
    if status in ("claimed", "done", "blocked") and claimed:
        task.update(assignee="x-1", runId="run-1", claimedAt=claimed)
    if status == "done":
        task.update(resolution="kanban_complete", finishedAt=finished, result="stub-completed: p")
    elif status == "blocked":
        task.update(resolution="kanban_block", finishedAt=finished, reason="marked block")
    task.update(extra)
    return task


def _make_run(tmp_path: Path, pools, run_id="run-20260813-test") -> Path:
    """Synthetic .helios/fleet/<runId>/: manifest.json + boards/<board>.json.

    ``pools``: list of (poolName, boardName, lanes, tasks) tuples.
    """
    run = tmp_path / "fleet" / run_id
    boards = run / "boards"
    boards.mkdir(parents=True, exist_ok=True)
    manifest_pools = []
    for pool_name, board_name, lanes, tasks in pools:
        db = boards / f"{board_name}.json"
        db.write_text(json.dumps({
            "board": board_name, "runId": run_id,
            "createdAt": "2026-08-13T09:00:00Z", "tasks": tasks,
        }, indent=2), encoding="utf-8")
        manifest_pools.append({
            "pool": pool_name, "board": board_name, "lanes": lanes,
            "db": str(db), "claimLock": str(db) + ".lock", "workers": [],
        })
    (run / "manifest.json").write_text(json.dumps({
        "runId": run_id, "startedAt": "2026-08-13T09:00:00Z",
        "status": "running", "stoppedAt": None, "pools": manifest_pools,
    }, indent=2), encoding="utf-8")
    return run


def _records(outcomes: Path) -> list[dict]:
    return [json.loads(line) for line in outcomes.read_text(encoding="utf-8").splitlines()]


def _standard_run(tmp_path: Path) -> Path:
    return _make_run(tmp_path, [
        ("xcore-9-code", "xcore-code", "code_generation", [
            _task("T1", "code_generation", "done"),
            _task("T2", "code_generation", "blocked"),
            _task("T3", "code_generation", "open", claimed=""),
            _task("T4", "code_generation", "claimed"),
        ]),
        ("xcore-9-review", "xcore-review", "code_review", [
            _task("R1", "code_review", "done"),
        ]),
    ])


def test_collect_happy_path(tmp_path):
    run = _standard_run(tmp_path)
    outcomes = tmp_path / "outcomes.jsonl"
    summary = fleet_learning.collect(run, outcomes)

    assert summary["collected"] == 3
    assert summary["skippedDuplicates"] == 0
    assert summary["pools"] == {"xcore-9-code": 2, "xcore-9-review": 1}
    assert summary["runId"] == "run-20260813-test"

    by_provider = {}
    for record in _records(outcomes):
        by_provider.setdefault(record["provider"], []).append(record)
    assert set(by_provider) == {"pool:xcore-9-code", "pool:xcore-9-review"}
    done, blocked = by_provider["pool:xcore-9-code"]
    assert done["taskType"] == "code_generation"
    assert done["success"] is True and blocked["success"] is False
    assert done["latencyMs"] == 2000.0
    assert done["timestamp"] == FINISHED  # resolve time
    assert done["pool"] == "xcore-9-code"
    assert done["source"] == "fleet-lane"
    assert done["model"] == "" and done["costUsd"] == 0.0 and done["quality"] is None


def test_collect_is_idempotent_and_picks_up_only_new_tasks(tmp_path):
    run = _standard_run(tmp_path)
    outcomes = tmp_path / "outcomes.jsonl"
    assert fleet_learning.collect(run, outcomes)["collected"] == 3

    again = fleet_learning.collect(run, outcomes)
    assert again["collected"] == 0
    assert again["skippedDuplicates"] == 3
    assert again["pools"] == {}
    assert len(_records(outcomes)) == 3  # no double-append

    # A task resolved after the first pass is the only thing a re-collect adds.
    board_path = run / "boards" / "xcore-review.json"
    board = json.loads(board_path.read_text(encoding="utf-8"))
    board["tasks"].append(_task("R2", "code_review", "done"))
    board_path.write_text(json.dumps(board), encoding="utf-8")
    third = fleet_learning.collect(run, outcomes)
    assert third["collected"] == 1
    assert third["skippedDuplicates"] == 3
    assert len(_records(outcomes)) == 4


def test_blocked_task_records_success_false(tmp_path):
    run = _make_run(tmp_path, [
        ("xcore-9-infra", "xcore-infra", "infrastructure", [
            _task("T1", "infrastructure", "blocked"),
        ]),
    ])
    outcomes = tmp_path / "outcomes.jsonl"
    fleet_learning.collect(run, outcomes)
    (record,) = _records(outcomes)
    assert record["success"] is False
    assert record["provider"] == "pool:xcore-9-infra"
    assert record["latencyMs"] == 2000.0


def test_missing_claim_stamp_yields_zero_latency(tmp_path):
    # A hand-resolved task never went through claim_next_task, so it has no
    # claimedAt; latency degrades to 0 and the timestamp stays the resolve time.
    run = _make_run(tmp_path, [
        ("xcore-9-code", "xcore-code", "code_generation", [
            _task("T1", "code_generation", "done", claimed=""),
        ]),
    ])
    outcomes = tmp_path / "outcomes.jsonl"
    fleet_learning.collect(run, outcomes)
    (record,) = _records(outcomes)
    assert record["latencyMs"] == 0.0
    assert record["timestamp"] == FINISHED


def test_board_unknown_to_manifest_falls_back_to_board_name(tmp_path):
    run = _make_run(tmp_path, [
        ("xcore-9-code", "xcore-code", "code_generation", []),
    ])
    stray = run / "boards" / "handmade.json"
    stray.write_text(json.dumps({
        "board": "handmade", "tasks": [_task("H1", "code_generation", "done")],
    }), encoding="utf-8")
    outcomes = tmp_path / "outcomes.jsonl"
    summary = fleet_learning.collect(run, outcomes)
    assert summary["pools"] == {"handmade": 1}
    (record,) = _records(outcomes)
    assert record["provider"] == "pool:handmade"


def test_collect_without_manifest_raises(tmp_path):
    with pytest.raises(ValueError):
        fleet_learning.collect(tmp_path / "no-such-run", tmp_path / "outcomes.jsonl")


def test_corrupt_index_raises_instead_of_double_appending(tmp_path):
    run = _standard_run(tmp_path)
    outcomes = tmp_path / "outcomes.jsonl"
    fleet_learning.collect(run, outcomes)
    index = tmp_path / "outcomes.jsonl.fleet-collected.json"
    assert index.exists()
    index.write_text("{not json", encoding="utf-8")
    with pytest.raises(ValueError):
        fleet_learning.collect(run, outcomes)
    assert len(_records(outcomes)) == 3  # nothing re-appended


def test_fleet_summary_math(tmp_path):
    outcomes = tmp_path / "outcomes.jsonl"
    rows = [
        {"provider": "pool:a", "pool": "a", "success": True,
         "latencyMs": 1000.0, "source": "fleet-lane"},
        {"provider": "pool:a", "pool": "a", "success": False,
         "latencyMs": 3000.0, "source": "fleet-lane"},
        {"provider": "pool:a", "pool": "a", "success": False,
         "latencyMs": 2000.0, "source": "fleet-lane"},
        {"provider": "pool:b", "pool": "b", "success": True,
         "latencyMs": 500.0, "source": "fleet-lane"},
        # Non-fleet records (live hub outcome, other advisory source) are excluded.
        {"provider": "openai", "success": True, "latencyMs": 9.0, "source": None},
        {"provider": "pool:a", "pool": "a", "success": True,
         "latencyMs": 9.0, "source": "absorption-benchmark"},
    ]
    outcomes.write_text(
        "".join(json.dumps(r) + "\n" for r in rows) + "torn line\n", encoding="utf-8")

    summary = fleet_learning.fleet_summary(outcomes)
    assert summary["totalFleetOutcomes"] == 4
    assert summary["pools"]["a"] == {
        "tasks": 3, "blocked": 2, "blockRate": 0.6667, "meanLatencyMs": 2000.0}
    assert summary["pools"]["b"] == {
        "tasks": 1, "blocked": 0, "blockRate": 0.0, "meanLatencyMs": 500.0}
    assert "scaleEvents" not in summary["pools"]["a"]  # no scale log offered


def test_fleet_summary_scale_log_correlation(tmp_path):
    outcomes = tmp_path / "outcomes.jsonl"
    outcomes.write_text(json.dumps({
        "provider": "pool:xcore-9-code", "pool": "xcore-9-code", "success": True,
        "latencyMs": 100.0, "source": "fleet-lane"}) + "\n", encoding="utf-8")
    scale_log = tmp_path / "scale-log.jsonl"
    entries = [
        {"at": "2026-08-13T10:00:00Z", "pool": "xcore-9-code",
         "from": 2, "to": 4, "reason": "queue", "burst": 0},
        {"at": "2026-08-13T10:05:00Z", "pool": "xcore-9-code",
         "from": 4, "to": 2, "reason": "idle", "burst": 0},
        {"at": "2026-08-13T10:10:00Z", "pool": "vmss-burst",
         "pools": ["xcore-9-code", "xcore-9-infra"], "burst": 5,
         "instances": 3, "workersPerInstance": 2, "reason": "burst"},
    ]
    scale_log.write_text("".join(json.dumps(e) + "\n" for e in entries), encoding="utf-8")

    summary = fleet_learning.fleet_summary(outcomes, scale_log)
    code = summary["pools"]["xcore-9-code"]
    assert code["tasks"] == 1
    assert code["scaleEvents"] == 2
    assert code["burstEvents"] == 1
    # A pool seen only in the scale log still appears, with zero task stats.
    infra = summary["pools"]["xcore-9-infra"]
    assert infra == {"tasks": 0, "blocked": 0, "blockRate": 0.0,
                     "meanLatencyMs": 0.0, "scaleEvents": 0, "burstEvents": 1}

    # A scale-log path whose file does not exist counts as zero events.
    quiet = fleet_learning.fleet_summary(outcomes, tmp_path / "never-scaled.jsonl")
    assert quiet["pools"]["xcore-9-code"]["scaleEvents"] == 0


def test_record_field_names_match_csharp_routing_outcome(tmp_path):
    """Contract test: emitted keys must equal RoutingOutcome's JsonPropertyName
    names (and declaration order) so LocalJsonlLearningStore can read them."""
    if not LEARNING_STORE_CS.exists():
        pytest.skip("C# LearningStore.cs not present in this checkout")
    source = LEARNING_STORE_CS.read_text(encoding="utf-8")
    block = source[source.index("record RoutingOutcome"):source.index("interface ILearningStore")]
    csharp_names = re.findall(r'JsonPropertyName\("([^"]+)"\)', block)
    assert csharp_names, "RoutingOutcome no longer declares JsonPropertyName attributes"

    run = _make_run(tmp_path, [
        ("xcore-9-code", "xcore-code", "code_generation", [
            _task("T1", "code_generation", "done"),
        ]),
    ])
    outcomes = tmp_path / "outcomes.jsonl"
    fleet_learning.collect(run, outcomes)
    (record,) = _records(outcomes)
    assert list(record.keys()) == csharp_names


def _invoke_cli(*argv: str) -> tuple[int, str]:
    proc = subprocess.run(
        [sys.executable, "-m", "helios_agents", *argv],
        capture_output=True, text=True, cwd=SPOKE_DIR, timeout=60)
    return proc.returncode, proc.stdout


def test_cli_fleet_collect_prints_summary_json(tmp_path):
    run = _standard_run(tmp_path)
    outcomes = tmp_path / "outcomes.jsonl"
    code, stdout = _invoke_cli(
        "fleet-collect", "--run-dir", str(run), "--outcomes", str(outcomes))
    assert code == 0
    summary = json.loads(stdout)  # JSON on stdout, nothing else
    assert summary["collected"] == 3
    assert summary["skippedDuplicates"] == 0
    assert summary["pools"] == {"xcore-9-code": 2, "xcore-9-review": 1}
    assert len(_records(outcomes)) == 3


def test_cli_fleet_summary_prints_summary_json(tmp_path):
    run = _standard_run(tmp_path)
    outcomes = tmp_path / "outcomes.jsonl"
    fleet_learning.collect(run, outcomes)
    scale_log = tmp_path / "scale-log.jsonl"
    scale_log.write_text(json.dumps({
        "at": "2026-08-13T10:00:00Z", "pool": "xcore-9-code",
        "from": 2, "to": 4, "reason": "queue", "burst": 0}) + "\n", encoding="utf-8")

    code, stdout = _invoke_cli("fleet-summary", "--outcomes", str(outcomes))
    assert code == 0
    assert json.loads(stdout)["totalFleetOutcomes"] == 3

    code, stdout = _invoke_cli(
        "fleet-summary", "--outcomes", str(outcomes), "--scale-log", str(scale_log))
    assert code == 0
    assert json.loads(stdout)["pools"]["xcore-9-code"]["scaleEvents"] == 1


def test_cli_failure_is_json_error_and_exit_1(tmp_path):
    code, stdout = _invoke_cli(
        "fleet-collect", "--run-dir", str(tmp_path / "no-such-run"),
        "--outcomes", str(tmp_path / "outcomes.jsonl"))
    assert code == 1
    assert "manifest" in json.loads(stdout)["error"]


def test_stdin_boundary_dispatches_fleet_ops(tmp_path):
    run = _standard_run(tmp_path)
    outcomes = tmp_path / "outcomes.jsonl"
    result = boundary.run({
        "op": "fleet_collect", "runDir": str(run), "outcomes": str(outcomes)})
    assert result["collected"] == 3
    summary = boundary.run({"op": "fleet_summary", "outcomes": str(outcomes)})
    assert summary["totalFleetOutcomes"] == 3
    with pytest.raises(ValueError):
        boundary.run({"op": "fleet_collect", "runDir": str(run)})  # no outcomes path
    with pytest.raises(ValueError):
        boundary.run({"op": "fleet_summary", "outcomes": str(outcomes), "scaleLog": 7})
