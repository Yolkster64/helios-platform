"""Subprocess JSON boundary: one request on stdin, one response on stdout.

Request shape: ``{"op": <name>, ...op-specific fields}``. The response envelope is
``{"ok": true, "result": {...}}`` or ``{"ok": false, "error": "..."}`` with a
non-zero exit code, so the C# orchestrator can always parse stdout.

With argv present the boundary instead runs one of the fleet-lane
subcommands and prints the operation's result JSON (no envelope) on stdout —
``{"error": "..."}`` with exit code 1 on failure::

    python3 -m helios_agents fleet-collect --run-dir <dir> --outcomes <path>
    python3 -m helios_agents fleet-summary --outcomes <path> [--scale-log <path>]
"""

from __future__ import annotations

import argparse
import json
import sys

from . import analysis, engines, fleet_learning, textwork


def _outcomes(request: dict) -> list:
    outcomes = request.get("outcomes")
    if not isinstance(outcomes, list):
        raise ValueError(
            "'outcomes' must be a list of routing-outcome objects, chronological (oldest first).")
    return outcomes


def _texts(request: dict) -> list:
    texts = request.get("texts")
    if not isinstance(texts, list) or not all(isinstance(t, str) for t in texts):
        raise ValueError("'texts' must be a list of strings.")
    return texts


def _bool(request: dict, key: str, default: bool = False) -> bool:
    value = request.get(key, default)
    if not isinstance(value, bool):
        raise ValueError(f"'{key}' must be a JSON boolean")
    return value


def _path(request: dict, key: str) -> str:
    value = request.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"'{key}' must be a non-empty path string")
    return value


def _optional_path(request: dict, key: str) -> str | None:
    if request.get(key) is None:
        return None
    return _path(request, key)


_OPS = {
    "provider_summary": lambda r: analysis.provider_summary(_outcomes(r)),
    "detect_drift": lambda r: analysis.detect_drift(_outcomes(r)),
    "keywords": lambda r: textwork.keywords(_texts(r), int(r.get("topN", 10))),
    "group_similar": lambda r: textwork.group_similar(_texts(r), float(r.get("threshold", 0.6))),
    "engine_catalog": lambda r: engines.build_engine_catalog(
        cuda_enabled=_bool(r, "cudaEnabled"),
        include_candidates=_bool(r, "includeCandidates"),
        managed_available=_bool(r, "managedAvailable"),
        native_available=_bool(r, "nativeAvailable"),
    ),
    "recommend_engines": lambda r: engines.recommend_engine_mix(
        cuda_enabled=_bool(r, "cudaEnabled"),
        security_profile=r.get("securityProfile", "balanced"),
        optimization_pressure=r.get("optimizationPressure", 0.5),
        fleet_size=r.get("fleetSize", 0),
        include_candidates=_bool(r, "includeCandidates"),
        managed_available=_bool(r, "managedAvailable"),
        native_available=_bool(r, "nativeAvailable"),
    ),
    "fleet_collect": lambda r: fleet_learning.collect(
        _path(r, "runDir"), _path(r, "outcomes")),
    "fleet_summary": lambda r: fleet_learning.fleet_summary(
        _path(r, "outcomes"), _optional_path(r, "scaleLog")),
}


def run(request: dict) -> dict:
    op = request.get("op")
    if op not in _OPS:
        raise ValueError(f"unknown op {op!r}; known ops: {', '.join(sorted(_OPS))}")
    return _OPS[op](request)


def _parse_cli(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="python3 -m helios_agents",
        description="Fleet-lane subcommands; with no argv the stdin JSON "
                    "boundary runs instead (module docstring).")
    subcommands = parser.add_subparsers(dest="command", required=True)
    collect = subcommands.add_parser(
        "fleet-collect",
        help="append finished fleet-run board tasks to a learning-store JSONL")
    collect.add_argument(
        "--run-dir", required=True,
        help="fleet run directory (.helios/fleet/<runId>: manifest.json + boards/)")
    collect.add_argument(
        "--outcomes", required=True,
        help="learning-store JSONL path to append RoutingOutcome records to")
    summary = subcommands.add_parser(
        "fleet-summary", help="per-pool stats over fleet-lane learning records")
    summary.add_argument(
        "--outcomes", required=True, help="learning-store JSONL path to read")
    summary.add_argument(
        "--scale-log", default="",
        help="optional .helios/fleet/scale-log.jsonl to correlate scaling events")
    return parser.parse_args(argv)


def _run_cli(argv: list[str]) -> int:
    args = _parse_cli(argv)
    try:
        if args.command == "fleet-collect":
            result = fleet_learning.collect(args.run_dir, args.outcomes)
        else:
            result = fleet_learning.fleet_summary(args.outcomes, args.scale_log or None)
    except Exception as exc:
        sys.stdout.write(json.dumps({"error": str(exc)}) + "\n")
        return 1
    sys.stdout.write(json.dumps(result) + "\n")
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv:
        return _run_cli(argv)
    try:
        request = json.load(sys.stdin)
        if not isinstance(request, dict):
            raise ValueError("request must be a single JSON object")
        result = run(request)
    except Exception as exc:
        json.dump({"ok": False, "error": str(exc)}, sys.stdout)
        return 1
    json.dump({"ok": True, "result": result}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
