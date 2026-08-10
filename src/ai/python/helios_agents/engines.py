"""Truthful capability catalog and resource-aware engine recommendations.

This module salvages the useful taxonomy from the recovered AIHub prototypes without
pretending that every named algorithm is already implemented. Implemented entries name
their checked-in source; prototype/concept entries are candidates only. Runtime
availability is deliberately reported separately because this advisory does not load or
probe native binaries.

The module is deliberately dependency-free.  It is called through the same one-request /
one-response subprocess boundary as the other Python analytics spokes.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from math import isfinite
from typing import Any


MATURITY_IMPLEMENTED = "implemented"
MATURITY_PROTOTYPE = "prototype"
MATURITY_CONCEPT = "concept"
MATURITIES = frozenset({MATURITY_IMPLEMENTED, MATURITY_PROTOTYPE, MATURITY_CONCEPT})
SECURITY_PROFILES = frozenset({"balanced", "hardened", "paranoid", "performance"})


@dataclass(frozen=True)
class EngineSpec:
    """One capability with explicit readiness and implementation evidence."""

    name: str
    family: str
    tier: str
    backend: str
    requires_cuda: bool
    objective: str
    memory_class: str
    maturity: str
    implementation: str | None = None
    provenance: str = "recovered-aihub-prototype"
    runtime_available: bool | None = None

    def __post_init__(self) -> None:
        if self.maturity not in MATURITIES:
            raise ValueError(f"invalid maturity {self.maturity!r}")
        if self.maturity == MATURITY_IMPLEMENTED and not self.implementation:
            raise ValueError(f"implemented engine {self.name!r} needs implementation evidence")


def _recovered(
    name: str,
    family: str,
    tier: str,
    backend: str,
    objective: str,
    memory_class: str,
    *,
    requires_cuda: bool = False,
    maturity: str = MATURITY_CONCEPT,
) -> EngineSpec:
    return EngineSpec(
        name,
        family,
        tier,
        backend,
        requires_cuda,
        objective,
        memory_class,
        maturity,
    )


def _engine_specs() -> tuple[EngineSpec, ...]:
    # The first entries describe code that exists on this branch.  Everything imported
    # from the recovery bundle is explicitly prototype/concept until an implementation
    # and a validating test are added.
    return (
        EngineSpec(
            "routing-policy",
            "routing",
            "core",
            "fsharp",
            False,
            "evidence-weighted provider ordering",
            "low",
            MATURITY_IMPLEMENTED,
            "src/ai/HELIOS.AIHub.Domain/RoutingPolicy.fs",
            "repository",
        ),
        EngineSpec(
            "online-sgd-router",
            "routing",
            "core",
            "cpp",
            False,
            "online provider-score refinement",
            "low",
            MATURITY_IMPLEMENTED,
            "src/ai/HELIOS.AIHub.Native/helios_aihub_native.cpp",
            "repository",
        ),
        EngineSpec(
            "provider-outcome-analytics",
            "analytics",
            "core",
            "python",
            False,
            "provider success, latency, cost, and quality summaries",
            "low",
            MATURITY_IMPLEMENTED,
            "src/ai/python/helios_agents/analysis.py",
            "repository",
        ),
        EngineSpec(
            "drift-detector",
            "governance",
            "core",
            "python",
            False,
            "routing-outcome drift detection",
            "low",
            MATURITY_IMPLEMENTED,
            "src/ai/python/helios_agents/analysis.py",
            "repository",
        ),
        EngineSpec(
            "cosine-dedup-kernel",
            "retrieval",
            "support",
            "cpp",
            False,
            "near-duplicate response detection",
            "low",
            MATURITY_IMPLEMENTED,
            "src/ai/HELIOS.AIHub.Native/helios_aihub_native.cpp",
            "repository",
        ),
        EngineSpec(
            "utf8-token-estimator",
            "compression",
            "support",
            "cpp",
            False,
            "bounded UTF-8 context estimation and prefix fitting",
            "low",
            MATURITY_IMPLEMENTED,
            "src/ai/HELIOS.AIHub.Native/helios_aihub_native.cpp",
            "repository",
        ),
        _recovered(
            "contextual-bandit-router", "routing", "advanced", "python",
            "contextual provider selection", "low", maturity=MATURITY_PROTOTYPE,
        ),
        _recovered(
            "gaussian-regression", "regression", "core", "python",
            "continuous signal fitting", "medium",
        ),
        _recovered(
            "linear-regression", "regression", "core", "python",
            "baseline predictive fit", "low",
        ),
        _recovered(
            "ridge-regression", "regression", "core", "python",
            "regularized trend learning", "low",
        ),
        _recovered(
            "lasso-regression", "regression", "core", "python",
            "sparse feature selection", "low",
        ),
        _recovered(
            "elasticnet-regression", "regression", "core", "python",
            "hybrid sparse regularization", "low",
        ),
        _recovered(
            "extreme-calculus-solver", "symbolic", "advanced", "csharp",
            "differential optimization", "medium",
        ),
        _recovered(
            "geometry-topology-optimizer", "geometry", "advanced", "csharp",
            "spatial route shaping", "medium",
        ),
        _recovered(
            "gaussian-blur-anomaly", "vision", "support", "cpp",
            "noise suppression and anomaly preparation", "low",
        ),
        _recovered(
            "knn-clustering", "clustering", "core", "python",
            "nearest-neighbor grouping", "medium",
        ),
        _recovered(
            "knaa-routing", "mesh", "advanced", "python",
            "k-neighbor adaptive allocation", "high", requires_cuda=True,
        ),
        _recovered(
            "gnaa-graph-attention", "graph", "advanced", "python",
            "graph-attention fleet policy", "high", requires_cuda=True,
        ),
        _recovered(
            "rnaa-recurrent-anomaly", "sequence", "advanced", "python",
            "temporal anomaly scoring", "high", requires_cuda=True,
        ),
        _recovered(
            "rnn-sequence-predictor", "sequence", "core", "python",
            "sequence forecasting", "high", requires_cuda=True,
        ),
        _recovered(
            "transformer-router", "routing", "advanced", "python",
            "learned route selection", "high", requires_cuda=True,
        ),
        _recovered(
            "autoencoder-shape-compressor", "compression", "core", "python",
            "latent compression", "medium", requires_cuda=True,
        ),
        _recovered(
            "variational-autoencoder", "compression", "advanced", "python",
            "distributional latent spaces", "high", requires_cuda=True,
        ),
        _recovered(
            "pca-fast-compressor", "compression", "support", "cpp",
            "low-memory dimension reduction", "low",
        ),
        _recovered(
            "chaos-engine", "exploration", "experimental", "python",
            "bounded stochastic exploration", "medium",
        ),
        _recovered(
            "natural-selection-engine", "evolutionary", "advanced", "python",
            "candidate survival optimization", "medium",
        ),
        _recovered(
            "genetic-policy-search", "evolutionary", "advanced", "python",
            "policy mutation and crossover", "medium",
        ),
        _recovered(
            "bayesian-optimizer", "optimization", "core", "python",
            "hyperparameter optimization", "medium",
        ),
        _recovered(
            "simulated-annealing", "optimization", "support", "cpp",
            "global objective search", "low",
        ),
        _recovered(
            "multi-armed-bandit-swarm", "routing", "advanced", "python",
            "swarm routing policy", "medium",
        ),
        _recovered(
            "mesh-consensus-engine", "mesh", "advanced", "csharp",
            "fleet consensus propagation", "medium",
        ),
        _recovered(
            "sql-pattern-miner", "analytics", "core", "python",
            "training-signal extraction", "low",
        ),
        _recovered(
            "vector-retrieval-ranker", "retrieval", "core", "python",
            "semantic ranking", "medium", requires_cuda=True,
        ),
        _recovered(
            "security-anomaly-core", "security", "core", "cpp",
            "runtime threat scoring", "low",
        ),
        _recovered(
            "memory-pressure-optimizer", "optimization", "support", "cpp",
            "memory pressure control", "low",
        ),
    )


PARALLELIZATION_CANDIDATES = (
    {"name": "task-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "data-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "pipeline-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "model-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "fleet-swarm-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "multi-llm-routing-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "subagent-specialist-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "hybrid-mesh-parallel", "maturity": MATURITY_CONCEPT},
    {"name": "async-event-parallel", "maturity": MATURITY_CONCEPT},
)

HYBRIDIZATION_CANDIDATES = (
    {
        "name": "chaos+bandit",
        "components": ("chaos-engine", "contextual-bandit-router"),
        "requires_cuda": False,
        "maturity": MATURITY_CONCEPT,
    },
    {
        "name": "natural-selection+bayesian",
        "components": ("natural-selection-engine", "bayesian-optimizer"),
        "requires_cuda": False,
        "maturity": MATURITY_CONCEPT,
    },
    {
        "name": "graph-attention+mesh-consensus",
        "components": ("gnaa-graph-attention", "mesh-consensus-engine"),
        "requires_cuda": True,
        "maturity": MATURITY_CONCEPT,
    },
    {
        "name": "autoencoder+vector-retrieval",
        "components": ("autoencoder-shape-compressor", "vector-retrieval-ranker"),
        "requires_cuda": True,
        "maturity": MATURITY_CONCEPT,
    },
    {
        "name": "security-anomaly+drift-detector",
        "components": ("security-anomaly-core", "drift-detector"),
        "requires_cuda": False,
        "maturity": MATURITY_CONCEPT,
    },
)


def _eligible(cuda_enabled: bool) -> list[EngineSpec]:
    return [spec for spec in _engine_specs() if cuda_enabled or not spec.requires_cuda]


def _validate_bool(value: object, name: str) -> None:
    if not isinstance(value, bool):
        raise ValueError(f"{name} must be a boolean")


def _runtime_available(
    spec: EngineSpec, *, managed_available: bool, native_available: bool
) -> bool | None:
    if spec.maturity != MATURITY_IMPLEMENTED:
        return None
    if spec.backend == "python":
        return True
    if spec.backend in {"csharp", "fsharp"}:
        return managed_available
    if spec.backend == "cpp":
        return native_available
    return False


def _materialize(
    spec: EngineSpec, *, managed_available: bool, native_available: bool
) -> dict[str, Any]:
    value = asdict(spec)
    value["runtime_available"] = _runtime_available(
        spec,
        managed_available=managed_available,
        native_available=native_available,
    )
    return value


def _hybridization_candidates(cuda_enabled: bool) -> list[dict[str, Any]]:
    return [
        {**candidate, "components": list(candidate["components"])}
        for candidate in HYBRIDIZATION_CANDIDATES
        if cuda_enabled or not candidate["requires_cuda"]
    ]


def _counts(engines: list[dict[str, Any]], key: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for engine in engines:
        value = str(engine[key])
        counts[value] = counts.get(value, 0) + 1
    return dict(sorted(counts.items()))


def build_engine_catalog(
    *,
    cuda_enabled: bool = False,
    include_candidates: bool = False,
    managed_available: bool = False,
    native_available: bool = False,
) -> dict[str, Any]:
    """Return source-backed capabilities, optionally followed by build candidates."""
    _validate_bool(cuda_enabled, "cuda_enabled")
    _validate_bool(include_candidates, "include_candidates")
    _validate_bool(managed_available, "managed_available")
    _validate_bool(native_available, "native_available")
    eligible = _eligible(cuda_enabled)
    if not include_candidates:
        eligible = [spec for spec in eligible if spec.maturity == MATURITY_IMPLEMENTED]
    engines = [
        _materialize(
            spec,
            managed_available=managed_available,
            native_available=native_available,
        )
        for spec in eligible
    ]
    return {
        "schema_version": 1,
        "cuda_enabled": cuda_enabled,
        "include_candidates": include_candidates,
        "managed_runtime_available": managed_available,
        "native_runtime_available": native_available,
        "total_engines": len(engines),
        "implemented_count": sum(e["maturity"] == MATURITY_IMPLEMENTED for e in engines),
        "candidate_count": sum(e["maturity"] != MATURITY_IMPLEMENTED for e in engines),
        "families": _counts(engines, "family"),
        "backends": _counts(engines, "backend"),
        "maturity": _counts(engines, "maturity"),
        "parallelization_candidates": (
            [dict(candidate) for candidate in PARALLELIZATION_CANDIDATES]
            if include_candidates else []),
        "hybridization_candidates": (
            _hybridization_candidates(cuda_enabled) if include_candidates else []),
        "engines": engines,
        "truthfulness": (
            "Maturity=implemented means checked-in source and test evidence. Consult "
            "runtime_available separately; prototype/concept entries are proposals only."
        ),
    }


def _validate_recommendation_inputs(
    security_profile: str, optimization_pressure: float, fleet_size: int
) -> None:
    if not isinstance(security_profile, str):
        raise ValueError("security_profile must be a string")
    if security_profile not in SECURITY_PROFILES:
        raise ValueError(
            f"security_profile must be one of {', '.join(sorted(SECURITY_PROFILES))}")
    if (isinstance(optimization_pressure, bool)
            or not isinstance(optimization_pressure, (int, float))
            or not isfinite(float(optimization_pressure))):
        raise ValueError("optimization_pressure must be a finite number")
    if not 0.0 <= float(optimization_pressure) <= 1.0:
        raise ValueError("optimization_pressure must be between 0 and 1")
    if isinstance(fleet_size, bool) or not isinstance(fleet_size, int):
        raise ValueError("fleet_size must be an integer")
    if not 0 <= fleet_size <= 100_000:
        raise ValueError("fleet_size must be between 0 and 100000")


def recommend_engine_mix(
    *,
    cuda_enabled: bool,
    security_profile: str,
    optimization_pressure: float,
    fleet_size: int,
    include_candidates: bool = False,
    managed_available: bool = False,
    native_available: bool = False,
) -> dict[str, Any]:
    """Recommend implemented capabilities and, separately, build candidates.

    Concepts never cross into ``selected_engines``.  This keeps an advisory answer from
    becoming a false claim that a named engine is available in the current runtime.
    """
    _validate_bool(cuda_enabled, "cuda_enabled")
    _validate_bool(include_candidates, "include_candidates")
    _validate_bool(managed_available, "managed_available")
    _validate_bool(native_available, "native_available")
    if not isinstance(security_profile, str):
        raise ValueError("security_profile must be a string")
    security_profile = security_profile.strip().lower()
    _validate_recommendation_inputs(security_profile, optimization_pressure, fleet_size)
    eligible = _eligible(cuda_enabled)
    implemented = [spec for spec in eligible if spec.maturity == MATURITY_IMPLEMENTED]
    candidates = [spec for spec in eligible if spec.maturity != MATURITY_IMPLEMENTED]

    available_implemented = [
        spec for spec in implemented
        if _runtime_available(
            spec,
            managed_available=managed_available,
            native_available=native_available,
        )
    ]
    implemented_by_name = {spec.name: spec for spec in available_implemented}
    selected_names = ["routing-policy", "provider-outcome-analytics"]
    if security_profile in {"hardened", "paranoid"}:
        selected_names.append("drift-detector")
    if optimization_pressure >= 0.25 or fleet_size >= 36:
        selected_names.append("online-sgd-router")
    if security_profile == "performance" or optimization_pressure >= 0.6:
        selected_names.extend(("cosine-dedup-kernel", "utf8-token-estimator"))
    selected = {
        name: implemented_by_name[name]
        for name in selected_names
        if name in implemented_by_name
    }

    preferred_families = (
        "routing", "governance", "analytics", "retrieval", "compression", "security")
    missing_families = [
        family for family in preferred_families
        if not any(spec.family == family for spec in implemented)
    ]

    proposed: dict[str, EngineSpec] = {}
    if include_candidates:
        # Fill implementation-family gaps first; these are the highest-leverage proposals.
        for family in missing_families:
            match = next((spec for spec in candidates if spec.family == family), None)
            if match is not None:
                proposed[match.name] = match

        if optimization_pressure >= 0.7:
            for name in ("chaos-engine", "natural-selection-engine", "bayesian-optimizer"):
                match = next((spec for spec in candidates if spec.name == name), None)
                if match is not None:
                    proposed[match.name] = match
        if security_profile in {"hardened", "paranoid"}:
            for spec in candidates:
                if spec.family in {"security", "governance"}:
                    proposed[spec.name] = spec
        if fleet_size >= 36:
            for name in ("mesh-consensus-engine", "multi-armed-bandit-swarm", "gnaa-graph-attention"):
                match = next((spec for spec in candidates if spec.name == name), None)
                if match is not None:
                    proposed[match.name] = match

    memory_profile: dict[str, int] = {}
    for spec in selected.values():
        memory_profile[spec.memory_class] = memory_profile.get(spec.memory_class, 0) + 1

    rationale = [
        "Selections are limited to checked-in implementations available in the supplied "
        "managed/native runtime snapshot; CUDA capability remains caller-declared.",
        "Candidates are proposals only and are never invoked by this recommendation.",
    ]
    if include_candidates:
        rationale.extend((
            f"Fleet size {fleet_size} "
            f"{'enables' if fleet_size >= 36 else 'does not enable'} "
            "mesh-scale candidate suggestions.",
            f"Optimization pressure {float(optimization_pressure):.2f} "
            f"{'enables' if optimization_pressure >= 0.7 else 'does not enable'} "
            "exploratory candidate suggestions.",
        ))

    return {
        "schema_version": 1,
        "inputs": {
            "cuda_enabled": cuda_enabled,
            "security_profile": security_profile,
            "optimization_pressure": float(optimization_pressure),
            "fleet_size": fleet_size,
            "include_candidates": include_candidates,
            "managed_runtime_available": managed_available,
            "native_runtime_available": native_available,
        },
        "selected_count": len(selected),
        "selected_engines": [
            _materialize(
                spec,
                managed_available=managed_available,
                native_available=native_available,
            )
            for spec in selected.values()
        ],
        "candidate_count": len(proposed),
        "candidate_engines": [
            _materialize(
                spec,
                managed_available=managed_available,
                native_available=native_available,
            )
            for spec in proposed.values()
        ],
        "missing_implemented_families": missing_families,
        "selected_memory_profile": dict(sorted(memory_profile.items())),
        "parallelization_candidates": (
            [dict(candidate) for candidate in PARALLELIZATION_CANDIDATES]
            if include_candidates else []),
        "hybridization_candidates": (
            _hybridization_candidates(cuda_enabled) if include_candidates else []),
        "rationale": rationale,
    }
