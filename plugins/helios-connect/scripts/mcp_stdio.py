#!/usr/bin/env python3
"""Start the existing HELIOS MCP entrypoint from an installed plugin cache."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 1:
        print("HELIOS Connect does not accept command arguments.", file=sys.stderr)
        return 2
    selected = os.environ.get("HELIOS_REPO_ROOT", "")
    if not selected or not Path(selected).is_absolute():
        print("Set HELIOS_REPO_ROOT to the absolute trusted HELIOS checkout before starting Codex.", file=sys.stderr)
        return 2
    try:
        root = Path(selected).resolve(strict=True)
        required = (
            "AGENTS.md",
            "config/control-project.json",
            "scripts/bootstrap/connect.py",
            "src/mcp/HELIOS.Mcp/HELIOS.Mcp.csproj",
        )
        if not root.is_dir() or not all((root / path).is_file() for path in required):
            raise ValueError("Incomplete checkout")
        launcher = root / "scripts/bootstrap/connect.py"
        os.chdir(root)
        os.environ["HELIOS_REPO_ROOT"] = str(root)
        argv = [sys.executable, str(launcher), "mcp"]
        if os.name == "nt":
            # Windows execv neither quotes spaced paths reliably nor preserves
            # the child exit status. Keep stdio inherited for the MCP transport.
            return subprocess.run(argv, shell=False).returncode
        os.execv(sys.executable, argv)
    except (OSError, ValueError):
        print("HELIOS Connect could not start the selected checkout. Verify its files and Python installation.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
