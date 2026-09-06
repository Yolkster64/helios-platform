#!/usr/bin/env python3
"""Rewrite relative links for the wiki copies of docs/ pages.

wiki-generator.yml flattens docs/GETTING_STARTED.md, docs/architecture/*.md and
docs/mcp/*.md into wiki pages (Getting-Started, Architecture-<name>, Mcp-<name>).
A relative link that resolves in the repository tree does not resolve on the wiki,
where every page sits at the top level. Each copy is therefore rewritten here:

- a link to another published page becomes that page's name (anchor kept), which
  the wiki resolves as a sibling page;
- a link to any other file or directory of the checkout becomes an absolute GitHub
  URL (blob/ for links, raw/ for images, tree/ for directories);
- a target that does not exist in the checkout is left untouched and reported, so
  a dead link in the source stays visible instead of being hidden by the rewrite;
- absolute URLs, mailto: links, bare anchors and fenced code blocks are untouched.

The repository copy keeps its relative links (the repo-side link checks rely on
them); only the wiki copy changes.

Usage:
  rewrite_links.py --repo OWNER/REPO --ref main --out wiki SOURCE.md...
  rewrite_links.py --check SOURCE.md...    # print the plan; exit 1 on unresolved targets
  rewrite_links.py --self-test             # exercise the rules on a temporary tree
"""

from __future__ import annotations

import argparse
import os
import posixpath
import re
import sys
import tempfile

LINK_RE = re.compile(r"(!?)\[([^\]]*)\]\(([^)\s]+)((?:\s+\"[^\"]*\")?)\)")
SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def page_name(source: str) -> str | None:
    """The wiki page name a docs/ path is published as, or None when it is not published."""
    src = posixpath.normpath(source.replace(os.sep, "/"))
    if src == "docs/GETTING_STARTED.md":
        return "Getting-Started"
    if not src.endswith(".md"):
        return None
    stem = posixpath.basename(src)[: -len(".md")]
    if src.startswith("docs/architecture/") and "/" not in src[len("docs/architecture/") :]:
        return f"Architecture-{stem}"
    if src.startswith("docs/mcp/") and "/" not in src[len("docs/mcp/") :]:
        return f"Mcp-{stem}"
    return None


def rewrite_target(source: str, target: str, repo: str, ref: str, root: str, is_image: bool):
    """Return (new_target, kind) where kind is one of page / url / kept / unresolved."""
    if not target or target.startswith("#") or SCHEME_RE.match(target):
        return target, "kept"
    path, sep, fragment = target.partition("#")
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(source.replace(os.sep, "/")), path))
    if resolved.startswith("../") or resolved == "..":
        return target, "unresolved"
    page = page_name(resolved)
    if page is not None and os.path.exists(os.path.join(root, resolved)):
        return page + (sep + fragment if sep else ""), "page"
    full = os.path.join(root, resolved)
    if os.path.isdir(full):
        return f"https://github.com/{repo}/tree/{ref}/{resolved}", "url"
    if os.path.isfile(full):
        mode = "raw" if is_image else "blob"
        return f"https://github.com/{repo}/{mode}/{ref}/{resolved}" + (sep + fragment if sep else ""), "url"
    return target, "unresolved"


def rewrite_text(source: str, text: str, repo: str, ref: str, root: str):
    """Rewrite every inline link outside fenced code blocks; return (text, report rows)."""
    out_lines = []
    rows = []
    in_fence = False
    for lineno, line in enumerate(text.splitlines(keepends=True), start=1):
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            out_lines.append(line)
            continue
        if in_fence:
            out_lines.append(line)
            continue

        def repl(match: re.Match) -> str:
            bang, label, target, title = match.groups()
            new_target, kind = rewrite_target(source, target, repo, ref, root, bang == "!")
            if kind != "kept":
                rows.append((lineno, target, new_target, kind))
            return f"{bang}[{label}]({new_target}{title})"

        out_lines.append(LINK_RE.sub(repl, line))
    return "".join(out_lines), rows


def process(sources, repo, ref, root, out_dir, check_only):
    unresolved = 0
    for source in sources:
        rel = os.path.relpath(source, root).replace(os.sep, "/")
        page = page_name(rel)
        if page is None:
            print(f"::error file={rel}::not a published docs page (expected docs/GETTING_STARTED.md, docs/architecture/*.md or docs/mcp/*.md)")
            return 2
        with open(source, encoding="utf-8") as handle:
            text = handle.read()
        new_text, rows = rewrite_text(rel, text, repo, ref, root)
        for lineno, target, new_target, kind in rows:
            if kind == "unresolved":
                unresolved += 1
                print(f"::warning file={rel},line={lineno}::link target '{target}' does not exist in the checkout; left as written on the wiki copy")
            elif check_only:
                print(f"{rel}:{lineno}: {target} -> {new_target} ({kind})")
        if not check_only:
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, page + ".md"), "w", encoding="utf-8") as handle:
                handle.write(new_text)
            print(f"{rel} -> {page}.md ({len(rows)} link(s) rewritten)")
    if check_only and unresolved:
        print(f"{unresolved} unresolved link target(s)")
        return 1
    return 0


def self_test() -> int:
    with tempfile.TemporaryDirectory() as root:
        os.makedirs(os.path.join(root, "docs", "mcp"))
        os.makedirs(os.path.join(root, "docs", "architecture"))
        os.makedirs(os.path.join(root, "scripts", "bootstrap"))
        for path in ("README.md", "docs/mcp/CLIENT_SETUP.md", "docs/architecture/REVIEW_LOOP.md",
                     "docs/OWNER_START_HERE.md", "docs/logo.png", "scripts/bootstrap/README.md"):
            with open(os.path.join(root, path), "w", encoding="utf-8") as handle:
                handle.write("x")
        guide = (
            "[readme](../README.md#current-status) [setup](mcp/CLIENT_SETUP.md) "
            "[loop](architecture/REVIEW_LOOP.md#stopping-rule) [owner](OWNER_START_HERE.md) "
            "![logo](logo.png) [dir](../scripts/bootstrap/) [gone](missing.md) "
            "[abs](https://example.com/a.md) [anchor](#pick-your-path) [mail](mailto:x@example.com)\n"
            "```bash\n[not a link](../README.md)\n```\n"
            "[after fence](../README.md)\n"
        )
        with open(os.path.join(root, "docs", "GETTING_STARTED.md"), "w", encoding="utf-8") as handle:
            handle.write(guide)
        text, rows = rewrite_text("docs/GETTING_STARTED.md", guide, "o/r", "main", root)
        expect = {
            "../README.md#current-status": ("https://github.com/o/r/blob/main/README.md#current-status", "url"),
            "mcp/CLIENT_SETUP.md": ("Mcp-CLIENT_SETUP", "page"),
            "architecture/REVIEW_LOOP.md#stopping-rule": ("Architecture-REVIEW_LOOP#stopping-rule", "page"),
            "OWNER_START_HERE.md": ("https://github.com/o/r/blob/main/docs/OWNER_START_HERE.md", "url"),
            "logo.png": ("https://github.com/o/r/raw/main/docs/logo.png", "url"),
            "../scripts/bootstrap/": ("https://github.com/o/r/tree/main/scripts/bootstrap", "url"),
            "missing.md": ("missing.md", "unresolved"),
            "../README.md": ("https://github.com/o/r/blob/main/README.md", "url"),
        }
        got = {target: (new, kind) for _, target, new, kind in rows}
        failures = [t for t, want in expect.items() if got.get(t) != want]
        if failures or len(rows) != len(expect):
            print("self-test FAILED:", failures, rows)
            return 1
        if "[not a link](../README.md)" not in text or "(https://example.com/a.md)" not in text \
                or "(#pick-your-path)" not in text or "(mailto:x@example.com)" not in text:
            print("self-test FAILED: untouched links changed")
            return 1
        if page_name("docs/architecture/nested/X.md") is not None or page_name("docs/PROJECT_SETUP.md") is not None:
            print("self-test FAILED: page_name maps an unpublished path")
            return 1
    print("rewrite_links self-test: 8 rewrite rules, 4 untouched forms, page mapping — all as expected")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sources", nargs="*", help="docs pages to publish")
    parser.add_argument("--repo", help="OWNER/REPO for absolute URLs")
    parser.add_argument("--ref", default="main", help="branch or commit for absolute URLs (default main)")
    parser.add_argument("--out", help="directory that receives <Page-Name>.md files")
    parser.add_argument("--root", default=".", help="repository root the sources are relative to")
    parser.add_argument("--check", action="store_true", help="print the rewrite plan without writing")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.sources:
        parser.error("no sources given")
    if not args.check and not (args.repo and args.out):
        parser.error("--repo and --out are required unless --check is used")
    root = os.path.abspath(args.root)
    return process(args.sources, args.repo or "OWNER/REPO", args.ref, root, args.out, args.check)


if __name__ == "__main__":
    sys.exit(main())
