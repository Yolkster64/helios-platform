import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_SOURCE = REPO_ROOT / ".devcontainer" / "init-db.sh"


class InitDbTests(unittest.TestCase):
    def _make_psql_stub(self, bin_dir: Path, args_file: Path, stdin_file: Path) -> None:
        script = bin_dir / "psql"
        script.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\n' \"$@\" > \"$HELIOS_TEST_PSQL_ARGS\"\n"
            "cat > \"$HELIOS_TEST_PSQL_STDIN\"\n",
            encoding="utf-8",
        )
        script.chmod(script.stat().st_mode | stat.S_IXUSR)

    def test_init_db_uses_strict_psql_options_and_parameterized_env(self) -> None:
        temp_root = Path(tempfile.mkdtemp(prefix="helios-init-db-"))
        bin_dir = temp_root / "bin"
        bin_dir.mkdir()
        args_file = temp_root / "args.txt"
        stdin_file = temp_root / "stdin.sql"
        self._make_psql_stub(bin_dir, args_file, stdin_file)

        script = temp_root / "init-db.sh"
        script.write_text(SCRIPT_SOURCE.read_text(encoding="utf-8"), encoding="utf-8")
        script.chmod(script.stat().st_mode | stat.S_IXUSR)

        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env['PATH']}"
        env["POSTGRES_DB"] = "custom_db"
        env["POSTGRES_USER"] = "custom_user"
        env["HELIOS_TEST_PSQL_ARGS"] = str(args_file)
        env["HELIOS_TEST_PSQL_STDIN"] = str(stdin_file)

        completed = subprocess.run(
            ["bash", str(script)],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr or completed.stdout)

        args = args_file.read_text(encoding="utf-8")
        sql = stdin_file.read_text(encoding="utf-8")
        self.assertIn("-v", args)
        self.assertIn("ON_ERROR_STOP=1", args)
        self.assertIn("--username", args)
        self.assertIn("custom_user", args)
        self.assertIn("--dbname", args)
        self.assertIn("custom_db", args)
        self.assertIn("BEGIN;", sql)
        self.assertIn("COMMIT;", sql)
        self.assertNotIn("GRANT ALL PRIVILEGES ON DATABASE helios_dev TO devuser", sql)

    def test_init_db_requires_postgres_env(self) -> None:
        temp_root = Path(tempfile.mkdtemp(prefix="helios-init-db-env-"))
        script = temp_root / "init-db.sh"
        script.write_text(SCRIPT_SOURCE.read_text(encoding="utf-8"), encoding="utf-8")
        script.chmod(script.stat().st_mode | stat.S_IXUSR)

        completed = subprocess.run(
            ["bash", str(script)],
            env={"PATH": os.environ["PATH"]},
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("POSTGRES_DB must be set", completed.stderr)


if __name__ == "__main__":
    unittest.main()
