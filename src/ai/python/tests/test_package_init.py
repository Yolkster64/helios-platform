"""The package initializer must stay cheap: no submodule (and no NumPy) loads until used."""

from __future__ import annotations

import json
import subprocess
import sys

import helios_agents


def _probe(code: str) -> dict[str, bool]:
    out = subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, check=True
    )
    return json.loads(out.stdout)


def test_importing_the_package_loads_no_submodule_and_no_numpy() -> None:
    loaded = _probe(
        "import json, sys; import helios_agents; "
        "print(json.dumps({'analysis': 'helios_agents.analysis' in sys.modules, "
        "'textwork': 'helios_agents.textwork' in sys.modules, 'numpy': 'numpy' in sys.modules}))"
    )
    assert loaded == {"analysis": False, "textwork": False, "numpy": False}


def test_the_fleet_worker_entry_loads_no_analytics() -> None:
    # The lane process the fleet starts once per worker is the cost that mattered: it
    # must come up without the analytics stack. (`python -m helios_agents` — the C#
    # orchestrator's JSON-over-stdio entry — imports all four modules on purpose; it is
    # the one process that serves analysis requests.)
    loaded = _probe(
        "import json, sys; import helios_agents.fleet_worker; "
        "print(json.dumps({'analysis': 'helios_agents.analysis' in sys.modules, "
        "'numpy': 'numpy' in sys.modules, 'sklearn': 'sklearn' in sys.modules}))"
    )
    assert loaded == {"analysis": False, "numpy": False, "sklearn": False}


def test_submodules_are_reachable_as_package_attributes_on_demand() -> None:
    loaded = _probe(
        "import json, sys; import helios_agents; m = helios_agents.engines; "
        "print(json.dumps({'engines': m.__name__ == 'helios_agents.engines', "
        "'analysis_still_lazy': 'helios_agents.analysis' not in sys.modules}))"
    )
    assert loaded == {"engines": True, "analysis_still_lazy": True}


def test_from_import_and_dir_still_expose_the_exports() -> None:
    from helios_agents import analysis  # noqa: F401 — the import machinery loads it on demand

    assert set(helios_agents.__all__) <= set(dir(helios_agents))
    try:
        helios_agents.no_such_module  # type: ignore[attr-defined]
    except AttributeError as exc:
        assert "no_such_module" in str(exc)
    else:  # pragma: no cover
        raise AssertionError("unknown attributes must raise AttributeError")
