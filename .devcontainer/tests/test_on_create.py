import os
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_SOURCE = REPO_ROOT / ".devcontainer" / "onCreateCommand.sh"


def make_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class OnCreateCommandTests(unittest.TestCase):
    def _workspace(self, native_exit_code: int = 0) -> Path:
        workspace = Path(tempfile.mkdtemp(prefix="helios-devcontainer-"))
        (workspace / ".devcontainer").mkdir()
        (workspace / "scripts" / "build").mkdir(parents=True)
        (workspace / "src" / "ai" / "python" / "helios_agents").mkdir(parents=True)
        (workspace / "HELIOS.sln").write_text("", encoding="utf-8")
        (workspace / ".devcontainer" / "onCreateCommand.sh").write_text(
            SCRIPT_SOURCE.read_text(encoding="utf-8"), encoding="utf-8"
        )
        (workspace / "scripts" / "build" / "build-native.sh").write_text(
            f"#!/usr/bin/env bash\nexit {native_exit_code}\n", encoding="utf-8"
        )
        (workspace / "scripts" / "build" / "build-native.sh").chmod(0o755)
        (workspace / "scripts" / "build" / "verify-readiness.ps1").write_text(
            "Write-Output 'ready'\n", encoding="utf-8"
        )
        (workspace / "src" / "ai" / "python" / "pyproject.toml").write_text(
            textwrap.dedent(
                """
                [build-system]
                requires = ["setuptools>=68"]
                build-backend = "setuptools.build_meta"

                [project]
                name = "fixture-helios-agents"
                version = "0.0.1"
                dependencies = []

                [project.optional-dependencies]
                dev = []

                [tool.setuptools.packages.find]
                include = ["helios_agents*"]
                """
            ).strip()
            + "\n",
            encoding="utf-8",
        )
        (workspace / "src" / "ai" / "python" / "helios_agents" / "__init__.py").write_text(
            "__all__ = []\n", encoding="utf-8"
        )
        return workspace

    def _tool_bin(self, root: Path, dotnet_build_exit_code: int = 0, readiness_exit_code: int = 0) -> Path:
        bin_dir = root / "bin"
        bin_dir.mkdir()
        make_executable(
            bin_dir / "dotnet",
            "#!/usr/bin/env bash\n"
            "echo \"$@\" >> \"$HELIOS_TEST_TOOL_LOG\"\n"
            "if [[ \"$1\" == \"--version\" ]]; then echo 8.0.999; fi\n",
        )
        if dotnet_build_exit_code:
            make_executable(
                bin_dir / "dotnet",
                "#!/usr/bin/env bash\n"
                "echo \"$@\" >> \"$HELIOS_TEST_TOOL_LOG\"\n"
                "if [[ \"$1\" == \"--version\" ]]; then echo 8.0.999; exit 0; fi\n"
                f"if [[ \"$1\" == \"build\" ]]; then exit {dotnet_build_exit_code}; fi\n",
            )
        make_executable(
            bin_dir / "pwsh",
            "#!/usr/bin/env bash\n"
            "echo \"pwsh $@\" >> \"$HELIOS_TEST_TOOL_LOG\"\n"
            "if [[ \"$1\" == \"--version\" ]]; then echo 'PowerShell 7.9.0'; exit 0; fi\n"
            f"if [[ \"$*\" == *'scripts/build/verify-readiness.ps1'* ]]; then exit {readiness_exit_code}; fi\n",
        )
        return bin_dir

    def test_setup_is_idempotent_and_non_destructive(self) -> None:
        workspace = self._workspace()
        preserved = {
            ".env": "KEEP_ENV=1\n",
            ".npmrc": "legacy-peer-deps=false\n",
            "scripts/setup.sh": "#!/usr/bin/env bash\necho keep\n",
        }
        for relative, content in preserved.items():
            path = workspace / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")

        invalid_venv = workspace / "src" / "ai" / "python" / ".venv"
        invalid_venv.mkdir()

        log_file = workspace / "tool.log"
        bin_dir = self._tool_bin(workspace)
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env['PATH']}"
        env["HELIOS_TEST_TOOL_LOG"] = str(log_file)

        script = workspace / ".devcontainer" / "onCreateCommand.sh"
        for _ in range(2):
            completed = subprocess.run(
                ["bash", str(script)],
                cwd=workspace,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr or completed.stdout)

        self.assertTrue((workspace / "src" / "ai" / "python" / ".venv" / "pyvenv.cfg").is_file())
        self.assertTrue((workspace / "src" / "ai" / "python" / ".venv" / "bin" / "python").is_file())
        for relative, content in preserved.items():
            self.assertEqual((workspace / relative).read_text(encoding="utf-8"), content)

        tool_log = log_file.read_text(encoding="utf-8")
        self.assertIn("build HELIOS.sln -c Release", tool_log)
        self.assertIn("pwsh -NoLogo -NoProfile -File scripts/build/verify-readiness.ps1", tool_log)

    def test_optional_native_build_failure_is_non_fatal(self) -> None:
        workspace = self._workspace(native_exit_code=1)
        log_file = workspace / "tool.log"
        bin_dir = self._tool_bin(workspace)
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env['PATH']}"
        env["HELIOS_TEST_TOOL_LOG"] = str(log_file)

        completed = subprocess.run(
            ["bash", str(workspace / ".devcontainer" / "onCreateCommand.sh")],
            cwd=workspace,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr or completed.stdout)
        self.assertIn("Native spoke build failed", completed.stdout)

    def test_required_dotnet_build_failure_is_fatal(self) -> None:
        workspace = self._workspace()
        log_file = workspace / "tool.log"
        bin_dir = self._tool_bin(workspace, dotnet_build_exit_code=7)
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env['PATH']}"
        env["HELIOS_TEST_TOOL_LOG"] = str(log_file)

        completed = subprocess.run(
            ["bash", str(workspace / ".devcontainer" / "onCreateCommand.sh")],
            cwd=workspace,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 7)

    def test_required_readiness_failure_is_fatal(self) -> None:
        workspace = self._workspace()
        log_file = workspace / "tool.log"
        bin_dir = self._tool_bin(workspace, readiness_exit_code=9)
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env['PATH']}"
        env["HELIOS_TEST_TOOL_LOG"] = str(log_file)

        completed = subprocess.run(
            ["bash", str(workspace / ".devcontainer" / "onCreateCommand.sh")],
            cwd=workspace,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 9)


if __name__ == "__main__":
    unittest.main()
