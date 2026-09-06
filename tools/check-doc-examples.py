#!/usr/bin/env python3
"""Compile every x2c code sample in the book and the website.

A fenced block tagged ``x2c`` must translate with the current stage-0
compiler. A block that cannot compile must be tagged ``x2c,ignore`` and be
preceded by an ``<!-- ignore: reason -->`` comment, so that an unverifiable
sample is a deliberate, explained exception rather than a silent one.

Each sample is tried twice: once as written, in case it is a set of file-scope
declarations, and once wrapped in a ``main`` function, in case it is a sequence
of statements. Only a sample that fails both ways is an error.
"""

from __future__ import annotations

import concurrent.futures
import os
import pathlib
import re
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
# The book and the website's long-form pages both carry x2c samples, and a
# page that moves between them must not lose its gate. The site's prose and
# carousel slides are under src/content because Astro would otherwise route
# each one as its own page; they carry samples for the same reason.
SOURCES = (
    ROOT / "docs" / "src",
    ROOT / "site" / "src" / "pages",
    ROOT / "site" / "src" / "content",
)
COMPILER = ROOT / "builds" / "0" / "x2c"
CC = os.environ.get("CC", "cc")
# Package examples use the same prepared dependency headers as package builds.
PACKAGE_HEADERS = [
    flag
    for path in sorted((ROOT / "packages").glob("*/deps/include"))
    for flag in ("--c-system-dir", str(path))
]
FENCE_PATTERN = re.compile(
    r"^(?P<indent>[ \t]*)```(?P<info>[^\n]*)\n"
    r"(?P<body>.*?)"
    r"^(?P=indent)```[ \t]*$",
    re.DOTALL | re.MULTILINE,
)
IGNORE_REASON_PATTERN = re.compile(r"<!--\s*ignore:\s*\S+.*?-->", re.DOTALL)
MAIN_PATTERN = re.compile(r"\bmain\s*\(")


def jobs() -> int:
    return int(os.environ.get("JOBS") or os.cpu_count() or 1)


class Sample:
    def __init__(self, path: pathlib.Path, line: int, code: str) -> None:
        self.path = path
        self.line = line
        self.code = code

    @property
    def where(self) -> str:
        return f"{self.path.relative_to(ROOT)}:{self.line}"


def dedent(body: str, indent: str) -> str:
    if not indent:
        return body
    lines = []
    for line in body.splitlines():
        lines.append(line[len(indent):] if line.startswith(indent) else line)
    return "\n".join(lines) + "\n"


def reveal_hidden(code: str) -> str:
    """Drop the "~" hidden-line prefix that book.toml hides from readers."""
    lines = []
    for line in code.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("~"):
            indent = line[: len(line) - len(stripped)]
            lines.append(indent + stripped[1:])
        else:
            lines.append(line)
    return "\n".join(lines) + "\n"


def as_program(code: str) -> str:
    return code


def wrapped_in_main(code: str) -> str:
    body = "\n".join(f"  {line}" if line.strip() else line
                     for line in code.splitlines())
    return (
        "int main(int argc, char **argv) {\n"
        f"{body}\n"
        "  return 0;\n"
        "}\n"
    )


def translate(source: str, workdir: pathlib.Path) -> tuple[bool, str]:
    """Compile without linking through the driver's normal package handling.

    Translation alone cannot catch missing C declarations. The build driver
    supplies imported packages' generated headers to the native compiler.
    """
    path = workdir / "sample.x"
    path.write_text(source, encoding="utf-8")
    result = subprocess.run(
        [
            str(COMPILER), "build", "--compile-only", "--cc", CC,
            "--package-dir", str(ROOT / "packages"), *PACKAGE_HEADERS,
            "--build-dir", str(workdir / "build"),
            "--output", str(workdir / "sample.o"), str(path),
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        return False, f"x2c: {detail}"
    return True, ""


def check_sample(sample: Sample) -> str | None:
    candidates = [("as written", as_program(sample.code))]
    if not MAIN_PATTERN.search(sample.code):
        candidates.append(("wrapped in main", wrapped_in_main(sample.code)))
    failures = []
    for label, source in candidates:
        with tempfile.TemporaryDirectory() as tmp:
            ok, detail = translate(source, pathlib.Path(tmp))
        if ok:
            return None
        failures.append(f"    {label}: {detail}")
    tried = " and ".join(label for label, _ in candidates)
    return (
        f"{sample.where}: x2c sample does not compile (tried {tried}); "
        "fix it, or tag it `x2c,ignore` with an <!-- ignore: reason --> "
        "comment above the fence\n" + "\n".join(failures)
    )


def collect(path: pathlib.Path, errors: list[str]) -> list[Sample]:
    text = path.read_text(encoding="utf-8")
    samples: list[Sample] = []
    for match in FENCE_PATTERN.finditer(text):
        tokens = [t.strip() for t in match.group("info").split(",")]
        if not tokens or tokens[0] != "x2c":
            continue
        line = text.count("\n", 0, match.start()) + 1
        code = reveal_hidden(dedent(match.group("body"), match.group("indent")))
        if "ignore" in tokens[1:]:
            prior = text[max(0, match.start() - 400):match.start()]
            if not IGNORE_REASON_PATTERN.search(prior):
                errors.append(
                    f"{path.relative_to(ROOT)}:{line}: `x2c,ignore` needs an "
                    "<!-- ignore: reason --> comment above the fence"
                )
            continue
        if not code.strip():
            continue
        samples.append(Sample(path, line, code))
    return samples


def main() -> int:
    if not COMPILER.exists():
        print(
            f"{COMPILER.relative_to(ROOT)} is missing; run 'make build' first",
            file=sys.stderr,
        )
        return 1
    errors: list[str] = []
    samples: list[Sample] = []
    for source in SOURCES:
        for path in sorted(source.rglob("*.md")):
            samples.extend(collect(path, errors))
    # Each sample is an independent pair of subprocesses, so the pool is bound
    # by the machine, not by Python. map keeps the report in document order.
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs()) as pool:
        errors.extend(e for e in pool.map(check_sample, samples) if e)
    if errors:
        print("doc example check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"doc example check passed: {len(samples)} x2c samples compiled")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
