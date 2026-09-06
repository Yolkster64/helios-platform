#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from typing import Any

ALLOWLISTED_DIAGNOSTIC_PREFIXES = (
    "ERROR:",
    "WARNING:",
    "Code:",
    "Message:",
    "Details:",
    "DeploymentFailed",
    "Operation returned an invalid status",
    "Status Message:",
)
ALLOWLISTED_DEPLOY_RESULT_KEYS = (
    "name",
    "id",
    "resourceGroup",
    "provisioningState",
    "timestamp",
)
WHAT_IF_CHANGE_TYPES = ("Create", "Modify", "Delete")


def _read_text(path: pathlib.Path | None) -> str:
    if path is None or not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def _sha256(path: pathlib.Path | None) -> str | None:
    if path is None or not path.exists():
        return None
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _extract_diagnostics(stderr_text: str) -> list[str]:
    diagnostics: list[str] = []
    for raw_line in stderr_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(ALLOWLISTED_DIAGNOSTIC_PREFIXES):
            diagnostics.append(line[:500])
    return diagnostics[-20:]


def _load_json(path: pathlib.Path | None) -> tuple[Any | None, str]:
    text = _read_text(path)
    if not text.strip():
        return None, "empty"
    try:
        return json.loads(text), "json"
    except json.JSONDecodeError:
        return None, "invalid-json"


def _build_what_if_summary(payload: Any) -> dict[str, int]:
    counts = {key.lower(): 0 for key in WHAT_IF_CHANGE_TYPES}
    changes = (((payload or {}).get("properties") or {}).get("changes") or []) if isinstance(payload, dict) else []
    for change in changes:
        if not isinstance(change, dict):
            continue
        change_type = str(change.get("changeType", ""))
        if change_type in WHAT_IF_CHANGE_TYPES:
            counts[change_type.lower()] += 1
    return counts


def _build_deploy_result(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {}
    return {
        key: payload[key]
        for key in ALLOWLISTED_DEPLOY_RESULT_KEYS
        if key in payload
    }


def build_record(args: argparse.Namespace) -> dict[str, Any]:
    stdout_payload, stdout_status = _load_json(args.stdout_file)
    stderr_text = _read_text(args.stderr_file)
    record: dict[str, Any] = {
        "phase": args.phase,
        "deploymentName": args.deployment_name,
        "timestamp": args.timestamp,
        "exitCode": args.exit_code,
        "diagnostics": _extract_diagnostics(stderr_text),
    }

    stdout_digest = _sha256(args.stdout_file)
    stderr_digest = _sha256(args.stderr_file)
    if stdout_digest is not None:
        record["stdoutDigestSha256"] = stdout_digest
    if stderr_digest is not None:
        record["stderrDigestSha256"] = stderr_digest

    if args.phase == "what-if":
        record["summary"] = _build_what_if_summary(stdout_payload)
        record["stdoutStatus"] = stdout_status
    elif args.phase == "deploy":
        record["result"] = _build_deploy_result(stdout_payload)
        record["stdoutStatus"] = stdout_status
    else:
        record["stdoutStatus"] = stdout_status

    return record


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Emit sanitized deploy custody records.")
    parser.add_argument("--phase", required=True)
    parser.add_argument("--deployment-name", required=True)
    parser.add_argument("--timestamp", required=True)
    parser.add_argument("--exit-code", required=True, type=int)
    parser.add_argument("--record-file", required=True, type=pathlib.Path)
    parser.add_argument("--stdout-file", type=pathlib.Path)
    parser.add_argument("--stderr-file", type=pathlib.Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    record = build_record(args)
    args.record_file.parent.mkdir(parents=True, exist_ok=True)
    args.record_file.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
