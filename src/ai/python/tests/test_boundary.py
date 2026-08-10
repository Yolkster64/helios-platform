"""The subprocess JSON boundary the C# orchestrator depends on."""

import json
import subprocess
import sys
from pathlib import Path

import pytest

from helios_agents import __main__ as boundary

SPOKE_DIR = Path(__file__).resolve().parent.parent


def _invoke(payload: str) -> tuple[int, dict]:
    proc = subprocess.run(
        [sys.executable, "-m", "helios_agents"],
        input=payload, capture_output=True, text=True, cwd=SPOKE_DIR, timeout=60)
    return proc.returncode, json.loads(proc.stdout)


def test_round_trip_provider_summary():
    request = {"op": "provider_summary", "outcomes": [
        {"provider": "openai", "success": True, "latencyMs": 120.0, "costUsd": 0.002},
    ]}
    code, response = _invoke(json.dumps(request))
    assert code == 0
    assert response["ok"] is True
    assert response["result"]["providers"]["openai"]["attempts"] == 1


def test_unknown_op_names_the_known_ops():
    code, response = _invoke(json.dumps({"op": "nope"}))
    assert code == 1
    assert response["ok"] is False
    assert "provider_summary" in response["error"]
    assert "group_similar" in response["error"]


def test_malformed_json_is_reported_not_crashed():
    code, response = _invoke("{not json")
    assert code == 1
    assert response["ok"] is False


@pytest.mark.parametrize("request_dict", [
    {"op": "provider_summary", "outcomes": "not-a-list"},
    {"op": "keywords", "texts": [1, 2]},
    {"op": "engine_catalog", "cudaEnabled": "false"},
    {"op": "engine_catalog", "nativeAvailable": "false"},
    {"op": "recommend_engines", "fleetSize": "36"},
    {"op": "recommend_engines", "optimizationPressure": True},
])
def test_bad_arguments_raise_actionable_errors(request_dict):
    with pytest.raises(ValueError):
        boundary.run(request_dict)


def test_run_dispatches_every_op():
    assert boundary.run({"op": "detect_drift", "outcomes": []}) == {
        "drifting": [], "checked": 0}
    assert boundary.run({"op": "keywords", "texts": ["alpha alpha beta"]})[
        "keywords"][0]["token"] == "alpha"
    assert boundary.run({"op": "group_similar", "texts": ["x y z"]})["groups"] == [[0]]
    assert boundary.run({"op": "engine_catalog"})["candidate_count"] == 0
    plan = boundary.run({
        "op": "recommend_engines",
        "securityProfile": "balanced",
        "optimizationPressure": 0.5,
        "fleetSize": 36,
        "includeCandidates": True,
    })
    assert plan["selected_count"] > 0
    assert plan["candidate_count"] > 0


def test_round_trip_engine_recommendation():
    code, response = _invoke(json.dumps({
        "op": "recommend_engines",
        "cudaEnabled": False,
        "securityProfile": "hardened",
        "optimizationPressure": 0.8,
        "fleetSize": 36,
        "includeCandidates": True,
    }))

    assert code == 0
    assert response["ok"] is True
    assert response["result"]["selected_count"] > 0
    assert response["result"]["candidate_count"] > 0
