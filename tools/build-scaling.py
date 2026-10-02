#!/usr/bin/env python3
"""Score sequential stage-build CPU seconds per authored source line.

Three sequential stage builds are timed through their waited `make` process
trees, then the median CPU time is divided by authored source lines. The JSON
record on the final output line is consumed by tools/performance-snapshot.py.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import statistics
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "unittest/benchmarks/build-scaling-baseline.json"
METRIC_ID = "child-cpu-seconds-per-authored-line/v1"
GENERATED = {Path("src/linked-meta.x"), Path("lib/x2c.x")}
SOURCE_SUFFIXES = {".x", ".xmacro", ".xlisp"}


def extract(work: Path, commit: str) -> Path:
  archive = subprocess.run(
    ["git", "archive", commit], cwd=ROOT, check=True, stdout=subprocess.PIPE,
  ).stdout
  subprocess.run(["tar", "-x", "-C", str(work)], input=archive, check=True)
  return work


def source_lines(tree: Path) -> dict[str, int]:
  counts = {"authored_source_lines": 0, "generated_source_lines": 0}
  for directory in ("src", "lib"):
    for path in (tree / directory).iterdir():
      if path.suffix not in SOURCE_SUFFIXES:
        continue
      kind = (
        "generated_source_lines"
        if path.relative_to(tree) in GENERATED else "authored_source_lines"
      )
      counts[kind] += path.read_bytes().count(b"\n")
  counts["total_source_lines"] = sum(counts.values())
  return counts


def run_make(
  command: list[str], tree: Path, environment: dict[str, str],
) -> float:
  before = resource.getrusage(resource.RUSAGE_CHILDREN)
  subprocess.run(
    command, cwd=tree, env=environment, check=True,
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
  )
  after = resource.getrusage(resource.RUSAGE_CHILDREN)
  return after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime


def measure(tree: Path, compiler: Path) -> tuple[dict[str, int], float]:
  environment = os.environ.copy()
  for name in ("MAKEFLAGS", "MAKELEVEL", "MFLAGS"):
    environment.pop(name, None)
  environment["X2C_HOME"] = str(tree)
  seconds = []
  for sample in range(3):
    stage = tree / "builds" / str(10 + sample)
    stage.mkdir(parents=True)
    seconds.append(run_make([
      "make", "-s", "-j1", "-f", "../stage.mk", "-C", str(stage),
      f"X2C_COMPILER={compiler}", f"CC={environment.get('CC', 'cc')}",
    ], tree, environment))
  return source_lines(tree), statistics.median(seconds)


def provenance(compiler: Path, commit: str) -> dict[str, object]:
  digest = hashlib.sha256(compiler.read_bytes()).hexdigest()
  cc = os.environ.get("CC", "cc")
  version = subprocess.run(
    [*cc.split(), "--version"], capture_output=True, text=True, check=False,
  )
  return {
    "translator": str(compiler), "translator_sha256": digest,
    "cc": cc, "cc_version": (version.stdout or version.stderr).splitlines()[0]
    if version.returncode == 0 and (version.stdout or version.stderr)
    else None,
    "platform": platform.platform(), "machine": platform.machine(),
    "build_mode": os.environ.get("BUILD_MODE") or subprocess.run(
      ["git", "show", f"{commit}:etc/build-mode"], cwd=ROOT,
      check=True, stdout=subprocess.PIPE, text=True,
    ).stdout.strip(),
    "build_lto": os.environ.get("BUILD_LTO", "0"),
    "environment": {name: os.environ[name] for name in (
      "BUILD_CFLAGS", "BUILD_LDFLAGS", "EXTRA_CFLAGS", "X2C_FLAGS", "X2C_CC",
    ) if name in os.environ},
  }


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  parser.add_argument("--compiler", type=Path, default=ROOT / "builds/2/x2c")
  parser.add_argument("--ref", default="HEAD", metavar="COMMIT")
  parser.add_argument("--rebaseline", action="store_true")
  args = parser.parse_args()
  compiler = args.compiler.expanduser().resolve()
  commit = subprocess.run(
    ["git", "rev-parse", f"{args.ref}^{{commit}}"], cwd=ROOT,
    check=True, stdout=subprocess.PIPE, text=True,
  ).stdout.strip()
  tree_id = subprocess.run(
    ["git", "rev-parse", f"{commit}^{{tree}}"], cwd=ROOT,
    check=True, stdout=subprocess.PIPE, text=True,
  ).stdout.strip()
  baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
  legacy = ({
    "metric_id": baseline.get("metric_id", "driver-cycles-per-source-line/v0"),
    "baseline_id": baseline.get("baseline_id", "legacy-driver-cycles"),
    "commit": baseline.get("commit"),
    "cycles_per_line": baseline["cycles_per_line"],
  } if "cycles_per_line" in baseline else baseline.get("legacy"))
  if not args.rebaseline and baseline.get("metric_id") != METRIC_ID:
    old = baseline.get("metric_id", "legacy-driver-cycles/v0")
    raise ValueError(
      f"baseline uses {old}; explicitly rebaseline for {METRIC_ID}",
    )

  with tempfile.TemporaryDirectory(prefix="x2c-build-scaling-") as work:
    counts, seconds = measure(extract(Path(work), commit), compiler)
  authored = counts["authored_source_lines"]
  per_line = seconds / authored
  baseline_id = baseline.get("baseline_id") or (
    f"legacy-driver-cycles:{baseline['commit']}"
  )
  if args.rebaseline:
    calibration = (
      f"{METRIC_ID}:{commit}:{tree_id}:{per_line:.12g}"
    ).encode("utf-8")
    baseline_id = f"{METRIC_ID}:{hashlib.sha256(calibration).hexdigest()[:12]}"
    baseline = {
      "metric_id": METRIC_ID, "baseline_id": baseline_id,
      "commit": commit, "tree": tree_id, **counts,
      "cpu_seconds": seconds,
      "cpu_seconds_per_authored_line": per_line,
      "provenance": provenance(compiler, commit),
    }
    if legacy:
      baseline["legacy"] = legacy
    BASELINE.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")
  record = {
    "metric_id": METRIC_ID, "baseline_id": baseline_id,
    "score": 100 * per_line / baseline["cpu_seconds_per_authored_line"],
    "cpu_seconds": seconds, "cpu_seconds_per_authored_line": per_line,
    **counts, "baseline_commit": baseline["commit"],
    "provenance": provenance(compiler, commit),
  }
  print(
    f"build cost score: {record['score']:.1f} "
    f"(100 = {baseline['commit'][:8]})",
  )
  print(json.dumps(record, sort_keys=True))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
