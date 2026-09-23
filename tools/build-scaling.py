#!/usr/bin/env python3
"""Score the stage build's cost per line of source against a baseline.

One stage build translates lib/ and src/ and compiles the generated C. The
tool counts the CPU cycles that work takes in a copy of HEAD, divides by
the number of source lines, and reports a score: 100 is the recorded baseline, and 110
means each line of x2c costs 10% more to build. A larger code base leaves
the score unchanged; a slower translator, a slower C compile, or more
generated C per line raises it.

  tools/build-scaling.py                # score HEAD
  tools/build-scaling.py --rebaseline   # make HEAD's cost the new 100

Cycles, from macOS `/usr/bin/time -l`, include memory stalls and ignore
time spent waiting for other work on the host. The median of three builds
varies by about 4% under heavy load, where wall time varies by 20%. A new C
compiler changes the count, so rebaseline after a toolchain upgrade.
The last output line is one JSON object for tools/performance-snapshot.py.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "unittest/benchmarks/build-scaling-baseline.json"
SOURCE_SUFFIXES = {".x", ".xmacro", ".xlisp"}
# `time` counts only its own child, so each translator and C compiler
# process is counted separately. The build runs silently; the count files
# also receive the tools' diagnostics.
COUNTED = """#!/bin/sh
exec /usr/bin/time -l "$@" 2>"$(mktemp "$COUNT_DIR/count.XXXXXX")"
"""


def extract(work: Path) -> Path:
  archive = subprocess.run(
    ["git", "archive", "HEAD", "src", "lib", "etc", "include",
     "builds/stage.mk"],
    cwd=ROOT, check=True, stdout=subprocess.PIPE,
  ).stdout
  subprocess.run(["tar", "-x", "-C", str(work)], input=archive, check=True)
  return work


def source_lines(tree: Path) -> int:
  return sum(
    path.read_bytes().count(b"\n")
    for directory in ("src", "lib")
    for path in (tree / directory).iterdir()
    if path.suffix in SOURCE_SUFFIXES and path.name != "x2c.x"
  )


def build_cycles(tree: Path, compiler: Path, sample: int) -> int:
  stage = tree / "builds" / str(10 + sample)
  counts = stage / "counts"
  counts.mkdir(parents=True)
  wrapper = tree / "counted"
  wrapper.write_text(COUNTED, encoding="utf-8")
  wrapper.chmod(0o755)
  environment = os.environ.copy()
  for name in ("MAKEFLAGS", "MAKELEVEL", "MFLAGS"):
    environment.pop(name, None)
  environment.update(X2C_HOME=str(tree), COUNT_DIR=str(counts))
  subprocess.run(
    ["make", "-s", "-j1", "-f", "../stage.mk", "-C", str(stage),
     f"X2C_COMPILER={wrapper} {compiler}",
     f"CC={wrapper} {environment.get('CC', 'cc')}"],
    env=environment, check=True,
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
  )
  return sum(
    int(line.split()[0])
    for path in counts.iterdir()
    for line in path.read_text(encoding="utf-8").splitlines()
    if line.endswith("cycles elapsed")
  )


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  parser.add_argument(
    "--compiler", type=Path, default=ROOT / "builds/2/x2c",
    help="translator to measure (default: builds/2/x2c)",
  )
  parser.add_argument(
    "--rebaseline", action="store_true",
    help="record HEAD's cost as score 100",
  )
  args = parser.parse_args()
  compiler = args.compiler.resolve()

  # Outside the checkout, the compiler cannot find this repository's
  # runtime in place of the tree's own.
  with tempfile.TemporaryDirectory(prefix="x2c-build-scaling-") as work:
    tree = extract(Path(work))
    lines = source_lines(tree)
    cycles = statistics.median(
      build_cycles(tree, compiler, sample) for sample in range(3)
    )
  per_line = cycles / lines
  commit = subprocess.run(
    ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True,
    stdout=subprocess.PIPE, text=True,
  ).stdout.strip()
  if args.rebaseline:
    BASELINE.write_text(json.dumps(
      {"commit": commit, "cycles_per_line": per_line}, indent=2,
    ) + "\n", encoding="utf-8")
  baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
  record = {
    "score": 100 * per_line / baseline["cycles_per_line"],
    "cycles_per_line": per_line,
    "cycles": cycles,
    "source_lines": lines,
    "baseline_commit": baseline["commit"],
  }
  print(f"build cost score: {record['score']:.1f} "
        f"(100 = {baseline['commit'][:8]})")
  print(json.dumps(record, sort_keys=True))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
