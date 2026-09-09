#!/usr/bin/env python3
"""Verify the themed-workspace palette: contrast, provenance, and drift.

Reads the ``workbench.colorCustomizations`` block from ``workspace.code-workspace``
(the authority for VS Code) and checks three things, with no dependencies beyond
the standard library:

1. Contrast (WCAG 2.x). Every text/background pair listed in ``TEXT_PAIRS`` holds
   at least 4.5:1 (AA, normal text); every interactive indicator in
   ``INDICATOR_PAIRS`` (focus rings, active borders, cursors) holds at least 3:1
   (AA, non-text contrast). ``terminal.ansiBlack`` is skipped only when it equals
   ``terminal.background`` (the dark-terminal convention). A palette block that
   omits a colour key a declared pair names FAILS: VS Code would fall back to the
   active theme for that side of the pair, which is never measured against the
   HELIOS colour on the other side, and two blocks missing the same key stay equal
   so the drift check alone would not notice.
2. Provenance. Every hex value in the dark block is a colour literal of the
   ``Default`` dictionary in ``src/gui/HELIOS.Shell/Themes/Tokens.xaml``; every
   hex in the light block is a literal of the ``Light`` dictionary. No colour may
   be invented outside the canonical token file (read-only here).
3. Drift. The block in ``.devcontainer/devcontainer.json``
   (``customizations.vscode.settings``) must equal the workspace block, and every
   hex the blocks use must appear in ``docs/architecture/WORKSPACE_THEME.md`` so
   the mapping table stays complete.

Exit codes: 0 = every check passed, 1 = at least one check failed,
2 = a file is missing or is not strict JSON / well-formed XML.

Usage::

    python3 scripts/verify/theme-contrast.py            # text report
    python3 scripts/verify/theme-contrast.py --markdown # table rows for the doc
    python3 scripts/verify/theme-contrast.py --json     # machine-readable
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

AA_TEXT = 4.5
AA_NON_TEXT = 3.0
HEX_RE = re.compile(r"^#([0-9A-Fa-f]{6})$")
XAML_KEY = "{http://schemas.microsoft.com/winfx/2006/xaml}Key"
THEME_SCOPE_RE = re.compile(r"^\[.*\]$")

# (foreground key, background key): body-text pairs gated at 4.5:1.
TEXT_PAIRS: tuple[tuple[str, str], ...] = (
    ("titleBar.activeForeground", "titleBar.activeBackground"),
    ("titleBar.inactiveForeground", "titleBar.inactiveBackground"),
    ("activityBar.foreground", "activityBar.background"),
    ("activityBar.inactiveForeground", "activityBar.background"),
    ("activityBarBadge.foreground", "activityBarBadge.background"),
    ("sideBar.foreground", "sideBar.background"),
    ("sideBarTitle.foreground", "sideBar.background"),
    ("sideBarSectionHeader.foreground", "sideBarSectionHeader.background"),
    ("descriptionForeground", "sideBar.background"),
    ("disabledForeground", "sideBar.background"),
    ("editor.foreground", "editor.background"),
    ("editor.foreground", "editor.lineHighlightBackground"),
    ("editor.foreground", "editor.selectionBackground"),
    ("editorLineNumber.foreground", "editor.background"),
    ("editorLineNumber.activeForeground", "editor.background"),
    ("textLink.foreground", "editor.background"),
    ("editorError.foreground", "editor.background"),
    ("editorWarning.foreground", "editor.background"),
    ("editorInfo.foreground", "editor.background"),
    ("editorWidget.foreground", "editorWidget.background"),
    ("tab.activeForeground", "tab.activeBackground"),
    ("tab.inactiveForeground", "tab.inactiveBackground"),
    ("breadcrumb.foreground", "breadcrumb.background"),
    ("breadcrumb.focusForeground", "breadcrumb.background"),
    ("statusBar.foreground", "statusBar.background"),
    ("statusBar.debuggingForeground", "statusBar.debuggingBackground"),
    ("statusBarItem.remoteForeground", "statusBarItem.remoteBackground"),
    ("statusBarItem.errorForeground", "statusBarItem.errorBackground"),
    ("statusBarItem.warningForeground", "statusBarItem.warningBackground"),
    ("badge.foreground", "badge.background"),
    ("button.foreground", "button.background"),
    ("button.foreground", "button.hoverBackground"),
    ("button.secondaryForeground", "button.secondaryBackground"),
    ("list.activeSelectionForeground", "list.activeSelectionBackground"),
    ("list.inactiveSelectionForeground", "list.inactiveSelectionBackground"),
    ("list.hoverForeground", "list.hoverBackground"),
    ("list.highlightForeground", "list.activeSelectionBackground"),
    ("list.highlightForeground", "sideBar.background"),
    ("input.foreground", "input.background"),
    ("input.placeholderForeground", "input.background"),
    ("dropdown.foreground", "dropdown.background"),
    ("quickInput.foreground", "quickInput.background"),
    ("menu.foreground", "menu.background"),
    ("menu.selectionForeground", "menu.selectionBackground"),
    ("panelTitle.activeForeground", "panel.background"),
    ("panelTitle.inactiveForeground", "panel.background"),
    ("notifications.foreground", "notifications.background"),
    ("gitDecoration.addedResourceForeground", "sideBar.background"),
    ("gitDecoration.modifiedResourceForeground", "sideBar.background"),
    ("gitDecoration.deletedResourceForeground", "sideBar.background"),
    ("gitDecoration.untrackedResourceForeground", "sideBar.background"),
    ("gitDecoration.ignoredResourceForeground", "sideBar.background"),
    ("gitDecoration.conflictingResourceForeground", "sideBar.background"),
    ("terminal.foreground", "terminal.background"),
    ("terminal.foreground", "terminal.selectionBackground"),
    ("terminal.ansiBlack", "terminal.background"),
    ("terminal.ansiBrightBlack", "terminal.background"),
    ("terminal.ansiRed", "terminal.background"),
    ("terminal.ansiBrightRed", "terminal.background"),
    ("terminal.ansiGreen", "terminal.background"),
    ("terminal.ansiBrightGreen", "terminal.background"),
    ("terminal.ansiYellow", "terminal.background"),
    ("terminal.ansiBrightYellow", "terminal.background"),
    ("terminal.ansiBlue", "terminal.background"),
    ("terminal.ansiBrightBlue", "terminal.background"),
    ("terminal.ansiMagenta", "terminal.background"),
    ("terminal.ansiBrightMagenta", "terminal.background"),
    ("terminal.ansiCyan", "terminal.background"),
    ("terminal.ansiBrightCyan", "terminal.background"),
    ("terminal.ansiWhite", "terminal.background"),
    ("terminal.ansiBrightWhite", "terminal.background"),
)

# Interactive indicators gated at 3:1 (WCAG 1.4.11). Plain dividers such as
# ``sideBar.border`` are deliberately not gated: 1.4.11 exempts boundaries that
# are not required to identify the component.
INDICATOR_PAIRS: tuple[tuple[str, str], ...] = (
    ("focusBorder", "editor.background"),
    ("focusBorder", "sideBar.background"),
    ("activityBar.activeBorder", "activityBar.background"),
    ("tab.activeBorderTop", "tab.activeBackground"),
    ("panelTitle.activeBorder", "panel.background"),
    ("editorCursor.foreground", "editor.background"),
    ("terminalCursor.foreground", "terminal.background"),
    ("list.focusOutline", "list.activeSelectionBackground"),
    ("inputOption.activeBorder", "input.background"),
    ("progressBar.background", "statusBar.background"),
)


def parse_hex(value: str, where: str) -> tuple[int, int, int]:
    match = HEX_RE.match(value or "")
    if not match:
        raise ValueError(
            f"{where}: {value!r} is not an opaque #RRGGBB colour "
            "(alpha channels cannot be contrast-checked without compositing)"
        )
    digits = match.group(1)
    return int(digits[0:2], 16), int(digits[2:4], 16), int(digits[4:6], 16)


def channel_luminance(channel: int) -> float:
    c = channel / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    r, g, b = (channel_luminance(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg: str, bg: str) -> float:
    lf = relative_luminance(parse_hex(fg, "foreground"))
    lb = relative_luminance(parse_hex(bg, "background"))
    lighter, darker = max(lf, lb), min(lf, lb)
    return (lighter + 0.05) / (darker + 0.05)


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: {path} does not exist") from None
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: {path} is not strict JSON: {exc.msg} (line {exc.lineno})") from None


def split_blocks(customizations: dict) -> dict[str, dict[str, str]]:
    """Return {scope label: {colour key: hex}}; unscoped keys form '(all themes)'."""
    blocks: dict[str, dict[str, str]] = {}
    unscoped: dict[str, str] = {}
    for key, value in customizations.items():
        if THEME_SCOPE_RE.match(key) and isinstance(value, dict):
            blocks[key] = dict(value)
        else:
            unscoped[key] = value
    if unscoped:
        blocks["(all themes)"] = unscoped
    return blocks


def dictionary_for(scope: str) -> str:
    """Map a theme-scope key to the Tokens.xaml dictionary it must draw from."""
    return "Light" if "light" in scope.lower() else "Default"


def load_token_literals(tokens_path: Path) -> dict[str, set[str]]:
    """Collect the #RRGGBB literals per theme dictionary in Tokens.xaml."""
    try:
        root = ET.fromstring(tokens_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: {tokens_path} does not exist") from None
    except ET.ParseError as exc:
        raise SystemExit(f"error: {tokens_path} is not well-formed XML: {exc}") from None
    literals: dict[str, set[str]] = {}
    for dictionary in root.iter():
        name = dictionary.attrib.get(XAML_KEY)
        if not dictionary.tag.endswith("ResourceDictionary") or name not in {"Default", "Light", "HighContrast"}:
            continue
        found: set[str] = set()
        for element in dictionary.iter():
            colour = element.attrib.get("Color")
            if colour and HEX_RE.match(colour):
                found.add(colour.upper())
            if element.tag.endswith("}Color") and element.text and HEX_RE.match(element.text.strip()):
                found.add(element.text.strip().upper())
        literals[name] = found
    return literals


def check_block(
    scope: str, block: dict[str, str], failures: list[str]
) -> list[dict]:
    rows: list[dict] = []
    # A block that names none of the declared pair colours is not a palette block (an
    # unscoped stray key, say); one that names any of them must name all of them.
    declared = {key for pairs in (TEXT_PAIRS, INDICATOR_PAIRS) for pair in pairs for key in pair}
    if not declared & set(block):
        return rows
    for pairs, threshold, kind in ((TEXT_PAIRS, AA_TEXT, "text"), (INDICATOR_PAIRS, AA_NON_TEXT, "indicator")):
        for fg_key, bg_key in pairs:
            absent = [key for key in (fg_key, bg_key) if key not in block]
            if absent:
                failures.append(
                    f"{scope}: pair {fg_key} on {bg_key}: {', '.join(absent)} is not defined in the block "
                    "(VS Code would fall back to the active theme for that colour, unmeasured)"
                )
                continue
            fg, bg = block[fg_key], block[bg_key]
            if fg_key == "terminal.ansiBlack" and fg.upper() == bg.upper():
                rows.append({"scope": scope, "kind": kind, "fg_key": fg_key, "fg": fg, "bg_key": bg_key,
                             "bg": bg, "ratio": None, "threshold": threshold, "ok": True,
                             "note": "skipped: equals terminal.background (dark-terminal convention)"})
                continue
            try:
                ratio = contrast_ratio(fg, bg)
            except ValueError as exc:
                failures.append(f"{scope}: {exc}")
                continue
            ok = ratio >= threshold
            if not ok:
                failures.append(
                    f"{scope}: {fg_key} {fg} on {bg_key} {bg} = {ratio:.2f}:1 (< {threshold}:1)"
                )
            rows.append({"scope": scope, "kind": kind, "fg_key": fg_key, "fg": fg, "bg_key": bg_key,
                         "bg": bg, "ratio": round(ratio, 2), "threshold": threshold, "ok": ok, "note": ""})
    return rows


def check_provenance(
    scope: str, block: dict[str, str], literals: dict[str, set[str]], failures: list[str]
) -> None:
    dictionary = dictionary_for(scope)
    allowed = literals.get(dictionary, set())
    for key, value in block.items():
        if not isinstance(value, str):
            failures.append(f"{scope}: {key} is not a string")
            continue
        if not HEX_RE.match(value):
            failures.append(f"{scope}: {key} = {value!r} is not an opaque #RRGGBB literal")
            continue
        if value.upper() not in allowed:
            failures.append(
                f"{scope}: {key} = {value} is not a literal of the Tokens.xaml '{dictionary}' dictionary"
            )


def render_text(rows: list[dict]) -> str:
    lines = []
    for row in rows:
        ratio = "   n/a" if row["ratio"] is None else f"{row['ratio']:6.2f}"
        verdict = "PASS" if row["ok"] else "FAIL"
        note = f"  {row['note']}" if row["note"] else ""
        lines.append(
            f"{verdict} {ratio}:1 >= {row['threshold']}:1  {row['scope']}  "
            f"{row['fg_key']} {row['fg']} on {row['bg_key']} {row['bg']}{note}"
        )
    return "\n".join(lines)


def render_markdown(rows: list[dict]) -> str:
    lines = ["| Scope | Kind | Foreground | Background | Ratio | Gate | Result |", "| --- | --- | --- | --- | --- | --- | --- |"]
    for row in rows:
        ratio = "n/a" if row["ratio"] is None else f"{row['ratio']:.2f}:1"
        verdict = "pass" if row["ok"] else "FAIL"
        if row["note"]:
            verdict = f"{verdict} ({row['note']})"
        lines.append(
            f"| `{row['scope']}` | {row['kind']} | `{row['fg_key']}` `{row['fg']}` | "
            f"`{row['bg_key']}` `{row['bg']}` | {ratio} | {row['threshold']}:1 | {verdict} |"
        )
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--workspace", default="workspace.code-workspace", type=Path)
    parser.add_argument("--devcontainer", default=Path(".devcontainer/devcontainer.json"), type=Path)
    parser.add_argument("--tokens", default=Path("src/gui/HELIOS.Shell/Themes/Tokens.xaml"), type=Path)
    parser.add_argument("--doc", default=Path("docs/architecture/WORKSPACE_THEME.md"), type=Path)
    parser.add_argument("--no-drift", action="store_true", help="skip the devcontainer and doc drift checks")
    parser.add_argument("--markdown", action="store_true", help="print the contrast table as Markdown rows")
    parser.add_argument("--json", action="store_true", help="print a machine-readable report")
    args = parser.parse_args(argv[1:])

    workspace = load_json(args.workspace)
    customizations = workspace.get("settings", {}).get("workbench.colorCustomizations")
    if not isinstance(customizations, dict) or not customizations:
        raise SystemExit(f"error: {args.workspace} has no settings.workbench.colorCustomizations block")

    failures: list[str] = []
    blocks = split_blocks(customizations)
    literals = load_token_literals(args.tokens)
    rows: list[dict] = []
    for scope, block in blocks.items():
        check_provenance(scope, block, literals, failures)
        rows.extend(check_block(scope, block, failures))

    if not args.no_drift:
        devcontainer = load_json(args.devcontainer)
        container_block = (
            devcontainer.get("customizations", {}).get("vscode", {}).get("settings", {})
            .get("workbench.colorCustomizations")
        )
        if container_block != customizations:
            failures.append(
                f"drift: {args.devcontainer} customizations.vscode.settings['workbench.colorCustomizations'] "
                f"differs from {args.workspace}"
            )
        if args.doc.exists():
            doc_text = args.doc.read_text(encoding="utf-8").upper()
            used = sorted({v.upper() for block in blocks.values() for v in block.values() if isinstance(v, str)})
            missing = [hex_value for hex_value in used if hex_value not in doc_text]
            if missing:
                failures.append(f"doc: {args.doc} does not mention {', '.join(missing)}")
        else:
            failures.append(f"doc: {args.doc} does not exist")

    if args.json:
        print(json.dumps({"rows": rows, "failures": failures, "ok": not failures}, indent=2))
    elif args.markdown:
        print(render_markdown(rows))
    else:
        print(render_text(rows))
        checked = sum(1 for row in rows if row["ratio"] is not None)
        print(f"\n{checked} pair(s) measured across {len(blocks)} block(s); {len(failures)} failure(s)")
    if failures and not args.json:
        print("", file=sys.stderr)
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
