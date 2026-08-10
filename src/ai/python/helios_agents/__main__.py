"""Subprocess JSON boundary: one request on stdin, one response on stdout.

Request shape: ``{"op": <name>, ...op-specific fields}``. The response envelope is
``{"ok": true, "result": {...}}`` or ``{"ok": false, "error": "..."}`` with a
non-zero exit code, so the C# orchestrator can always parse stdout.
"""

from __future__ import annotations

import json
import sys

from . import analysis, textwork


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


_OPS = {
    "provider_summary": lambda r: analysis.provider_summary(_outcomes(r)),
    "detect_drift": lambda r: analysis.detect_drift(_outcomes(r)),
    "keywords": lambda r: textwork.keywords(_texts(r), int(r.get("topN", 10))),
    "group_similar": lambda r: textwork.group_similar(_texts(r), float(r.get("threshold", 0.6))),
}


def run(request: dict) -> dict:
    op = request.get("op")
    if op not in _OPS:
        raise ValueError(f"unknown op {op!r}; known ops: {', '.join(sorted(_OPS))}")
    return _OPS[op](request)


def main() -> int:
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
