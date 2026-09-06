#!/usr/bin/env python3
"""Repository evidence only; never infers deployment or live service health."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path

REQUIRED_FILES = (
    'AGENTS.md', 'HELIOS.sln', 'config/aihub.json', 'config/connectors.json',
    'docs/CONSOLIDATION_BLUEPRINT.md', 'src/mcp/HELIOS.Mcp/HELIOS.Mcp.csproj',
    'scripts/setup/setup-all.ps1', 'scripts/bootstrap/setup-everything.ps1',
    '.mcp.json', '.codex/config.toml', '.vscode/mcp.json',
)
EXPECTED_JOBS = ('health-check', 'verification-contract')


def inventory(root):
    issues = []
    for name in REQUIRED_FILES:
        path = root / name
        if not path.is_file() or not path.stat().st_size:
            issues.append(f'{name}: missing or empty')
        elif path.suffix == '.json':
            try:
                data = json.loads(path.read_text(encoding='utf-8'))
                if not isinstance(data, dict):
                    issues.append(f'{name}: expected a JSON object')
            except (OSError, ValueError):
                issues.append(f'{name}: unreadable or invalid JSON')
    return {'scope': 'repository-files', 'ready': not issues,
            'filesChecked': len(REQUIRED_FILES), 'issues': issues}


def summarize(needs):
    # Explicit names ensure an empty, partial or unfamiliar report cannot go green.
    signals = {}
    for name in EXPECTED_JOBS:
        entry = needs.get(name) if isinstance(needs, dict) else None
        result = entry.get('result') if isinstance(entry, dict) else None
        signals[name] = result if result in ('success', 'failure', 'cancelled', 'skipped') else 'unknown'
    return {'schemaVersion': 1, 'generatedUtc': datetime.now(timezone.utc).isoformat(),
            'scope': 'repository-verification', 'signals': signals,
            'repositoryChecksPassed': all(value == 'success' for value in signals.values()),
            'runtimeVerified': False, 'deploymentVerified': False,
            'providersVerified': False, 'connectorDeliveryVerified': False}


def render(report):
    state = 'PASSED' if report['repositoryChecksPassed'] else 'INCOMPLETE OR FAILED'
    lines = ['# HELIOS repository verification', '',
             f"Generated: {report['generatedUtc']}", '',
             f'Repository checks: **{state}**', '', '| Check | Result |', '|---|---|']
    lines.extend(f'| {name} | {result} |' for name, result in report['signals'].items())
    lines += ['', 'Scope: source-file presence, JSON shape, and offline verification contracts.',
              'This run does not build the platform or verify deployed agents, Azure, providers,',
              'Slack/Linear delivery, SharePoint, or a user workstation.',
              'The .NET Build & Test workflow separately builds and tests the portable solution',
              'and probes MCP stdio discovery. Authenticated assistant sessions remain a separate check.', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', action='store_true')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--out-dir', type=Path, default=Path('health-report'))
    args = parser.parse_args()
    if args.inventory:
        report = inventory(args.root)
        print(json.dumps(report))
        return 0 if report['ready'] else 1
    try:
        needs = json.loads(os.environ.get('HELIOS_JOB_RESULTS', '{}'))
    except ValueError:
        needs = {}
    report = summarize(needs)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / 'health-report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    (args.out_dir / 'health-report.md').write_text(render(report), encoding='utf-8')
    print(render(report))
    # Emit evidence even when the checks failed. The workflow gates after upload.
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
