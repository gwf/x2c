#!/usr/bin/env python3
"""Read-only checks for the current x2c documentation truth surface."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
BOOK_SRC = ROOT / "docs" / "src"
DOCS = (
    ROOT / "README.md",
    ROOT / "AGENTS.md",
    *sorted((ROOT / "agents").glob("*.md")),
    *sorted((ROOT / "docs").glob("*.md")),
    *sorted((ROOT / "docs" / "src").rglob("*.md")),
)
PATH_AUDIT = {
    ROOT / "README.md",
    ROOT / "AGENTS.md",
    ROOT / "agents" / "AGENTS.md",
    ROOT / "agents" / "quick-start.md",
    ROOT / "docs" / "src" / "internals" / "architecture.md",
    ROOT / "agents" / "x2c-code-organization-guide.md",
    ROOT / "agents" / "x2c-debugging-guide.md",
    ROOT / "agents" / "x2c-development-guide.md",
    ROOT / "agents" / "x2c-docs-drift-report.md",
    ROOT / "agents" / "x2c-module-catalog.md",
    ROOT / "agents" / "x2c-philosophy.md",
    ROOT / "docs" / "src" / "reference" / "cli.md",
    ROOT / "docs" / "src" / "reference" / "language.md",
    ROOT / "docs" / "src" / "guide" / "idioms.md",
    ROOT / "docs" / "src" / "internals" / "implementation-map.md",
    ROOT / "docs" / "src" / "library" / "overview.md",
    ROOT / "agents" / "logger-and-diagnostics-guide.md",
}
GENERATED_PATHS = {
    ROOT / "unittest" / "build",
    ROOT / "docs" / "book",
    ROOT / "site" / "dist",
}
FLAG_AUDIT = {
    ROOT / "README.md",
    ROOT / "agents" / "quick-start.md",
    ROOT / "docs" / "src" / "internals" / "architecture.md",
    ROOT / "agents" / "x2c-debugging-guide.md",
    ROOT / "docs" / "src" / "reference" / "language.md",
    ROOT / "docs" / "src" / "guide" / "idioms.md",
    ROOT / "docs" / "src" / "internals" / "implementation-map.md",
    ROOT / "docs" / "src" / "library" / "overview.md",
    ROOT / "agents" / "x2c-philosophy.md",
}
WORKFLOW_AUDIT = {
    ROOT / "README.md",
    ROOT / "AGENTS.md",
    ROOT / "agents" / "AGENTS.md",
    ROOT / "agents" / "quick-start.md",
    ROOT / "docs" / "src" / "internals" / "architecture.md",
    ROOT / "agents" / "x2c-debugging-guide.md",
    ROOT / "agents" / "x2c-development-guide.md",
    ROOT / "docs" / "src" / "reference" / "language.md",
    ROOT / "docs" / "src" / "guide" / "idioms.md",
    ROOT / "docs" / "src" / "internals" / "implementation-map.md",
    ROOT / "docs" / "src" / "library" / "overview.md",
}
EXAMPLE_AUDIT = {
    ROOT / "docs" / "src" / "reference" / "language.md",
    ROOT / "docs" / "src" / "guide" / "idioms.md",
    ROOT / "docs" / "src" / "internals" / "implementation-map.md",
    ROOT / "docs" / "src" / "library" / "overview.md",
}
PATH_PATTERN = re.compile(
    r"`((?:src|lib|docs|agents|plans|tools|unittest|examples|etc|packages|site)"
    r"/[^`\s]+)`"
)
# The project is named "x2c" only. It is pronounced like a certain drug, and
# voice-to-text keeps introducing that spelling; it must never reach the tree.
BANNED_NAME_PATTERN = re.compile(r"\becstas(?:y|ies)\b", re.IGNORECASE)
LINK_PATTERN = re.compile(r"!?\[[^]]*\]\(([^)]+)\)")
FLAG_PATTERN = re.compile(r"(?<![a-zA-Z0-9-])--[a-zA-Z][a-zA-Z0-9-]*")
EXAMPLE_PATTERN = re.compile(r"`(examples/([a-zA-Z0-9_/-]+)\.x)`")
MODULE_COUNT_PATTERN = re.compile(
    r"\b(\d+|sixteen|eighteen|twenty)([ -]\w+)*[ -]modules\b"
)
MODULE_COUNT_WORDS = {"sixteen": 16, "eighteen": 18, "twenty": 20}
SRC_MODULE_LISTS = {
    ROOT / "AGENTS.md": ("- `src/` - the compiler", "- `lib/` -"),
    ROOT / "docs" / "src" / "internals" / "architecture.md": (
        "Gathered in one place, for the 27 modules under `src/`:",
        "## The runtime boundary",
    ),
}


def location(path: pathlib.Path, text: str, offset: int) -> str:
    line = text.count("\n", 0, offset) + 1
    return f"{path.relative_to(ROOT)}:{line}"


def clean_repo_path(raw: str) -> str:
    value = raw.rstrip(".,;:)")
    value = re.sub(r":\d+(?:-\d+)?$", "", value)
    return value


def check_links(errors: list[str]) -> None:
    for path in DOCS:
        text = path.read_text(encoding="utf-8")
        for match in LINK_PATTERN.finditer(text):
            target = match.group(1).strip().strip("<>").split()[0]
            if not target or target.startswith(("#", "http://", "https://")):
                continue
            target = target.split("#", 1)[0]
            resolved = (path.parent / target).resolve()
            if not resolved.exists():
                where = location(path, text, match.start())
                errors.append(f"{where}: missing link {target}")


def check_paths(errors: list[str]) -> None:
    for path in sorted(PATH_AUDIT):
        text = path.read_text(encoding="utf-8")
        for match in PATH_PATTERN.finditer(text):
            raw = clean_repo_path(match.group(1))
            if any(char in raw for char in "*?[<"):
                continue
            resolved = ROOT / raw
            if not resolved.exists():
                if any(
                    resolved == generated or generated in resolved.parents
                    for generated in GENERATED_PATHS
                ):
                    continue
                where = location(path, text, match.start())
                errors.append(f"{where}: missing path {raw}")


def compiler_options() -> set[str]:
    source = (ROOT / "src" / "cli.x").read_text(encoding="ascii")
    table = source.split("static CliOption cli_options[] = {", 1)[1]
    table = table.split("\n};", 1)[0]
    return set(FLAG_PATTERN.findall(table))


def check_flags(errors: list[str]) -> None:
    valid = compiler_options()
    for path in FLAG_AUDIT:
        text = path.read_text(encoding="utf-8")
        for match in FLAG_PATTERN.finditer(text):
            flag = match.group(0)
            if flag not in valid:
                where = location(path, text, match.start())
                errors.append(f"{where}: unknown flag {flag}")


def check_workflows(errors: list[str]) -> None:
    for path in WORKFLOW_AUDIT:
        text = path.read_text(encoding="utf-8")
        offset = text.find("OVERVIEW.md")
        if offset >= 0:
            where = location(path, text, offset)
            errors.append(f"{where}: missing OVERVIEW.md entry page")
        match = re.search(r"make build-safe[^\n]*\bV=1\b", text)
        if match:
            where = location(path, text, match.start())
            errors.append(f"{where}: unsupported V=1 workflow")
        match = re.search(r"\bcc\s+-I\s+include\b", text)
        if match:
            where = location(path, text, match.start())
            errors.append(
                f"{where}: use -iquote include so runtime headers do not "
                "shadow system headers"
            )
        lines = text.splitlines()
        for index, line in enumerate(lines):
            redirect_parts = ("make build-safe", "debug/", ">")
            if not all(part in line for part in redirect_parts):
                continue
            if "mkdir -p debug" in line:
                continue
            prior = "\n".join(lines[max(0, index - 3):index])
            if "mkdir -p debug" not in prior:
                errors.append(
                    f"{path.relative_to(ROOT)}:{index + 1}: create debug/ "
                    "before redirecting bootstrap output"
                )


def example_manifest() -> dict[str, tuple[str, str]]:
    result: dict[str, tuple[str, str]] = {}
    path = ROOT / "examples" / "manifest.txt"
    for line in path.read_text(encoding="ascii").splitlines():
        if not line or line.startswith("#"):
            continue
        name, category, action, *_ = line.split("|")
        result[name] = (category, action)
    return result


def check_example_claims(errors: list[str]) -> None:
    manifest = example_manifest()
    for path in sorted(EXAMPLE_AUDIT):
        text = path.read_text(encoding="utf-8")
        for match in EXAMPLE_PATTERN.finditer(text):
            raw, name = match.groups()
            if name not in manifest:
                where = location(path, text, match.start())
                errors.append(f"{where}: unclassified example {raw}")
                continue
            category, action = manifest[name]
            if action in {"run", "build"}:
                continue
            marker = f"({category.replace('-', ' ')})"
            after = text[match.end():match.end() + len(marker) + 1]
            if not after.lstrip().startswith(marker):
                where = location(path, text, match.start())
                errors.append(
                    f"{where}: {raw} is {category}, not checked; "
                    f"label it {marker}"
                )


def check_module_counts(errors: list[str]) -> None:
    src_count = len(list((ROOT / "src").glob("*.x")))
    lib_count = len([p for p in (ROOT / "lib").glob("*.x")
                      if p.name != "x2c.x"])
    for path in DOCS:
        text = path.read_text(encoding="utf-8")
        for match in MODULE_COUNT_PATTERN.finditer(text):
            raw = match.group(1)
            count = MODULE_COUNT_WORDS.get(raw)
            if count is None:
                count = int(raw)
            window_start = max(0, match.start() - 40)
            context = text[window_start:match.start()].lower()
            if "runtime" in context:
                expected = lib_count
            else:
                expected = src_count
            if count != expected:
                where = location(path, text, match.start())
                errors.append(
                    f"{where}: '{match.group(0)}' says {count} but "
                    f"expected {expected}"
                )
    expected_names = {path.stem for path in (ROOT / "src").glob("*.x")}
    for path, (start_marker, end_marker) in SRC_MODULE_LISTS.items():
        text = path.read_text(encoding="utf-8")
        start = text.index(start_marker)
        end = text.index(end_marker, start)
        section = text[start:end]
        listed = set()
        for raw in re.findall(r"`([^`]+)`", section):
            match = re.fullmatch(r"(?:src/)?([a-z][a-z0-9-]*)(?:\.x)?", raw)
            if match:
                listed.add(match.group(1))
        missing = sorted(expected_names - listed)
        extra = sorted(listed - expected_names - {"src"})
        if missing or extra:
            where = location(path, text, start)
            errors.append(
                f"{where}: src module list differs from src/*.x; "
                f"missing={missing}, extra={extra}"
            )


LEDGER_ROW_PATTERN = re.compile(r"^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|", re.MULTILINE)


def ledger_rows(text: str) -> list[tuple[str, str]]:
    ledger_start = text.index("## Contract ledger")
    verified_start = text.index("## Verified contracts")
    ledger_text = text[ledger_start:verified_start]
    rows = []
    for name, status in LEDGER_ROW_PATTERN.findall(ledger_text):
        if name in ("Contract", "---"):
            continue
        rows.append((re.sub(r"`", "", name), status))
    return rows


def check_ledger_placement(errors: list[str]) -> None:
    path = ROOT / "agents" / "x2c-philosophy.md"
    text = path.read_text(encoding="utf-8")
    rows = ledger_rows(text)
    partial_start = text.index("## Partial contracts and open decisions")
    working_start = text.index("## Working rules")
    partial_text = text[partial_start:working_start]
    sections = re.split(r"(?m)^### ", partial_text)[1:]
    for section in sections:
        heading, body = section.split("\n", 1)
        heading = heading.strip()
        full = re.sub(r"\s+", " ", (heading + " " + body).lower())
        full = full.replace("**", "")
        hits = [
            status for name, status in rows
            if re.sub(r"\s+", " ", name.lower()) in full
        ]
        if not any(status != "verified" for status in hits):
            where = f"{path.relative_to(ROOT)}:section '{heading}'"
            errors.append(
                f"{where}: no non-verified ledger row found for this "
                "'Partial contracts' section; move it under 'Verified "
                "contracts' or name its open ledger row"
            )


def check_catalog(errors: list[str]) -> None:
    result = subprocess.run(
        [sys.executable, "tools/gen-module-catalog.py", "--check"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        errors.append(f"module catalog is stale\n{detail}")


def check_banned_name(errors: list[str]) -> None:
    for path in DOCS:
        text = path.read_text(encoding="utf-8")
        for match in BANNED_NAME_PATTERN.finditer(text):
            where = location(path, text, match.start())
            errors.append(
                f"{where}: the project is named x2c; do not spell out the "
                "word it is pronounced like"
            )


def check_api_reference(errors: list[str]) -> None:
    result = subprocess.run(
        [sys.executable, "tools/gen-api-reference.py", "--check"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        errors.append(f"library reference is stale\n{detail}")


def check_summary(errors: list[str]) -> None:
    """Every book page is reachable from SUMMARY.md, and every entry exists."""
    summary = BOOK_SRC / "SUMMARY.md"
    text = summary.read_text(encoding="utf-8")
    listed: set[pathlib.Path] = set()
    for match in LINK_PATTERN.finditer(text):
        target = match.group(1).strip().split("#", 1)[0]
        if not target or target.startswith(("http://", "https://")):
            continue
        resolved = (BOOK_SRC / target).resolve()
        listed.add(resolved)
        if not resolved.exists():
            where = location(summary, text, match.start())
            errors.append(f"{where}: SUMMARY.md entry has no file {target}")
    for path in sorted(BOOK_SRC.rglob("*.md")):
        if path == summary or path.resolve() in listed:
            continue
        rel = path.relative_to(ROOT)
        errors.append(f"{rel}: page is not reachable from docs/src/SUMMARY.md")


def main() -> int:
    errors: list[str] = []
    check_catalog(errors)
    check_api_reference(errors)
    check_summary(errors)
    check_banned_name(errors)
    check_links(errors)
    check_paths(errors)
    check_flags(errors)
    check_workflows(errors)
    check_example_claims(errors)
    check_module_counts(errors)
    check_ledger_placement(errors)
    if errors:
        print("documentation audit failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(
        f"documentation audit passed: {len(DOCS)} files, "
        f"{len(PATH_AUDIT)} path-audited entry points"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
