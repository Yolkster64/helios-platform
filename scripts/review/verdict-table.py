#!/usr/bin/env python3
"""Render a review round's findings as the verdict table posted on a pull request.

The review loop (docs/architecture/REVIEW_LOOP.md) merges on an independent reviewer's
sign-off. When no reviewer is available - Codex quota exhausted on both the cloud reviewer
and the local CLI, which happened for real on PR #252 - the session reviews the round's own
diff and posts ONE verdict comment instead. This renders that comment from the review's JSON
so the table is the same shape every time and nobody hand-writes a verdict.

Input (a file, or stdin with no argument):

    {
      "head": "807fca63",              # the commit reviewed
      "round": 14,                     # optional, for the heading
      "reviewer": "session",           # optional; "session" is the fallback reviewer
      "findings": [
        {
          "summary": "The OIDC lane confirmed only one of the three variables it needs.",
          "verdict": "CONFIRMED",      # CONFIRMED | PLAUSIBLE | REFUTED
          "lens": "correctness",       # optional
          "file": "scripts/bootstrap/connect.sh",   # optional
          "line": 254,                 # optional
          "commit": "807fca63",        # the fix, or absent when REFUTED
          "evidence": "azure-oidc-setup.sh:181-183 only echoes the three lines."
        }
      ]
    }

A REFUTED finding needs `evidence`: the loop's stopping rule is that every finding is fixed
OR refuted with evidence, never a bare disagreement, so a refutation with nothing behind it
is refused here rather than posted.

Usage:
    python3 scripts/review/verdict-table.py findings.json > verdict.md
    python3 scripts/review/verdict-table.py --check findings.json   # validate only, no output

Exit codes: 0 = rendered, 1 = the input is not a usable review, 2 = the input is not JSON.
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any

VERDICTS = ("CONFIRMED", "PLAUSIBLE", "REFUTED")


class ReviewError(ValueError):
    """The input is not a review this can render."""


def _text(value: Any, field: str, index: int) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ReviewError(f"findings[{index}].{field} must be a non-empty string")
    return value.strip()


def normalise(review: Any) -> dict[str, Any]:
    """The review with every field checked, or ReviewError naming the first problem."""
    if not isinstance(review, dict):
        raise ReviewError("the review must be a JSON object")
    head = review.get("head")
    if not isinstance(head, str) or not head.strip():
        raise ReviewError("head must be the commit that was reviewed")
    findings = review.get("findings")
    if not isinstance(findings, list):
        raise ReviewError("findings must be an array (an empty one is a clean round)")

    checked: list[dict[str, Any]] = []
    for index, finding in enumerate(findings):
        if not isinstance(finding, dict):
            raise ReviewError(f"findings[{index}] must be an object")
        verdict = finding.get("verdict")
        if verdict not in VERDICTS:
            raise ReviewError(
                f"findings[{index}].verdict must be one of {', '.join(VERDICTS)}, got {verdict!r}")
        entry = {
            "summary": _text(finding.get("summary"), "summary", index),
            "verdict": verdict,
            "lens": finding.get("lens") if isinstance(finding.get("lens"), str) else "",
            "file": finding.get("file") if isinstance(finding.get("file"), str) else "",
            # not a bool: isinstance(True, int) is True in Python, and `"line": true` would
            # otherwise render as connect.sh:True. The schema engines here draw the same line.
            "line": finding.get("line")
                    if isinstance(finding.get("line"), int) and not isinstance(finding.get("line"), bool)
                    else None,
            "commit": finding.get("commit") if isinstance(finding.get("commit"), str) else "",
            "evidence": finding.get("evidence") if isinstance(finding.get("evidence"), str) else "",
        }
        # The stopping rule: fixed, or refuted WITH evidence. A refutation carrying nothing is
        # the one shape this refuses to render, because posting it would look like a verdict.
        if verdict == "REFUTED" and not entry["evidence"].strip():
            raise ReviewError(
                f"findings[{index}] is REFUTED with no evidence; the review loop requires a file, "
                "a line or a test showing the finding was wrong - never a bare disagreement")
        if verdict != "REFUTED" and not entry["commit"].strip():
            raise ReviewError(
                f"findings[{index}] is {verdict} with no commit; say where it was fixed")
        checked.append(entry)
    return {
        "head": head.strip(),
        "round": review.get("round") if isinstance(review.get("round"), int) else None,
        "reviewer": review.get("reviewer") if isinstance(review.get("reviewer"), str) else "session",
        "findings": checked,
    }


def _cell(text: str) -> str:
    """A markdown table cell: pipes and newlines would break the row."""
    return text.replace("|", "\\|").replace("\n", " ").strip()


def render(review: dict[str, Any]) -> str:
    """The verdict comment, ready to post."""
    checked = normalise(review)
    findings = checked["findings"]
    heading = "## Review verdict"
    if checked["round"] is not None:
        heading += f" — round {checked['round']}"
    heading += f" (`{checked['head']}`)"

    lines = [heading, ""]
    if checked["reviewer"] == "session":
        lines += [
            "No independent reviewer was available for this head, so this is the session's own "
            "adversarial pass over the round's diff, posted as the merge evidence the review loop "
            "asks for in that case (docs/architecture/REVIEW_LOOP.md, \"When no reviewer is "
            "available\"). It is not equivalent to an independent review, and says so.",
            "",
        ]
    if not findings:
        lines += ["No findings: the diff was reviewed and nothing survived scrutiny.", ""]
    else:
        lines += ["| # | Finding | Lens | Verdict | Where |", "|---|---|---|---|---|"]
        for number, finding in enumerate(findings, start=1):
            where = f"`{finding['commit']}`" if finding["commit"] else "refuted"
            if finding["file"]:
                location = finding["file"] + (f":{finding['line']}" if finding["line"] else "")
                summary = f"{_cell(finding['summary'])}<br>`{_cell(location)}`"
            else:
                summary = _cell(finding["summary"])
            if finding["evidence"]:
                summary += f"<br>_{_cell(finding['evidence'])}_"
            lines.append(
                f"| {number} | {summary} | {_cell(finding['lens']) or '—'} | "
                f"**{finding['verdict']}** | {where} |")
        lines.append("")
        confirmed = sum(1 for f in findings if f["verdict"] == "CONFIRMED")
        refuted = sum(1 for f in findings if f["verdict"] == "REFUTED")
        plausible = len(findings) - confirmed - refuted
        lines += [
            f"{len(findings)} finding(s): {confirmed} confirmed and fixed, "
            f"{plausible} plausible and fixed, {refuted} refuted with evidence.",
            "",
        ]
    lines += ["---", "_Generated by [Claude Code](https://claude.ai/code)_"]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("review", nargs="?", help="the review JSON; stdin when omitted")
    parser.add_argument("--check", action="store_true",
                        help="validate the review and print nothing")
    args = parser.parse_args(argv)

    try:
        if args.review:
            with open(args.review, encoding="utf-8") as handle:
                raw = handle.read()
        else:
            raw = sys.stdin.read()
    except OSError as exc:
        print(f"cannot read the review: {exc}", file=sys.stderr)
        return 2
    try:
        review = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"the review is not valid JSON: {exc}", file=sys.stderr)
        return 2

    try:
        rendered = render(review)
    except ReviewError as exc:
        print(f"not a usable review: {exc}", file=sys.stderr)
        return 1
    if not args.check:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
