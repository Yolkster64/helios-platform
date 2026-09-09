"""Exercise the plugin-to-checkout process boundary without credentials or .NET."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PLUGIN = Path(__file__).resolve().parents[1]


class PluginLaunchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="helios plugin test ")
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.cache = base / "installed plugin cache" / "helios-connect"
        (self.cache / "scripts").mkdir(parents=True)
        shutil.copy2(PLUGIN / "scripts/mcp_stdio.py", self.cache / "scripts/mcp_stdio.py")
        self.root = base / "trusted checkout with spaces"
        for filename in ("AGENTS.md", "config/control-project.json", "src/mcp/HELIOS.Mcp/HELIOS.Mcp.csproj"):
            target = self.root / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("test fixture", encoding="utf-8")
        self.launcher = self.root / "scripts/bootstrap/connect.py"
        self.launcher.parent.mkdir(parents=True)
        self.launcher.write_text(
            "import json, os, sys\n"
            "print(json.dumps({'argv': sys.argv[1:], 'cwd': os.getcwd(), 'root': os.environ['HELIOS_REPO_ROOT']}))\n",
            encoding="utf-8",
        )

    def launch(self, root: str | None, *args: str) -> subprocess.CompletedProcess[str]:
        env = {key: value for key, value in os.environ.items() if key in {"PATH", "SYSTEMROOT", "WINDIR", "TMP", "TEMP"}}
        if root is not None:
            env["HELIOS_REPO_ROOT"] = root
        return subprocess.run(
            [sys.executable, "scripts/mcp_stdio.py", *args],
            cwd=self.cache, env=env, capture_output=True, text=True, timeout=10,
        )

    def assert_refused(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertTrue(result.stderr.strip())

    def test_missing_root_requires_explicit_selection(self) -> None:
        self.assert_refused(self.launch(None))

    def test_relative_root_is_not_inferred_from_plugin_cache(self) -> None:
        self.assert_refused(self.launch("../trusted checkout with spaces"))

    def test_incomplete_checkout_does_not_execute_launcher(self) -> None:
        (self.root / "config/control-project.json").unlink()
        self.assert_refused(self.launch(str(self.root)))

    def test_extra_arguments_cannot_change_the_launcher_action(self) -> None:
        self.assert_refused(self.launch(str(self.root), "deploy"))

    def test_installed_cache_delegates_to_absolute_checkout_and_keeps_stdout_clean(self) -> None:
        result = self.launch(str(self.root))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(json.loads(result.stdout), {
            "argv": ["mcp"], "cwd": str(self.root.resolve()), "root": str(self.root.resolve()),
        })
        self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_launch_failure_is_propagated_to_the_client(self) -> None:
        self.launcher.write_text("raise SystemExit(17)\n", encoding="utf-8")
        result = self.launch(str(self.root))
        self.assertEqual(result.returncode, 17)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
