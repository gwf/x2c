#!/usr/bin/env python3
"""Emit one record of static, build-free metrics for the current tree.

The record describes size and shape only. It does not decide that any number
is good or bad, and nothing in the build or test process consumes it. Its
purpose is to make change over time visible: run it at two commits and diff
the records.

The detailed record is derived from tracked files alone, so the same commit
always produces the same record on any machine. The concise summary measures
the current src/, lib/, unittest/, and examples/ files.

    tools/repo-metrics.py                 # human-readable table
    tools/repo-metrics.py --json          # one JSON object
    tools/repo-metrics.py --json > a.json # record a baseline
    tools/repo-metrics.py --summary       # concise source/test summary
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import pathlib
import re
import subprocess
import sys

from x2c_source import mask_non_code

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEST_REGISTRATION = re.compile(
    r"(?m)^\s*(?:\$test\.run|TestHarness_(?:run|skip))\s*\("
)
TEST_SUPPORT = {"test-all.x", "test-support.x"}
CYAN = "\033[36m"
BOLD = "\033[1m"
RESET = "\033[0m"


class Fatal(Exception):
    """A statistics input is missing or malformed."""


# Metric groups: (name, glob, what one "unit" means)
SOURCE_GROUPS = [
    ("compiler", "src/*.x", "module"),
    ("runtime", "lib/*.x", "module"),
    ("macros", "lib/*.xmacro", "macro file"),
    ("tests", "unittest/test-*.x", "suite"),
    ("examples", "examples/**/*.x", "example"),
    ("probes", "unittest/probes/*.sh", "probe"),
    ("benchmarks", "unittest/benchmarks/*.x", "benchmark"),
    ("tools", "tools/*.py", "tool"),
]

# The agent-facing instruction surface. Growth here adds reading for every
# session, so it is tracked next to the code it describes.
HARNESS_GROUPS = [
    ("instructions", "**/AGENTS.md", "file"),
    ("skills", "agents/skills/*/SKILL.md", "skill"),
    ("guides", "agents/*.md", "guide"),
    ("plans_active", "plans/*.md", "plan"),
    ("plans_archived", "plans/archive/*.md", "plan"),
]


def tracked() -> set[str]:
    out = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
    )
    return set(out.stdout.split())


def lines_of(path: pathlib.Path) -> int:
    try:
        with path.open("rb") as handle:
            return sum(1 for _ in handle)
    except OSError:
        return 0


def measure(groups, files: set[str]) -> dict:
    result = {}
    for name, pattern, _unit in groups:
        paths = sorted(
            p
            for p in ROOT.glob(pattern)
            if p.is_file() and str(p.relative_to(ROOT)) in files
        )
        result[name] = {
            "files": len(paths),
            "lines": sum(lines_of(p) for p in paths),
        }
    return result


def fixtures(files: set[str]) -> dict:
    """Compiler fixtures, split by what they pin.

    Golden generated-C and phase artifacts must be rebaselined by unrelated
    changes, so their weight is worth watching separately from the .x inputs
    and the observable-output expectations.
    """
    base = "unittest/compiler-fixtures/"
    inputs, golden, observable = [], [], []
    for rel in sorted(f for f in files if f.startswith(base)):
        path = ROOT / rel
        if not path.is_file():
            continue
        if rel.endswith(".x"):
            inputs.append(path)
        elif rel.endswith((".c", ".h", ".ast", ".transform", ".tokens")):
            golden.append(path)
        else:
            observable.append(path)
    return {
        "inputs": {"files": len(inputs), "lines": sum(lines_of(p) for p in inputs)},
        "golden": {"files": len(golden), "lines": sum(lines_of(p) for p in golden)},
        "observable": {
            "files": len(observable),
            "lines": sum(lines_of(p) for p in observable),
        },
    }


def make_targets() -> int:
    text = (ROOT / "Makefile").read_text(errors="replace")
    return sum(
        1
        for line in text.splitlines()
        if line and not line[0].isspace() and ":" in line.split("=")[0]
        and not line.startswith((".", "#"))
    )


def commit() -> dict:
    def run(*args):
        out = subprocess.run(
            args, cwd=ROOT, capture_output=True, text=True, check=False
        )
        return out.stdout.strip()

    dirty = run("git", "status", "--porcelain")
    return {
        "sha": run("git", "rev-parse", "HEAD"),
        "branch": run("git", "rev-parse", "--abbrev-ref", "HEAD"),
        "date": run("git", "log", "-1", "--format=%ad", "--date=short"),
        "dirty_files": len([ln for ln in dirty.splitlines() if ln]),
    }


def collect() -> dict:
    files = tracked()
    source = measure(SOURCE_GROUPS, files)
    harness = measure(HARNESS_GROUPS, files)
    return {
        "commit": commit(),
        "source": source,
        "fixtures": fixtures(files),
        "harness": harness,
        "totals": {
            "tracked_files": len(files),
            "make_targets": make_targets(),
            "source_lines": sum(g["lines"] for g in source.values()),
            "harness_lines": sum(g["lines"] for g in harness.values()),
        },
    }


def parse_cloc(output: str) -> dict[str, int]:
    """Return code and comment counts from cloc CSV output."""
    for row in csv.DictReader(output.splitlines()):
        if row.get("language") != "SUM":
            continue
        try:
            return {
                "code": int(row["code"]),
                "comments": int(row["comment"]),
            }
        except (KeyError, TypeError, ValueError) as error:
            raise Fatal("cloc returned a malformed summary row") from error
    raise Fatal("cloc returned no summary row")


def cloc_lines(paths: list[pathlib.Path]) -> dict[str, int]:
    """Count code and comments in paths with cloc's C rules."""
    command = ["cloc", "--force-lang=C", "--csv", "--quiet"]
    command.extend(str(path) for path in paths)
    try:
        result = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True, check=False
        )
    except FileNotFoundError as error:
        raise Fatal("cloc is required by 'make stats'") from error
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise Fatal(f"cloc failed: {detail or f'exit {result.returncode}'}")
    return parse_cloc(result.stdout)


def unit_tests(root: pathlib.Path = ROOT) -> int:
    """Count registered runnable and deliberately skipped unit tests."""
    count = 0
    for path in sorted((root / "unittest").glob("test-*.x")):
        if path.name in TEST_SUPPORT:
            continue
        source = path.read_text(encoding="utf-8")
        count += len(TEST_REGISTRATION.findall(mask_non_code(source)))
    return count


def compiler_fixtures(root: pathlib.Path = ROOT) -> int:
    """Count fixture manifests discovered by the compiler-fixture runner."""
    directory = root / "unittest" / "compiler-fixtures"
    return sum(1 for path in directory.glob("*.phases") if path.is_file())


def showcase_examples(root: pathlib.Path = ROOT) -> int:
    """Count examples classified as showcases in the curated manifest."""
    manifest = root / "examples" / "manifest.txt"
    count = 0
    for line in manifest.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) > 1 and fields[1] == "showcase":
            count += 1
    return count


def collect_summary(root: pathlib.Path = ROOT) -> dict:
    """Collect the concise source and executable-material inventory."""
    source = {
        name: cloc_lines(sorted((root / name).glob("*.x")))
        for name in ("src", "lib")
    }
    return {
        "source": source,
        "tests": {
            "unit_tests": unit_tests(root),
            "compiler_fixtures": compiler_fixtures(root),
            "showcase_examples": showcase_examples(root),
        },
    }


def color_enabled(mode: str, stream=sys.stdout, environ=os.environ) -> bool:
    """Resolve an explicit or automatic terminal colour choice."""
    if mode == "always":
        return True
    if mode == "never":
        return False
    return (
        stream.isatty()
        and environ.get("TERM") != "dumb"
        and "NO_COLOR" not in environ
    )


def _paint(text: str, tone: str, color: bool) -> str:
    return f"{tone}{text}{RESET}" if color else text


def render_summary(record: dict, color: bool) -> str:
    """Render the concise inventory, optionally with ANSI presentation."""
    source = record["source"]
    tests = record["tests"]
    code_total = sum(source[name]["code"] for name in ("src", "lib"))
    comment_total = sum(
        source[name]["comments"] for name in ("src", "lib")
    )
    lines = [
        f"{_paint('Source        ', CYAN, color)}  Code  Comments",
    ]
    for name in ("src", "lib"):
        label = _paint(f"{name}/".ljust(14), CYAN, color)
        lines.append(
            f"{label}{source[name]['code']:8,}{source[name]['comments']:10,}"
        )
    label = _paint("total".ljust(14), BOLD, color)
    lines.extend((
        f"{label}{code_total:8,}{comment_total:10,}",
        "",
        _paint("Tests and examples", CYAN, color),
        f"{'unit tests':20}{tests['unit_tests']:6,}",
        f"{'compiler fixtures':20}{tests['compiler_fixtures']:6,}",
        f"{'showcase examples':20}{tests['showcase_examples']:6,}",
    ))
    return "\n".join(lines)


def render(record: dict) -> str:
    out = []
    head = record["commit"]
    out.append(
        f"{head['sha'][:8]} on {head['branch']} ({head['date']})"
        + (f" +{head['dirty_files']} dirty" if head["dirty_files"] else "")
    )
    for section in ("source", "fixtures", "harness"):
        out.append(f"\n{section}")
        for name, value in record[section].items():
            out.append(f"  {name:16} {value['files']:5} files {value['lines']:8} lines")
    out.append("\ntotals")
    for name, value in record["totals"].items():
        out.append(f"  {name:16} {value:8}")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    output = parser.add_mutually_exclusive_group()
    output.add_argument(
        "--json", action="store_true", help="emit one detailed JSON object"
    )
    output.add_argument(
        "--summary", action="store_true", help="emit the concise summary"
    )
    parser.add_argument(
        "--color", choices=("auto", "always", "never"), default="auto",
        help="control summary colour (default: auto)",
    )
    args = parser.parse_args()
    if args.summary:
        try:
            record = collect_summary()
        except Fatal as error:
            print(f"repository statistics: {error}", file=sys.stderr)
            return 1
        print(render_summary(record, color_enabled(args.color)))
        return 0
    record = collect()
    if args.json:
        json.dump(record, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    else:
        print(render(record))
    return 0


if __name__ == "__main__":
    sys.exit(main())
