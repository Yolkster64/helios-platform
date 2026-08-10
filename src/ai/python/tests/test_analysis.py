from helios_agents import analysis


def _outcome(provider, success, latency=100.0, cost=0.001, quality=None):
    return {
        "provider": provider,
        "success": success,
        "latencyMs": latency,
        "costUsd": cost,
        "quality": quality,
    }


def test_provider_summary_empty():
    result = analysis.provider_summary([])
    assert result["totalOutcomes"] == 0
    assert result["providers"] == {}
    assert result["backend"] in ("numpy", "pure-python")


def test_provider_summary_per_provider_stats():
    outcomes = [
        _outcome("openai", True, latency=200.0, cost=0.002, quality=0.9),
        _outcome("anthropic", False, latency=400.0, cost=0.004),
        _outcome("openai", False, latency=100.0, cost=0.001, quality=0.5),
    ]
    result = analysis.provider_summary(outcomes)
    openai = result["providers"]["openai"]
    assert openai["attempts"] == 2
    assert openai["successRate"] == 0.5
    assert openai["avgLatencyMs"] == 150.0
    assert openai["totalCostUsd"] == 0.003
    assert openai["avgQuality"] == 0.7
    anthropic = result["providers"]["anthropic"]
    assert anthropic["successRate"] == 0.0
    assert anthropic["avgQuality"] is None


def test_recent_success_rate_uses_tail_window():
    outcomes = [_outcome("p", True)] * 10 + [_outcome("p", False)] * 5
    stats = analysis.provider_summary(outcomes)["providers"]["p"]
    assert stats["successRate"] == round(10 / 15, 4)
    assert stats["recentSuccessRate"] == 0.0


def test_detect_drift_flags_degrading_provider():
    outcomes = [_outcome("worsening", True)] * 8 + [_outcome("worsening", False)] * 4
    outcomes += [_outcome("steady", True)] * 12
    result = analysis.detect_drift(outcomes)
    assert result["checked"] == 2
    assert len(result["drifting"]) == 1
    flagged = result["drifting"][0]
    assert flagged["provider"] == "worsening"
    assert flagged["direction"] == "degrading"


def test_detect_drift_ignores_thin_evidence():
    outcomes = [_outcome("new", True)] * 2 + [_outcome("new", False)] * 3
    result = analysis.detect_drift(outcomes)
    assert result["drifting"] == []
