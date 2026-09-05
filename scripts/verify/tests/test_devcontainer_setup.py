"""Check bootstrap failure propagation without installing or building anything."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[3]


class DevcontainerSetupTests(unittest.TestCase):
    def run_setup(self, failure=""):
        with tempfile.TemporaryDirectory(prefix="helios-container-") as directory:
            root = Path(directory)
            script = root / ".devcontainer/post-create.sh"
            script.parent.mkdir()
            shutil.copyfile(REPO / ".devcontainer/post-create.sh", script)
            cli = root / "src/ai/HELIOS.AIHub.Cli"
            cli.mkdir(parents=True)
            (cli / "HELIOS.AIHub.Cli.csproj").write_text(
                "<Project><PropertyGroup><TargetFramework>net12.0</TargetFramework>"
                "</PropertyGroup></Project>"
            )
            binary = cli / "bin/Release/net12.0/helios-ai"
            binary.parent.mkdir(parents=True)
            binary.write_text("#!/bin/sh\nexit 0\n")
            binary.chmod(0o755)
            native = root / "scripts/build/build-native.sh"
            native.parent.mkdir(parents=True)
            native.write_text('test "$FAIL_STEP" != native\n')
            bindir = root / "bin"
            bindir.mkdir()
            commands = {
                "cmake": "exit 0\n",
                "g++": "exit 0\n",
                "dotnet": 'echo "dotnet $1" >> "$CALLS"\ntest "$FAIL_STEP" != "$1"\n',
                "python3": 'if [ "$1" = -m ]; then echo pip >> "$CALLS"; exit 0; fi\nexec "$REAL_PYTHON" "$@"\n',
                "sudo": 'echo "$*" >> "$CALLS"\n',
            }
            for name, body in commands.items():
                path = bindir / name
                path.write_text("#!/bin/sh\n" + body)
                path.chmod(0o755)
            calls = root / "calls.txt"
            env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"],
                       FAIL_STEP=failure, CALLS=str(calls), REAL_PYTHON=sys.executable)
            result = subprocess.run(["bash", str(script)], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=10)
            return result, calls.read_text() if calls.exists() else ""

    def test_restore_failure_stops_before_build_and_link(self):
        result, calls = self.run_setup("restore")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "dotnet restore\n")

    def test_build_failure_stops_before_python_and_link(self):
        result, calls = self.run_setup("build")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "dotnet restore\ndotnet build\n")

    def test_native_build_failure_is_visible(self):
        result, calls = self.run_setup("native")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_success_derives_framework_from_project(self):
        result, calls = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("bin/Release/net12.0/helios-ai /usr/local/bin/helios-ai", calls)


if __name__ == "__main__":
    unittest.main()
