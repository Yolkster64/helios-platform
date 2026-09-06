#!/usr/bin/env python3
"""Validate every automation artifact in a tree: JSON, YAML, Bicep, Terraform, Actions.

Exists because the failure modes that actually break pipelines are mechanical and boring
(a workflow pinned to a disabled action, a YAML file that parses to the wrong type, a
Bicep name that changes every deploy). Catching them here is cheaper than catching them
in a red pipeline or a duplicated resource group.

Usage:
    validate_all.py [paths...]      # defaults to the current directory

Exit codes: 0 = clean (warnings allowed), 1 = at least one error.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - the message is the point
    print("error: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    raise SystemExit(1)


SKIP_DIRS = {
    ".git", "node_modules", "bin", "obj", "dist", "build", ".venv", "venv",
    "__pycache__", ".terraform", "packages", ".vs", ".idea",
}

# Artifact actions v3 were disabled by GitHub in Jan 2025 and hard-fail on hosted runners.
DEAD_ACTIONS = {
    "actions/upload-artifact@v3": "upload-artifact@v3 is disabled by GitHub; use @v4",
    "actions/download-artifact@v3": "download-artifact@v3 is disabled by GitHub; use @v4",
}
NONEXISTENT_ACTION_PREFIXES = {
    "actions/setup-powershell": "actions/setup-powershell does not exist; pwsh is preinstalled — use `shell: pwsh`",
}
STALE_ACTIONS = {
    "actions/checkout@v3": "checkout@v3 is stale; use @v4",
    "actions/cache@v3": "cache@v3 is stale; use @v4",
    "actions/setup-dotnet@v3": "setup-dotnet@v3 is stale; use @v4",
    "actions/setup-node@v3": "setup-node@v3 is stale; use @v4",
    "actions/setup-python@v4": "setup-python@v4 is stale; use @v5",
}

# Contexts an attacker can set. Interpolated into `run:` they execute as shell.
INJECTABLE = re.compile(
    r"\$\{\{\s*(github\.event\.(issue|pull_request|comment|review|discussion)\b[^}]*"
    r"|github\.head_ref|github\.event\.head_commit\.message)\s*\}\}"
)


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    checked: int = 0

    def error(self, path: Path, msg: str) -> None:
        self.errors.append(f"{path}: {msg}")

    def warn(self, path: Path, msg: str) -> None:
        self.warnings.append(f"{path}: {msg}")


def walk(roots: list[Path]):
    for root in roots:
        if root.is_file():
            yield root
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for name in filenames:
                yield Path(dirpath) / name


def check_json(path: Path, report: Report) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    try:
        json.loads(text)
    except json.JSONDecodeError as exc:
        # .bicepparam-adjacent and JSONC files legitimately allow comments; flag softly.
        if "//" in text or "/*" in text:
            report.warn(path, f"invalid strict JSON ({exc.msg}); looks like JSONC")
        else:
            report.error(path, f"invalid JSON: {exc.msg} (line {exc.lineno})")
        return
    report.checked += 1
    scan_for_secrets(path, text, report)


def check_yaml(path: Path, report: Report) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    try:
        docs = list(yaml.safe_load_all(text))
    except yaml.YAMLError as exc:
        report.error(path, f"invalid YAML: {str(exc).splitlines()[0]}")
        return
    report.checked += 1
    scan_for_secrets(path, text, report)
    if is_workflow(path):
        for doc in docs:
            if isinstance(doc, dict):
                check_workflow(path, doc, text, report)


def iter_shell_scalars(doc: dict):
    """Yield (label, text) for every scalar that executes: step `run:` blocks and the
    `script:` input of actions/github-script. Nothing else in a workflow is evaluated
    as code, so nothing else is an interpolation risk."""
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        return
    for job_id, job in jobs.items():
        if not isinstance(job, dict):
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for index, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            label = step.get("name") or step.get("id") or f"step {index + 1}"
            run = step.get("run")
            if isinstance(run, str):
                yield f"{job_id} / {label} run:", run
            uses = step.get("uses")
            inputs = step.get("with")
            if isinstance(uses, str) and uses.startswith("actions/github-script") \
                    and isinstance(inputs, dict) and isinstance(inputs.get("script"), str):
                yield f"{job_id} / {label} script:", inputs["script"]


def locate_line(text: str, scalar: str, needle: str) -> int | None:
    """Best-effort 1-based line of `needle` inside the block that `scalar` came from:
    anchor on the block's first non-blank line, then search forward for the needle,
    so an identical expression under `env:` above the block is not what gets named."""
    anchor = next((line.strip() for line in scalar.splitlines() if line.strip()), "")
    start = text.find(anchor) if anchor else -1
    position = text.find(needle, start if start >= 0 else 0)
    if position < 0:
        return None
    return text[:position].count("\n") + 1


def is_workflow(path: Path) -> bool:
    return path.suffix in {".yml", ".yaml"} and path.parent.name == "workflows" \
        and path.parent.parent.name == ".github"


def check_workflow(path: Path, doc: dict, text: str, report: Report) -> None:
    # `on` is parsed by YAML 1.1 as boolean True — a classic footgun worth naming.
    triggers = doc.get("on", doc.get(True))
    if triggers is None:
        report.error(path, "workflow has no `on:` trigger")

    if "permissions" not in doc:
        report.warn(path, "no top-level `permissions:` — defaults are broad; set least privilege")

    # Only `uses:` lines declare actions — scanning raw text flags prose in comments.
    used = "\n".join(
        line for line in text.splitlines()
        if re.match(r"\s*-?\s*uses:", line)
    )
    for action, why in DEAD_ACTIONS.items():
        if action in used:
            report.error(path, why)
    for prefix, why in NONEXISTENT_ACTION_PREFIXES.items():
        if prefix in used:
            report.error(path, why)
    for action, why in STALE_ACTIONS.items():
        if action in used:
            report.warn(path, why)

    # Only the scalars a runner hands to a shell (or to github-script's JS) are
    # injection sites. `env:` values, `concurrency` groups, `if:` conditions and
    # ordinary `with:` inputs receive the expression as a plain value — putting the
    # context there IS the recommended fix — so scanning the raw text flagged every
    # correctly wired workflow (measured: 16 "errors", 12 of them the env: idiom).
    for label, scalar in iter_shell_scalars(doc):
        for match in INJECTABLE.finditer(scalar):
            # A comparison (`… != null`, `… == 'x'`) evaluates to true/false before
            # the shell sees it — a boolean literal, not attacker text.
            if re.search(r"==|!=", match.group(0)):
                continue
            line = locate_line(text, scalar, match.group(0))
            where = f"line {line}" if line else label
            report.error(
                path,
                f"{where}: attacker-controlled `{match.group(0)}` interpolated directly "
                f"into a shell/script block ({label}); pass it through `env:` and "
                "reference $VAR instead",
            )

    if "pull_request_target" in text and "actions/checkout" in text:
        report.warn(
            path,
            "pull_request_target + checkout: runs with write token and secrets; "
            "never check out untrusted PR head here",
        )

    jobs = doc.get("jobs")
    if isinstance(jobs, dict):
        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                continue
            if "runs-on" not in job and "uses" not in job:
                report.error(path, f"job `{job_name}` has neither `runs-on` nor `uses`")


def scan_for_secrets(path: Path, text: str, report: Report) -> None:
    """Catch literal credentials. Env-name indirection is the pattern we want instead."""
    patterns = [
        (r"sk-[A-Za-z0-9]{20,}", "OpenAI-style API key"),
        (r"sk-ant-[A-Za-z0-9\-_]{20,}", "Anthropic API key"),
        (r"gh[pousr]_[A-Za-z0-9]{30,}", "GitHub token"),
        (r"AKIA[0-9A-Z]{16}", "AWS access key id"),
        (r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----", "private key"),
    ]
    for pattern, what in patterns:
        if re.search(pattern, text):
            report.error(path, f"looks like a committed {what}; store the name, not the value")


def check_bicep(paths: list[Path], report: Report) -> None:
    if not paths:
        return
    bicep = shutil.which("bicep")
    az = shutil.which("az")
    if not bicep and not az:
        report.warn(paths[0].parent, "bicep CLI not found; skipped Bicep compilation")
        return
    for path in paths:
        # .bicepparam files compile with build-params, not build.
        verb = "build-params" if path.suffix == ".bicepparam" else "build"
        cmd = ([bicep, verb, str(path), "--stdout"] if bicep
               else [az, "bicep", verb, "--file", str(path), "--stdout"])
        proc = subprocess.run(cmd, capture_output=True, text=True)
        report.checked += 1
        if proc.returncode != 0:
            first = (proc.stderr or proc.stdout).strip().splitlines()
            report.error(path, "bicep build failed: " + (first[0] if first else "unknown error"))
        elif proc.stderr.strip():
            for line in proc.stderr.strip().splitlines():
                if "Warning" in line:
                    report.warn(path, f"bicep lint: {line.strip()}")
        text = path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"name:\s*[^\n]*utcNow\(", text):
            report.error(
                path,
                "utcNow() in a resource name makes every deployment create new resources; "
                "seed with uniqueString(resourceGroup().id) instead",
            )


def check_terraform(dirs: set[Path], report: Report) -> None:
    if not dirs:
        return
    terraform = shutil.which("terraform")
    if not terraform:
        report.warn(next(iter(dirs)), "terraform CLI not found; skipped fmt/validate")
        return
    for directory in sorted(dirs):
        fmt = subprocess.run([terraform, "fmt", "-check", "-recursive", str(directory)],
                             capture_output=True, text=True)
        report.checked += 1
        if fmt.returncode != 0 and fmt.stdout.strip():
            report.warn(directory, f"terraform fmt would rewrite: {fmt.stdout.strip().splitlines()[0]}")
        # validate needs `init`; only run it where the working dir is already initialized,
        # because a network-dependent init inside a validator is its own failure mode.
        if (directory / ".terraform").exists():
            val = subprocess.run([terraform, "validate", "-no-color"],
                                 capture_output=True, text=True, cwd=directory)
            if val.returncode != 0:
                report.error(directory, f"terraform validate: {val.stdout.strip().splitlines()[0] if val.stdout.strip() else val.stderr.strip()}")
        else:
            report.warn(directory, "not initialized (.terraform missing); ran fmt only")


def main(argv: list[str]) -> int:
    roots = [Path(a) for a in argv[1:]] or [Path(".")]
    for root in roots:
        if not root.exists():
            print(f"error: {root} does not exist", file=sys.stderr)
            return 1

    report = Report()
    bicep_files: list[Path] = []
    terraform_dirs: set[Path] = set()

    for path in walk(roots):
        suffix = path.suffix.lower()
        if suffix == ".json":
            check_json(path, report)
        elif suffix in {".yml", ".yaml"}:
            check_yaml(path, report)
        elif suffix in {".bicep", ".bicepparam"}:
            bicep_files.append(path)
        elif suffix == ".tf":
            terraform_dirs.add(path.parent)
        elif path.name in {".env", ".env.template", ".env.example"}:
            scan_for_secrets(path, path.read_text(encoding="utf-8", errors="replace"), report)
            report.checked += 1

    check_bicep(bicep_files, report)
    check_terraform(terraform_dirs, report)

    for warning in report.warnings:
        print(f"WARN  {warning}")
    for error in report.errors:
        print(f"ERROR {error}")

    print(
        f"\n{report.checked} artifact(s) checked · "
        f"{len(report.errors)} error(s) · {len(report.warnings)} warning(s)"
    )
    return 1 if report.errors else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
