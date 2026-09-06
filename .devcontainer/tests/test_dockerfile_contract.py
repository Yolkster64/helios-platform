import shutil
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(shutil.which("docker") is None, "docker is required for the devcontainer image contract test")
class DockerfileContractTests(unittest.TestCase):
    def test_built_image_contains_required_post_create_tools(self) -> None:
        tag = "helios-devcontainer-contract-test"
        build = subprocess.run(
            ["docker", "build", "-f", ".devcontainer/Dockerfile", "-t", tag, "."],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(build.returncode, 0, build.stderr or build.stdout)

        probe = subprocess.run(
            [
                "docker",
                "run",
                "--rm",
                tag,
                "bash",
                "-lc",
                "python3 --version && python3 -m venv --help >/dev/null && pwsh --version >/dev/null",
            ],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        try:
            self.assertEqual(probe.returncode, 0, probe.stderr or probe.stdout)
        finally:
            subprocess.run(
                ["docker", "image", "rm", "-f", tag],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )


if __name__ == "__main__":
    unittest.main()
