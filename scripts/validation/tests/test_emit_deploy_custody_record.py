from __future__ import annotations

import argparse
import json
import pathlib
import tempfile
import unittest

from scripts.validation import emit_deploy_custody_record as target


class EmitDeployCustodyRecordTests(unittest.TestCase):
    def _args(
        self,
        temp_dir: pathlib.Path,
        *,
        phase: str,
        stdout_text: str = "",
        stderr_text: str = "",
        exit_code: int = 0,
    ) -> argparse.Namespace:
        stdout_file = temp_dir / "stdout.txt"
        stderr_file = temp_dir / "stderr.txt"
        record_file = temp_dir / "record.json"
        stdout_file.write_text(stdout_text, encoding="utf-8")
        stderr_file.write_text(stderr_text, encoding="utf-8")
        return argparse.Namespace(
            phase=phase,
            deployment_name="helios-123-1",
            timestamp="2026-09-06T00:00:00Z",
            exit_code=exit_code,
            stdout_file=stdout_file,
            stderr_file=stderr_file,
            record_file=record_file,
        )

    def test_what_if_counts_allowlisted_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            args = self._args(
                pathlib.Path(temp),
                phase="what-if",
                stdout_text=json.dumps(
                    {
                        "properties": {
                            "changes": [
                                {"changeType": "Create"},
                                {"changeType": "Modify"},
                                {"changeType": "Modify"},
                                {"changeType": "Delete"},
                            ]
                        }
                    }
                ),
                stderr_text="noise\nERROR: safe diagnostic\nsecret=should-not-appear\n",
            )

            record = target.build_record(args)

        self.assertEqual({"create": 1, "modify": 2, "delete": 1}, record["summary"])
        self.assertEqual(["ERROR: safe diagnostic"], record["diagnostics"])
        self.assertEqual("json", record["stdoutStatus"])

    def test_deploy_result_filters_to_allowlisted_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            args = self._args(
                pathlib.Path(temp),
                phase="deploy",
                stdout_text=json.dumps(
                    {
                        "name": "deploy-1",
                        "id": "/subscriptions/123",
                        "resourceGroup": "rg-helios-ai",
                        "provisioningState": "Succeeded",
                        "timestamp": "2026-09-06T00:00:00Z",
                        "secret": "should-not-be-kept",
                    }
                ),
            )

            record = target.build_record(args)

        self.assertEqual(
            {
                "name": "deploy-1",
                "id": "/subscriptions/123",
                "resourceGroup": "rg-helios-ai",
                "provisioningState": "Succeeded",
                "timestamp": "2026-09-06T00:00:00Z",
            },
            record["result"],
        )
        self.assertEqual("json", record["stdoutStatus"])

    def test_invalid_json_does_not_break_failure_record(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            args = self._args(
                pathlib.Path(temp),
                phase="deploy",
                stdout_text="{not json",
                stderr_text="ERROR: deployment failed\nAccount key=keep-out\n",
                exit_code=3,
            )

            record = target.build_record(args)

        self.assertEqual(3, record["exitCode"])
        self.assertEqual({}, record["result"])
        self.assertEqual("invalid-json", record["stdoutStatus"])
        self.assertEqual(["ERROR: deployment failed"], record["diagnostics"])


if __name__ == "__main__":
    unittest.main()
