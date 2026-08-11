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
    parser.add_argument("--native-smoke", required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-md", required=True)
    args = parser.parse_args()

    total, passed, failed = parse_trx(Path(args.trx))
    healthy = args.build == "success" and args.tests == "success" and failed == 0

    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "lane": "minimal-platform",
        "solution": "HELIOS.sln",
        "signals": {
            "build": args.build,
            "tests": args.tests,
            "native_smoke": args.native_smoke,
            "cli_smoke": args.cli_smoke,
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
