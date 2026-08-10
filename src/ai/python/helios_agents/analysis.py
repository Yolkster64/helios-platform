"""Routing-outcome analytics.

Pure functions over outcome dicts shaped like the C# ``RoutingOutcome``:
``{"provider": str, "success": bool, "latencyMs": float, "costUsd": float,
"quality": float | None}`` in chronological order (oldest first).

numpy is used when installed; the pure-Python paths keep the spoke working on
any box with a bare interpreter.
"""

from __future__ import annotations

try:
    import numpy as _np
except ImportError:  # pragma: no cover - exercised on bare interpreters
    _np = None

RECENT_WINDOW = 5
DRIFT_MIN_ATTEMPTS = 8
DRIFT_THRESHOLD = 0.25


def _mean(values: list[float]) -> float:
    if not values:
        return 0.0
    if _np is not None:
        return float(_np.mean(values))
    return sum(values) / len(values)


def _std(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    if _np is not None:
        return float(_np.std(values))
    mu = _mean(values)
    return (sum((v - mu) ** 2 for v in values) / len(values)) ** 0.5


def provider_summary(outcomes: list[dict]) -> dict:
    """Per-provider stats plus a recent-window success rate for trend reading."""
    by_provider: dict[str, list[dict]] = {}
    for outcome in outcomes:
        by_provider.setdefault(outcome["provider"], []).append(outcome)

    providers = {}
    for name, rows in sorted(by_provider.items()):
        successes = [1.0 if r["success"] else 0.0 for r in rows]
        latencies = [float(r["latencyMs"]) for r in rows]
        costs = [float(r["costUsd"]) for r in rows]
        qualities = [float(r["quality"]) for r in rows if r.get("quality") is not None]
        recent = successes[-RECENT_WINDOW:]
        providers[name] = {
            "attempts": len(rows),
            "successRate": round(_mean(successes), 4),
            "recentSuccessRate": round(_mean(recent), 4),
            "avgLatencyMs": round(_mean(latencies), 2),
            "latencyStdMs": round(_std(latencies), 2),
            "avgCostUsd": round(_mean(costs), 6),
            "totalCostUsd": round(sum(costs), 6),
            "avgQuality": round(_mean(qualities), 4) if qualities else None,
        }

    return {
        "totalOutcomes": len(outcomes),
        "providers": providers,
        "backend": "numpy" if _np is not None else "pure-python",
    }


def detect_drift(outcomes: list[dict]) -> dict:
    """Providers whose recent success rate has moved away from their overall rate.

    Flags only providers with enough evidence (>= DRIFT_MIN_ATTEMPTS) and a gap
    of at least DRIFT_THRESHOLD, so a single bad call never raises an alert.
    """
    summary = provider_summary(outcomes)
    drifting = []
    for name, stats in summary["providers"].items():
        if stats["attempts"] < DRIFT_MIN_ATTEMPTS:
            continue
        gap = stats["recentSuccessRate"] - stats["successRate"]
        if abs(gap) >= DRIFT_THRESHOLD:
            drifting.append({
                "provider": name,
                "successRate": stats["successRate"],
                "recentSuccessRate": stats["recentSuccessRate"],
                "direction": "improving" if gap > 0 else "degrading",
            })
    return {"drifting": drifting, "checked": len(summary["providers"])}
