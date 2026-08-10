"""Python analysis spoke for the HELIOS AIHub.

Hub-and-spoke rule: this package never calls providers, other spokes, or the
network. The C# orchestrator invokes it as a subprocess (``python3 -m
helios_agents``) with one JSON request on stdin and one JSON response on stdout.
"""

__all__ = ["analysis", "textwork"]
