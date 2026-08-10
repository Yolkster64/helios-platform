"""Claim/complete/block logic of the local fleet-worker stub."""

import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

from helios_agents import fleet_worker


def _board(tmp_path: Path, tasks: list) -> Path:
    db = tmp_path / "board.json"
    db.write_text(json.dumps({"board": "xcore-test", "tasks": tasks}), encoding="utf-8")
    return db


def _config(tmp_path: Path, db: Path, lanes=None, **overrides) -> fleet_worker.WorkerConfig:
    settings = dict(
        db_path=db,
        lock_path=tmp_path / "board.lock",
        lanes=frozenset(lanes) if lanes else None,
        assignee="xtest-1",
        run_id="run-1",
        poll_seconds=0.01,
        max_idle_polls=2,
        lock_timeout_seconds=0.05,
        lock_stale_seconds=30.0,
    )
    settings.update(overrides)
    return fleet_worker.WorkerConfig(**settings)


def _tasks(db: Path) -> list:
    return json.loads(db.read_text(encoding="utf-8"))["tasks"]


def test_claim_respects_lane_filter(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "prompt": "a"},
        {"id": "T2", "lane": "infrastructure", "status": "open", "prompt": "b"},
    ])
    claimed = fleet_worker.claim_next_task(_config(tmp_path, db, lanes={"infrastructure"}))
    assert claimed is not None and claimed["id"] == "T2"
    persisted = {t["id"]: t for t in _tasks(db)}
    assert persisted["T2"]["status"] == "claimed"
    assert persisted["T2"]["assignee"] == "xtest-1"
    assert persisted["T2"]["runId"] == "run-1"
    assert persisted["T1"]["status"] == "open"
    assert not (tmp_path / "board.lock").exists()  # lock released after the claim


def test_claims_are_ordered_and_exhaust(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "prompt": "a"},
        {"id": "T2", "lane": "code_generation", "status": "open", "prompt": "b"},
    ])
    config = _config(tmp_path, db)
    first = fleet_worker.claim_next_task(config)
    second = fleet_worker.claim_next_task(config)
    assert first is not None and first["id"] == "T1"
    assert second is not None and second["id"] == "T2"
    assert fleet_worker.claim_next_task(config) is None


@pytest.mark.parametrize("task,resolution,needle", [
    ({"id": "T1", "prompt": "add retries"}, fleet_worker.RESOLUTION_COMPLETE, "add retries"),
    ({"id": "T2", "prompt": "x", "block": True}, fleet_worker.RESOLUTION_BLOCK, "block=true"),
    ({"id": "T3", "prompt": "   "}, fleet_worker.RESOLUTION_BLOCK, "no prompt"),
    ({"id": "T4"}, fleet_worker.RESOLUTION_BLOCK, "no prompt"),
])
def test_work_task_decides_the_contract_exit(task, resolution, needle):
    got_resolution, payload = fleet_worker.work_task(task)
    assert got_resolution == resolution
    assert needle in payload


def test_finish_records_kanban_complete(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "prompt": "add retries"},
    ])
    config = _config(tmp_path, db)
    task = fleet_worker.claim_next_task(config)
    assert task is not None
    resolution, payload = fleet_worker.work_task(task)
    assert fleet_worker.finish_task(config, "T1", resolution, payload) is True
    (done,) = _tasks(db)
    assert done["status"] == "done"
    assert done["resolution"] == fleet_worker.RESOLUTION_COMPLETE
    assert done["result"].startswith("stub-completed:")


def test_finish_records_kanban_block(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "block": True},
    ])
    config = _config(tmp_path, db)
    task = fleet_worker.claim_next_task(config)
    assert task is not None
    resolution, payload = fleet_worker.work_task(task)
    assert fleet_worker.finish_task(config, "T1", resolution, payload) is True
    (blocked,) = _tasks(db)
    assert blocked["status"] == "blocked"
    assert blocked["resolution"] == fleet_worker.RESOLUTION_BLOCK
    assert blocked["reason"]


def test_finish_rejects_unknown_resolution(tmp_path):
    db = _board(tmp_path, [])
    with pytest.raises(ValueError):
        fleet_worker.finish_task(_config(tmp_path, db), "T1", "kanban_shrug", "x")


def test_held_lock_prevents_claim(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "prompt": "a"},
    ])
    lock = tmp_path / "board.lock"
    # A live holder: our own pid is definitely alive, so the lock is not stale.
    lock.write_text(json.dumps({"pid": os.getpid(), "assignee": "other"}), encoding="utf-8")
    assert fleet_worker.claim_next_task(_config(tmp_path, db)) is None
    (task,) = _tasks(db)
    assert task["status"] == "open"  # untouched while someone else holds the lock


def test_stale_lock_is_broken_and_claim_proceeds(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "prompt": "a"},
    ])
    lock = tmp_path / "board.lock"
    lock.write_text("{}", encoding="utf-8")  # no holder pid -> age decides
    old = lock.stat().st_mtime - 3600
    os.utime(lock, (old, old))
    claimed = fleet_worker.claim_next_task(_config(tmp_path, db, lock_stale_seconds=1.0))
    assert claimed is not None and claimed["id"] == "T1"


def test_run_worker_drains_board_then_idle_exits(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "prompt": "good"},
        {"id": "T2", "lane": "code_generation", "status": "open", "block": True},
        {"id": "T3", "lane": "other_lane", "status": "open", "prompt": "not ours"},
    ])
    config = _config(tmp_path, db, lanes={"code_generation"})
    assert fleet_worker.run_worker(config) == 0
    persisted = {t["id"]: t for t in _tasks(db)}
    assert persisted["T1"]["status"] == "done"
    assert persisted["T2"]["status"] == "blocked"
    assert persisted["T3"]["status"] == "open"  # other lane never touched


def test_torn_board_read_is_an_idle_poll_not_a_crash(tmp_path):
    db = tmp_path / "board.json"
    db.write_text('{"board": "xcore-test", "tasks": [', encoding="utf-8")  # torn write
    config = _config(tmp_path, db)
    assert fleet_worker.claim_next_task(config) is None
    assert not (tmp_path / "board.lock").exists()  # lock released on the way out
    assert fleet_worker.finish_task(
        config, "T1", fleet_worker.RESOLUTION_COMPLETE, "x") is False


def test_run_worker_honors_stop_event(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "code_generation", "status": "open", "prompt": "a"},
    ])
    stop = threading.Event()
    stop.set()  # what the SIGTERM handler does
    assert fleet_worker.run_worker(_config(tmp_path, db), stop) == 0
    (task,) = _tasks(db)
    assert task["status"] == "open"  # stopped before claiming anything


@pytest.mark.parametrize("spec,expected", [
    ("", None),
    ("*", None),
    ("code_generation", frozenset({"code_generation"})),
    ("a, b ,c", frozenset({"a", "b", "c"})),
])
def test_parse_lanes(spec, expected):
    assert fleet_worker.parse_lanes(spec) == expected


def test_stale_claim_is_reclaimed_as_a_lease(tmp_path):
    # A worker that crashed after claiming must not strand the task: an expired
    # claim lease is claimable again by a replacement worker.
    db = _board(tmp_path, [
        {"id": "T-1", "lane": "build", "status": "claimed",
         "assignee": "xdead-1", "claimedAt": "2020-01-01T00:00:00Z"},
    ])
    config = _config(tmp_path, db, lanes=["build"], claim_lease_seconds=60.0)
    task = fleet_worker.claim_next_task(config)
    assert task is not None and task["id"] == "T-1"
    assert task["assignee"] == "xtest-1"


def test_fresh_claim_is_not_stolen(tmp_path):
    db = _board(tmp_path, [
        {"id": "T-1", "lane": "build", "status": "claimed",
         "assignee": "xother-1", "claimedAt": fleet_worker._utc_now()},
    ])
    config = _config(tmp_path, db, lanes=["build"], claim_lease_seconds=60.0)
    assert fleet_worker.claim_next_task(config) is None


def test_enqueue_appends_under_lock(tmp_path):
    db = _board(tmp_path, [
        {"id": "T1", "lane": "build", "status": "open", "prompt": "a"},
    ])
    config = _config(tmp_path, db)
    assert fleet_worker.enqueue_task(
        config, {"id": "T2", "lane": "build", "status": "open", "prompt": "b"}) is True
    assert [t["id"] for t in _tasks(db)] == ["T1", "T2"]
    assert not (tmp_path / "board.lock").exists()  # lock released after the append


def test_enqueue_missing_board_fails_and_releases_lock(tmp_path):
    config = _config(tmp_path, tmp_path / "nope.json")
    assert fleet_worker.enqueue_task(config, {"id": "T1"}) is False
    assert not (tmp_path / "nope.json").exists()  # never invents a board
    assert not (tmp_path / "board.lock").exists()


def test_enqueue_rejects_non_dict_task(tmp_path):
    db = _board(tmp_path, [])
    with pytest.raises(TypeError):
        fleet_worker.enqueue_task(_config(tmp_path, db), ["not", "a", "task"])  # type: ignore[arg-type]


def test_enqueue_times_out_while_lock_is_held(tmp_path):
    db = _board(tmp_path, [])
    lock = tmp_path / "board.lock"
    # A live holder: our own pid is definitely alive, so the lock is not stale.
    lock.write_text(json.dumps({"pid": os.getpid(), "assignee": "other"}), encoding="utf-8")
    assert fleet_worker.enqueue_task(_config(tmp_path, db), {"id": "T1"}) is False
    assert _tasks(db) == []  # board untouched


def test_enqueue_waits_for_worker_lock_and_neither_mutation_is_lost(tmp_path):
    # The stale-snapshot regression: a worker mutates the board while holding
    # the claim lock; a concurrent external append must serialize behind that
    # lock so BOTH the worker's claim and the enqueued task survive.
    db = _board(tmp_path, [
        {"id": "T1", "lane": "build", "status": "open", "prompt": "a"},
    ])
    config = _config(tmp_path, db, lock_timeout_seconds=5.0)
    assert fleet_worker.acquire_claim_lock(config.lock_path, "worker", 0.05) is True

    result: dict = {}
    thread = threading.Thread(target=lambda: result.update(
        ok=fleet_worker.enqueue_task(
            config, {"id": "T2", "lane": "build", "status": "open", "prompt": "b"})))
    thread.start()
    try:
        # The worker's critical section, performed while the enqueue spins on
        # the lock: load the board fresh, claim T1, save.
        board = fleet_worker.load_board(db)
        board["tasks"][0]["status"] = "claimed"
        board["tasks"][0]["assignee"] = "worker"
        fleet_worker.save_board(db, board)
    finally:
        fleet_worker.release_claim_lock(config.lock_path)
    thread.join(timeout=10.0)
    assert not thread.is_alive() and result["ok"] is True

    persisted = {t["id"]: t for t in _tasks(db)}
    assert persisted["T1"]["status"] == "claimed"  # worker mutation preserved
    assert persisted["T2"]["status"] == "open"     # enqueued task preserved
    assert not (tmp_path / "board.lock").exists()


def test_parse_args_enqueue():
    assert fleet_worker._parse_args([]).enqueue == ""
    args = fleet_worker._parse_args(["--enqueue", '{"id": "T9"}'])
    assert args.enqueue == '{"id": "T9"}'


def test_main_enqueue_appends_and_exits_zero(tmp_path, monkeypatch):
    db = _board(tmp_path, [])
    monkeypatch.setenv(fleet_worker.ENV_DB, str(db))
    monkeypatch.setenv(fleet_worker.ENV_CLAIM_LOCK, str(tmp_path / "board.lock"))
    rc = fleet_worker.main(["--enqueue", json.dumps(
        {"id": "T-9", "lane": "build", "status": "open", "prompt": "x"})])
    assert rc == 0
    (task,) = _tasks(db)
    assert task["id"] == "T-9"


@pytest.mark.parametrize("bad", ["not json", "[1, 2]", '"a string"'])
def test_main_enqueue_rejects_bad_payloads(tmp_path, monkeypatch, bad):
    db = _board(tmp_path, [])
    monkeypatch.setenv(fleet_worker.ENV_DB, str(db))
    monkeypatch.setenv(fleet_worker.ENV_CLAIM_LOCK, str(tmp_path / "board.lock"))
    assert fleet_worker.main(["--enqueue", bad]) == 2
    assert _tasks(db) == []  # nothing appended


def test_claim_lease_uses_utc_during_daylight_saving_time():
    if not hasattr(time, "tzset"):
        return  # Windows has no process-local TZ switch; calendar.timegm is still portable.

    env = os.environ.copy()
    env["TZ"] = "America/Chicago"
    script = """
import calendar
from helios_agents import fleet_worker

claimed_at = "2026-08-10T12:00:00Z"
now = calendar.timegm(__import__("time").strptime(
    "2026-08-10T12:01:00Z", "%Y-%m-%dT%H:%M:%SZ"))
fleet_worker.time.time = lambda: now
assert not fleet_worker._claim_expired({"claimedAt": claimed_at}, 300.0)
"""
    subprocess.run([sys.executable, "-c", script], check=True, env=env, timeout=30)
