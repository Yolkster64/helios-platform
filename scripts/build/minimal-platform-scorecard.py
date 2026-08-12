#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
import xml.etree.ElementTree as ET


def parse_trx(path: Path) -> tuple[int, int, int]:
    if not path.exists():
        return 0, 0, 0

    root = ET.parse(path).getroot()
    counters = root.find(".//{*}ResultSummary/{*}Counters")
    if counters is None:
        return 0, 0, 0

    total = int(counters.attrib.get("total", "0"))
    passed = int(counters.attrib.get("passed", "0"))
    failed = int(counters.attrib.get("failed", "0")) + int(counters.attrib.get("error", "0"))
    return total, passed, failed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trx", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--tests", required=True)
    parser.add_argument("--cli-smoke", required=True)
    parser.add_argument("--publish", required=True)
    parser.add_argument("--artifact-smoke", required=True)
    parser.add_argument("--upload-test-results", required=True)
    parser.add_argument("--upload-cli", required=True)
    parser.add_argument("--native-smoke", required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-md", required=True)
    args = parser.parse_args()

    total, passed, failed = parse_trx(Path(args.trx))
    # healthy must reflect every signal the scorecard reports: a failed
    # smoke step with if:always() generation would otherwise publish
    # healthy=true against a red job.
    healthy = (
        all(
            outcome == "success"
            for outcome in (
                args.build,
                args.tests,
                args.native_smoke,
                args.cli_smoke,
                args.publish,
                args.artifact_smoke,
                args.upload_test_results,
                args.upload_cli,
            )
        )
        and failed == 0
        # Health requires positive PASSED evidence: a missing/counterless TRX,
        # an empty discovery, or a TRX of only skipped/notExecuted entries must
        # not publish a healthy artifact (failed==0 with passed==0 is not
        # proof of anything).
        and passed > 0
    )

    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "lane": "minimal-platform",
        "solution": "HELIOS.sln",
        "signals": {
            "build": args.build,
            "tests": args.tests,
            "native_smoke": args.native_smoke,
            "cli_smoke": args.cli_smoke,
            "publish": args.publish,
            "artifact_smoke": args.artifact_smoke,
            "upload_test_results": args.upload_test_results,
            "upload_cli": args.upload_cli,
        },
        "metrics": {
            "tests_total": total,
            "tests_passed": passed,
            "tests_failed": failed,
            "healthy": healthy,
        },
    }

    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    summary = "\n".join(
        [
            "## Minimal platform scorecard",
            "",
            f"- Lane: `{payload['lane']}`",
            f"- Build: `{args.build}`",
            f"- Tests: `{args.tests}`",
            f"- Native smoke: `{args.native_smoke}`",
            f"- CLI smoke: `{args.cli_smoke}`",
            f"- Publish: `{args.publish}`",
            f"- Artifact smoke: `{args.artifact_smoke}`",
            f"- Test-results upload: `{args.upload_test_results}`",
            f"- CLI artifact upload: `{args.upload_cli}`",
            f"- Tests total/passed/failed: `{total}/{passed}/{failed}`",
            f"- Healthy signal: `{'yes' if healthy else 'no'}`",
        ]
    )

    out_md = Path(args.out_md)
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(summary + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
