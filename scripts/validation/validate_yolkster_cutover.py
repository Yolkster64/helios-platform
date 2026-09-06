#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOPOLOGY = ROOT / "config/migration/yolkster-control/topology.v1.json"
UI_CONTRACT = ROOT / "config/ui/winui3-only.v1.json"
LEDGER = ROOT / "docs/migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md"


def load(path: pathlib.Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain an object")
    return value


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    topology = load(TOPOLOGY)
    ui = load(UI_CONTRACT)

    current = topology["currentAuthority"]
    target = topology["targetAuthority"]
    if current["repository"] != "Yolkster64/helios-platform":
        fail("current authority must match the live Yolkster64 repository during rename staging")
    if target["coreRepository"] != "Yolkster64/helios-control":
        fail("target core repository mismatch")
    if target["guiRepository"] != "Yolkster64/helios-gui":
        fail("target GUI repository mismatch")
    if topology["deployment"]["applyDefault"] is not False:
        fail("applyDefault must remain false")
    if topology["deployment"]["productionEnabled"] is not False:
        fail("production must remain disabled")

    required = ui["required"]
    if required["useWinUI"] is not True:
        fail("WinUI must be required")
    if required["xamlNamespace"] != "Microsoft.UI.Xaml":
        fail("Microsoft.UI.Xaml must be the active XAML namespace")
    if len(ui.get("temporaryLegacyBaseline", [])) != 1:
        fail("legacy WPF baseline must stay singular and explicit")
    if ui["temporaryLegacyBaseline"][0]["path"] != "HELIOS.Platform.csproj":
        fail("unexpected WPF baseline path")

    active_root = ROOT / ui["activeUiRoot"]
    if not active_root.is_dir():
        fail(f"active WinUI root does not exist: {active_root.relative_to(ROOT)}")

    project_files = list(active_root.rglob("*.csproj"))
    if not project_files:
        fail("active WinUI root contains no C# project")
    if not any("<UseWinUI>true</UseWinUI>" in path.read_text(encoding="utf-8", errors="ignore") for path in project_files):
        fail("active GUI projects must declare <UseWinUI>true</UseWinUI>")

    forbidden = tuple(ui["forbiddenInActiveCode"])
    for path in active_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".cs", ".xaml", ".csproj", ".props", ".targets", ".ps1"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for token in forbidden:
            if token in text:
                fail(f"forbidden active UI token {token!r} in {path.relative_to(ROOT)}")

    tfms: list[str] = []
    for project in project_files:
        text = project.read_text(encoding="utf-8", errors="ignore")
        tfms.extend(re.findall(r"<TargetFramework>([^<]+)</TargetFramework>", text))
    baseline = ui.get("temporaryTargetFrameworkBaseline", {})
    if required["targetFramework"] not in tfms and baseline.get("current") not in tfms:
        fail(f"active GUI target framework is neither final target nor declared baseline: {tfms}")

    ledger_text = LEDGER.read_text(encoding="utf-8")
    ids = re.findall(r"^\| (HC-\d{3}) \|", ledger_text, flags=re.MULTILINE)
    ordered_unique = list(dict.fromkeys(ids))
    expected = [f"HC-{number:03d}" for number in range(1, 29)]
    if ordered_unique != expected:
        fail(f"canonical issue IDs must be HC-001..HC-028 in order; got {ordered_unique}")

    print(json.dumps({
        "status": "passed",
        "currentRepository": current["repository"],
        "targetRepository": target["coreRepository"],
        "targetGuiRepository": target["guiRepository"],
        "activeWinUiProjects": [str(path.relative_to(ROOT)) for path in project_files],
        "activeTargetFrameworks": tfms,
        "targetFrameworkMigrationIssue": baseline.get("issue"),
        "canonicalIssues": len(ordered_unique),
        "productionEnabled": topology["deployment"]["productionEnabled"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, ValueError, OSError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
