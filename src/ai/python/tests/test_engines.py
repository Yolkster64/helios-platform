from pathlib import Path

import pytest

from helios_agents import engines


def test_catalog_defaults_to_implemented_truth_only():
    catalog = engines.build_engine_catalog()

    assert catalog["total_engines"] >= 5
    assert catalog["candidate_count"] == 0
    assert catalog["parallelization_candidates"] == []
    assert catalog["hybridization_candidates"] == []
    assert all(item["maturity"] == "implemented" for item in catalog["engines"])
    assert all(item["implementation"] for item in catalog["engines"])
    assert all("runtime_available" in item for item in catalog["engines"])
    repo_root = Path(__file__).resolve().parents[4]
    assert all((repo_root / item["implementation"]).is_file() for item in catalog["engines"])
    assert len({item["name"] for item in catalog["engines"]}) == catalog["total_engines"]


def test_catalog_preserves_recovered_candidates_without_calling_them_implemented():
    catalog = engines.build_engine_catalog(include_candidates=True)

    by_name = {item["name"]: item for item in catalog["engines"]}
    assert by_name["chaos-engine"]["maturity"] == "concept"
    assert by_name["mesh-consensus-engine"]["maturity"] == "concept"
    assert catalog["candidate_count"] > 20
    assert all(
        candidate["maturity"] == "concept"
        for candidate in catalog["parallelization_candidates"])
    assert all(
        candidate["maturity"] == "concept"
        for candidate in catalog["hybridization_candidates"])


def test_cuda_is_a_requirement_not_a_generic_capability_flag():
    cpu_catalog = engines.build_engine_catalog(cuda_enabled=False, include_candidates=True)
    gpu_catalog = engines.build_engine_catalog(cuda_enabled=True, include_candidates=True)

    cpu_names = {item["name"] for item in cpu_catalog["engines"]}
    gpu_names = {item["name"] for item in gpu_catalog["engines"]}
    assert "gnaa-graph-attention" not in cpu_names
    assert "gnaa-graph-attention" in gpu_names
    assert "linear-regression" in cpu_names


def test_cpu_hybrid_candidates_reference_catalog_ids_and_require_no_cuda():
    catalog = engines.build_engine_catalog(cuda_enabled=False, include_candidates=True)
    names = {item["name"] for item in catalog["engines"]}

    for candidate in catalog["hybridization_candidates"]:
        assert candidate["requires_cuda"] is False
        assert set(candidate["components"]).issubset(names)


def test_recommendation_never_promotes_concepts_to_selected_engines():
    plan = engines.recommend_engine_mix(
        cuda_enabled=True,
        security_profile="paranoid",
        optimization_pressure=0.9,
        fleet_size=36,
        include_candidates=True,
    )

    assert plan["selected_count"] > 0
    assert all(item["maturity"] == "implemented" for item in plan["selected_engines"])
    assert all(item["runtime_available"] is True for item in plan["selected_engines"])
    assert plan["candidate_count"] >= 5
    assert all(item["maturity"] != "implemented" for item in plan["candidate_engines"])
    assert "security" in plan["missing_implemented_families"]


def test_recommendation_inputs_change_the_selected_implemented_mix():
    conservative = engines.recommend_engine_mix(
        cuda_enabled=False,
        security_profile="balanced",
        optimization_pressure=0.0,
        fleet_size=0,
    )
    scaled = engines.recommend_engine_mix(
        cuda_enabled=False,
        security_profile="paranoid",
        optimization_pressure=0.8,
        fleet_size=36,
    )

    conservative_names = {item["name"] for item in conservative["selected_engines"]}
    scaled_names = {item["name"] for item in scaled["selected_engines"]}
    assert conservative_names < scaled_names


@pytest.mark.parametrize(
    "kwargs",
    [
        {"security_profile": "unknown", "optimization_pressure": 0.5, "fleet_size": 1},
        {"security_profile": "balanced", "optimization_pressure": -0.1, "fleet_size": 1},
        {"security_profile": "balanced", "optimization_pressure": 1.1, "fleet_size": 1},
        {"security_profile": "balanced", "optimization_pressure": 0.5, "fleet_size": -1},
        {"security_profile": "balanced", "optimization_pressure": 0.5, "fleet_size": True},
        {"security_profile": "balanced", "optimization_pressure": True, "fleet_size": 1},
    ],
)
def test_recommendation_rejects_invalid_inputs(kwargs):
    with pytest.raises(ValueError):
        engines.recommend_engine_mix(
            cuda_enabled=False,
            include_candidates=False,
            **kwargs,
        )


@pytest.mark.parametrize(
    "field",
    ["cuda_enabled", "include_candidates", "managed_available", "native_available"],
)
def test_public_functions_reject_non_boolean_flags(field):
    catalog_args = {
        "cuda_enabled": False,
        "include_candidates": False,
        "managed_available": False,
        "native_available": False,
    }
    catalog_args[field] = "false"
    with pytest.raises(ValueError):
        engines.build_engine_catalog(**catalog_args)

    recommendation_args = {
        "cuda_enabled": False,
        "security_profile": "balanced",
        "optimization_pressure": 0.5,
        "fleet_size": 1,
        "include_candidates": False,
        "managed_available": False,
        "native_available": False,
    }
    recommendation_args[field] = "false"
    with pytest.raises(ValueError):
        engines.recommend_engine_mix(**recommendation_args)
