#!/usr/bin/env python3
"""Generate the site's llms.txt index and its single-file reference.

`site/public/llms.txt` follows the https://llmstxt.org convention: the book
title, the opening paragraph of `docs/src/index.md` as the summary, and the
pages of `docs/src/SUMMARY.md` linked at their published URLs. Contributor
sections and generated module pages go under `## Optional`.

`site/public/llms-full.txt` concatenates the chapters in FULL_TEXT, in
SUMMARY order, so an agent can load the language in one fetch. Relative links
become published URLs, and hidden `~` sample lines are revealed, because the
prefix is book markup rather than x2c syntax.

    python3 tools/gen-llms-txt.py --write
    python3 tools/gen-llms-txt.py --check
"""

from __future__ import annotations

import argparse
import difflib
import pathlib
import posixpath
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
BOOK = ROOT / "docs" / "src"
SUMMARY = BOOK / "SUMMARY.md"
PUBLIC = ROOT / "site" / "public"
INDEX = PUBLIC / "llms.txt"
FULL = PUBLIC / "llms-full.txt"
SITE = "https://x2c-lang.dev"
DOCS = f"{SITE}/docs/"

# The reference chapters, plus the guide chapters the reference defers to for
# the C mapping, the class and system-macro inventory, and construct choice.
FULL_TEXT = (
    "guide/from-c.md",
    "guide/system-macros.md",
    "guide/idioms.md",
    "reference/language.md",
    "reference/cli.md",
)
OPTIONAL_SECTIONS = {
    "Compiler API (provisional)",
    "Compiler and contributor internals",
}
# Nested SUMMARY entries at this depth or deeper are generated module pages.
OPTIONAL_DEPTH = 2

ENTRY = re.compile(
    r"^(?P<indent> *)- \[(?P<title>[^\]]+)\]\((?P<path>[^)]+)\)"
)
FENCE = re.compile(r"^\s*```(?P<info>[^`]*)$")
LINK = re.compile(r"(\]\(|^\[[^\]]+\]:\s*)(?P<target>[^)\s]+)")
SCHEME = re.compile(r"^[a-z][a-z0-9+.-]*:", re.IGNORECASE)


class Fatal(Exception):
    pass


def summary_sections() -> list[tuple[str, list[tuple[int, str, str]]]]:
    """Return SUMMARY sections as (heading, [(depth, title, path)])."""
    sections: list[tuple[str, list[tuple[int, str, str]]]] = []
    for line in SUMMARY.read_text(encoding="utf-8").splitlines():
        if line.startswith("# ") and line != "# Summary":
            sections.append((line[2:].strip(), []))
        elif (match := ENTRY.match(line)) and sections:
            sections[-1][1].append((
                len(match["indent"]) // 2, match["title"], match["path"]
            ))
    return sections


def page_url(path: str) -> str:
    return DOCS + re.sub(r"\.md$", ".html", path)


def link_url(page: str, target: str) -> str:
    if SCHEME.match(target):
        return target
    if target.startswith("#"):
        return page_url(page) + target
    path, mark, fragment = target.partition("#")
    resolved = posixpath.normpath(
        posixpath.join(posixpath.dirname(page), path)
    )
    return page_url(resolved) + mark + fragment


def absolute_links(page: str, line: str) -> str:
    """Rewrite link targets outside inline code spans."""
    parts = line.split("`")
    for index in range(0, len(parts), 2):
        parts[index] = LINK.sub(
            lambda match: match[1] + link_url(page, match["target"]),
            parts[index],
        )
    return "`".join(parts)


def publish_page(page: str) -> str:
    """Return one book page with published links and revealed samples."""
    lines: list[str] = []
    fence = None
    for line in (BOOK / page).read_text(encoding="utf-8").splitlines():
        if match := FENCE.match(line):
            if fence is None:
                fence = match["info"].split(",")[0].strip()
            elif not match["info"].strip():
                fence = None
            lines.append(line)
        elif fence == "x2c" and line.lstrip().startswith("~"):
            stripped = line.lstrip()
            lines.append(line[:len(line) - len(stripped)] + stripped[1:])
        elif fence is None:
            lines.append(absolute_links(page, line))
        else:
            lines.append(line)
    if fence is not None:
        raise Fatal(f"docs/src/{page}: unterminated code fence")
    return "\n".join(lines).strip() + "\n"


def book_summary() -> tuple[str, str]:
    """Return the book title and its opening paragraph as one line."""
    text = (BOOK / "index.md").read_text(encoding="utf-8")
    title, _, rest = text.partition("\n")
    paragraph = rest.strip().split("\n\n", 1)[0]
    return title.removeprefix("# ").strip(), " ".join(paragraph.split())


def render() -> dict[pathlib.Path, str]:
    sections = summary_sections()
    entries = {path: title for _, rows in sections for _, title, path in rows}
    missing = [page for page in FULL_TEXT if page not in entries]
    if missing:
        raise Fatal(f"{SUMMARY.relative_to(ROOT)} has no entry for "
                    + ", ".join(missing))
    chapters = [page for page in entries if page in FULL_TEXT]

    title, paragraph = book_summary()
    index = [
        "# x2c",
        "",
        f"> {paragraph}",
        "",
        f"[{title}]({DOCS}) contains every chapter.",
        "",
        "## Single-file reference",
        "",
        f"- [x2c language reference]({SITE}/llms-full.txt): "
        + ", ".join(entries[page] for page in chapters),
        "",
    ]
    optional: list[str] = []
    for heading, rows in sections:
        listed = []
        for depth, name, path in rows:
            row = f"- [{name}]({page_url(path)})"
            if heading in OPTIONAL_SECTIONS or depth >= OPTIONAL_DEPTH:
                optional.append(row)
            else:
                listed.append(row)
        if listed:
            index.extend((f"## {heading}", "", *listed, ""))
    index.extend(("## Optional", "", *optional, ""))

    full = [
        "# x2c language reference",
        "",
        f"> {paragraph}",
        "",
        f"These chapters come from [{title}]({DOCS}).",
        "Each chapter follows a comment naming its published URL. Samples",
        "include the lines the book hides behind an expander.",
    ]
    for page in chapters:
        full.extend(("", f"<!-- {page_url(page)} -->", "",
                     publish_page(page).rstrip()))
    return {
        INDEX: "\n".join(index).rstrip() + "\n",
        FULL: "\n".join(full) + "\n",
    }


def write(outputs: dict[pathlib.Path, str]) -> int:
    for path, text in outputs.items():
        path.write_text(text, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)} ({len(text.encode())} bytes)")
    return 0


def check(outputs: dict[pathlib.Path, str]) -> int:
    problems = 0
    for path, expected in outputs.items():
        actual = path.read_text(encoding="utf-8") if path.exists() else ""
        if actual == expected:
            continue
        problems += 1
        sys.stderr.writelines(difflib.unified_diff(
            actual.splitlines(True), expected.splitlines(True),
            fromfile=str(path.relative_to(ROOT)), tofile="generated",
        ))
    if problems:
        print("run 'make doc-generate' and review the llms.txt diff",
              file=sys.stderr)
        return 1
    print("llms.txt and llms-full.txt are current")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        outputs = render()
    except Fatal as error:
        print(f"llms.txt: {error}", file=sys.stderr)
        return 1
    if args.write:
        return write(outputs)
    if args.check:
        return check(outputs)
    sys.stdout.write(outputs[INDEX])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
