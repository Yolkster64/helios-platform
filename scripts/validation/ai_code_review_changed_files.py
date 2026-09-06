#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def _git(repo: pathlib.Path, *args: str) -> list[str]:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line for line in completed.stdout.splitlines() if line]


def _has_head_parent(repo: pathlib.Path) -> bool:
    completed = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--verify", "HEAD^"],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode == 0:
        return True
    if completed.returncode == 128:
        return False
    raise subprocess.CalledProcessError(
        completed.returncode,
        completed.args,
        output=completed.stdout,
        stderr=completed.stderr,
    )


def changed_files(repo: pathlib.Path, event_name: str, event_path: pathlib.Path | None) -> list[str]:
    if event_name == "pull_request":
        if event_path is None:
            raise ValueError("pull_request changed-file extraction requires GITHUB_EVENT_PATH")
        event = json.loads(event_path.read_text(encoding="utf-8"))
        pull_request = event.get("pull_request") or {}
        base = ((pull_request.get("base") or {}).get("sha") or "").strip()
        head = ((pull_request.get("head") or {}).get("sha") or "").strip()
        if not base or not head:
            raise ValueError("pull_request event payload must include pull_request.base.sha and pull_request.head.sha")
        return _git(repo, "diff", "--name-only", f"{base}...{head}")

    if event_name == "workflow_dispatch":
        if _has_head_parent(repo):
            return _git(repo, "diff", "--name-only", "HEAD^", "HEAD")
        return _git(repo, "show", "--pretty=", "--name-only", "HEAD")

    raise ValueError(f"unsupported event for AI code review changed-file extraction: {event_name}")


def main() -> int:
    repo = pathlib.Path(os.environ.get("GITHUB_WORKSPACE", str(ROOT)))
    event_name = os.environ.get("GITHUB_EVENT_NAME", "").strip()
    event_path_value = os.environ.get("GITHUB_EVENT_PATH", "").strip()
    if not event_name:
        raise ValueError("GITHUB_EVENT_NAME is required")

    event_path = pathlib.Path(event_path_value) if event_path_value else None
    files = changed_files(repo, event_name, event_path)

    print("Changed files:")
    for path in files:
        print(f"  - {path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        if isinstance(exc, subprocess.CalledProcessError):
            if exc.stdout:
                print(exc.stdout, end="", file=sys.stdout)
            if exc.stderr:
                print(exc.stderr, end="", file=sys.stderr)
            raise SystemExit(exc.returncode)
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
