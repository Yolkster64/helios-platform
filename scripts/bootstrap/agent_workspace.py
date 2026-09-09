#!/usr/bin/env python3
"""Local, isolated agent worktrees for one HELIOS repository. Never starts an agent."""
from __future__ import annotations

import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid

PROJECT_URL = "https://linear.app/641974/project/helios-4f592efea071"
AGENTS = ("claude", "codex", "copilot", "hermes", "xcore", "chatgpt", "human")
NAME = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*\Z")
RESERVED = {"con", "prn", "aux", "nul", *(f"com{i}" for i in range(1, 10)),
            *(f"lpt{i}" for i in range(1, 10))}
MAX_REGISTRY_BYTES = 1024 * 1024


class WorkspaceError(Exception):
    pass


def plain_path(path: Path) -> Path:
    """Refuse symlinks/junctions before resolving or modifying a path."""
    path = Path(os.path.abspath(path))
    for item in reversed((path, *path.parents)):
        try:
            metadata = item.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, "st_file_attributes", 0) & 0x400:
            raise WorkspaceError("Linked paths and Windows junctions are not supported.")
    return path


def valid_name(name: str) -> bool:
    return len(name) <= 48 and NAME.fullmatch(name) is not None and name not in RESERVED


def path_key(path: str | Path) -> str:
    return os.path.normcase(os.path.abspath(path)).casefold()


class Git:
    def __init__(self):
        # Ambient Git directory/config overrides must not redirect this operation.
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("GIT_")}
        # Workspace preparation is local and unattended, including on partial
        # clones. Reapply these after removing ambient Git overrides. The empty
        # protocol allowlist also blocks lazy fetch on older Git versions.
        self.env.update({"GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": "",
                         "GCM_INTERACTIVE": "Never", "SSH_ASKPASS": "",
                         "GIT_NO_LAZY_FETCH": "1", "GIT_ALLOW_PROTOCOL": ""})
        self.options = ["-c", "core.hooksPath=" + os.devnull,
                        "-c", "core.fsmonitor=false", "-c", "branch.autoSetupMerge=false",
                        "-c", "core.askPass=", "-c", "credential.helper="]

    def run(self, repo: Path, *args: str, allow_missing: bool = False) -> str:
        try:
            result = subprocess.run(["git", *self.options, "-C", str(repo), *args],
                                    env=self.env, capture_output=True, text=True,
                                    stdin=subprocess.DEVNULL,
                                    encoding="utf-8", errors="strict", timeout=60,
                                    check=False)
        except (OSError, subprocess.TimeoutExpired, UnicodeError) as exc:
            raise WorkspaceError("Local Git operation could not complete.") from exc
        if result.returncode and not (allow_missing and result.returncode == 1):
            # Git errors may contain remote URLs or configured helper commands.
            raise WorkspaceError("Local Git operation failed; existing work was preserved.")
        return result.stdout

    def disable_filters(self, repo: Path) -> None:
        # Checkout filters can execute external programs. Disable every configured
        # driver, including LFS, so workspace creation performs local Git work only.
        keys = self.run(repo, "config", "--null", "--name-only", "--get-regexp",
                        r"^filter\..*\.", allow_missing=True).split("\0")
        drivers = {key[len("filter."):].rsplit(".", 1)[0] for key in keys if key}
        if len(drivers) > 100:
            raise WorkspaceError("Too many checkout filters to prepare a bounded workspace.")
        for driver in sorted(drivers):
            for setting, value in (("clean", ""), ("smudge", ""), ("process", ""), ("required", "false")):
                self.options.extend(["-c", f"filter.{driver}.{setting}={value}"])


def worktrees(git: Git, repo: Path) -> list[dict[str, str]]:
    rows, row = [], {}
    for field in git.run(repo, "worktree", "list", "--porcelain", "-z").split("\0"):
        if not field:
            if row:
                rows.append(row)
                row = {}
        else:
            key, _, value = field.partition(" ")
            row[key] = value
    if row:
        rows.append(row)
    return rows


def load_registry(path: Path) -> dict:
    plain_path(path)
    if not path.exists():
        return {"version": 1, "registryId": None, "workspaces": {}}
    try:
        with path.open("rb") as source:
            data = source.read(MAX_REGISTRY_BYTES + 1)
        if len(data) > MAX_REGISTRY_BYTES:
            raise ValueError()
        value = json.loads(data)
        if value.get("version") != 1 or not isinstance(value.get("workspaces"), dict):
            raise ValueError()
        uuid.UUID(value["registryId"])
        for name, row in value["workspaces"].items():
            if not valid_name(name) or not isinstance(row, dict) or row.get("agent") not in AGENTS:
                raise ValueError()
            if not all(isinstance(row.get(key), str) for key in
                       ("workspaceId", "branch", "path", "sourceSha", "state")):
                raise ValueError()
            uuid.UUID(row["workspaceId"])
        return value
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as exc:
        raise WorkspaceError("Workspace registry is unreadable or invalid; it was not replaced.") from exc


def save_registry(path: Path, value: dict) -> None:
    plain_path(path)
    data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()
    if len(data) > MAX_REGISTRY_BYTES:
        raise WorkspaceError("Workspace registry reached its local size limit.")
    temp = path.with_name("workspaces-" + uuid.uuid4().hex + ".tmp")
    try:
        with temp.open("xb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


@contextlib.contextmanager
def registry_lock(directory: Path):
    plain_path(directory)
    directory.mkdir(exist_ok=True)
    lock = directory / "workspaces.lock"
    plain_path(lock)
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise WorkspaceError("Workspace creation is already locked. Inspect the existing operation before retrying.") from exc
    try:
        os.close(descriptor)
        yield
    finally:
        lock.unlink()


def inspect_row(git: Git, canonical: Path, common: Path, base: Path, name: str, row: dict) -> dict:
    expected = plain_path(base / name)
    branch = f"workspace/{row['agent']}/{name}"
    if row["path"] != str(expected) or row["branch"] != branch:
        raise WorkspaceError("Registered workspace ownership does not match its fixed path and branch.")
    matches = [entry for entry in worktrees(git, canonical)
               if path_key(entry.get("worktree", "")) == path_key(expected)]
    if len(matches) != 1 or matches[0].get("branch") != "refs/heads/" + branch or not expected.is_dir():
        raise WorkspaceError("Registered worktree is missing or has changed branch; inspect it before retrying.")
    plain_path(expected / ".git")
    actual_common = plain_path(Path(git.run(expected, "rev-parse", "--path-format=absolute", "--git-common-dir").strip()))
    if actual_common != common:
        raise WorkspaceError("Registered worktree belongs to a different repository.")
    return {"name": name, **row, "head": git.run(expected, "rev-parse", "HEAD").strip(),
            "status": "ready" if row["state"] == "ready" else "requires_review"}


def execute(repo: Path, command: str, name: str | None, agent: str | None) -> dict:
    source = plain_path(repo)
    git = Git()
    git.disable_filters(source)
    source = plain_path(Path(git.run(source, "rev-parse", "--show-toplevel").strip()))
    entries = worktrees(git, source)
    if not entries or "bare" in entries[0]:
        raise WorkspaceError("Use an existing non-bare canonical checkout.")
    canonical = plain_path(Path(entries[0]["worktree"]))
    common = plain_path(Path(git.run(source, "rev-parse", "--path-format=absolute", "--git-common-dir").strip()))
    base = plain_path(canonical.parent / (canonical.name + "-workspaces"))
    directory = common / "helios"
    registry_path = directory / "workspaces.json"
    head = git.run(source, "rev-parse", "HEAD").strip()
    report = {"projectId": "helios-control", "projectUrl": PROJECT_URL,
              "canonicalRepository": str(canonical), "workspaceRoot": str(base),
              "sourceSha": head, "networkCalled": False, "agentStarted": False}

    if command in ("status", "list"):
        registry = load_registry(registry_path)
        result = []
        for entry_name, row in sorted(registry["workspaces"].items()):
            try:
                result.append(inspect_row(git, canonical, common, base, entry_name, row))
            except WorkspaceError:
                result.append({"name": entry_name, "agent": row["agent"], "status": "requires_review"})
        return {**report, "status": "local", "workspaces": result}

    if name is None or not valid_name(name) or agent not in AGENTS:
        raise WorkspaceError("Use a lowercase name of at most 48 letters, digits and single hyphens; Windows reserved names are excluded.")
    target = plain_path(base / name)
    branch = f"workspace/{agent}/{name}"
    with registry_lock(directory):
        registry = load_registry(registry_path)
        if name in registry["workspaces"]:
            row = registry["workspaces"][name]
            if row["agent"] != agent:
                raise WorkspaceError("This workspace name is already owned by a different agent role.")
            workspace = inspect_row(git, canonical, common, base, name, row)
            if workspace["status"] != "ready":
                raise WorkspaceError("An earlier creation did not finish. Review its preserved worktree before continuing.")
            return {**report, "status": "existing", "workspace": workspace}
        if target.exists() or any(path_key(item.get("worktree", "")) == path_key(target) for item in entries):
            raise WorkspaceError("Workspace path is already occupied; it will not be adopted or overwritten.")
        if git.run(canonical, "branch", "--list", branch).strip():
            raise WorkspaceError("Workspace branch already exists; it will not be adopted or overwritten.")
        base.mkdir(exist_ok=True)
        registry["registryId"] = registry["registryId"] or str(uuid.uuid4())
        row = {"workspaceId": str(uuid.uuid5(uuid.UUID(registry["registryId"]), name)),
               "agent": agent, "branch": branch, "path": str(target),
               "sourceSha": head, "state": "creating"}
        registry["workspaces"][name] = row
        save_registry(registry_path, registry)
        git.run(canonical, "worktree", "add", "-b", branch, "--", str(target), head)
        row["state"] = "ready"
        save_registry(registry_path, registry)
        return {**report, "status": "created", "workspace": inspect_row(git, canonical, common, base, name, row)}


def main(argv: list[str] | None = None, *, stdout=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    commands = parser.add_subparsers(dest="command")
    commands.add_parser("status")
    commands.add_parser("list")
    create = commands.add_parser("create")
    create.add_argument("name")
    create.add_argument("--agent", choices=AGENTS, required=True)
    args = parser.parse_args(argv)
    try:
        result = execute(args.repo, args.command or "status", getattr(args, "name", None), getattr(args, "agent", None))
        code = 0
    except (WorkspaceError, OSError) as exc:
        result = {"status": "blocked", "message": str(exc) if isinstance(exc, WorkspaceError) else "Local filesystem operation failed; existing work was preserved.",
                  "networkCalled": False, "agentStarted": False}
        code = 2
    print(json.dumps(result, indent=2), file=stdout or sys.stdout)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
