"""Python analysis and engine-advisory spoke for the HELIOS AIHub.

Hub-and-spoke rule: this package never calls providers, other spokes, or the
network. The C# orchestrator invokes it as a subprocess (``python3 -m
helios_agents``) with one JSON request on stdin and one JSON response on stdout.

The submodules are exported lazily (PEP 562): ``analysis`` imports NumPy when the
``ml`` extra is installed, and the fleet starts many worker processes
(``python -m helios_agents.fleet_worker``) that never touch analytics, so
importing the package must not pay that startup cost or fail on a broken
optional dependency. ``from helios_agents import analysis`` still works — the
import machinery loads the submodule on first use.
"""

from __future__ import annotations

import importlib
from typing import TYPE_CHECKING

if TYPE_CHECKING:  # static analysers see the real modules; runtime stays lazy
    from . import analysis, engines, fleet_learning, textwork

__all__ = ["analysis", "engines", "fleet_learning", "textwork"]


def __getattr__(name: str) -> object:
    if name in __all__:
        return importlib.import_module(f".{name}", __name__)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def __dir__() -> list[str]:
    return sorted(set(globals()) | set(__all__))
