#!/usr/bin/env python3
"""Split one stage build into size-normalized translation and C costs.

A stage build translates lib/ and src/ in two serial batches and then
compiles the generated C. Translation cost follows source size and C cost
follows generated C size, so the tool reports each as a rate against its own
size. It also translates a pinned tree with the same compiler; that workload
never changes, so its time moves only when the compiler's speed does.

  tools/build-scaling.py                 # measure HEAD and the pin
  tools/build-scaling.py --pin COMMIT    # measure against another pin

The last output line is one JSON object for tools/performance-snapshot.py.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
PIN_FILE = ROOT / "unittest/benchmarks/build-scaling-pin"
SOURCE_SUFFIXES = {".x", ".xmacro", ".xlisp"}
CC_WRAPPER = """#!/bin/sh
start=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
"${REAL_CC:-cc}" "$@"
status=$?
finish=$(perl -MTime::HiRes=time -e 'printf "%.6f", time')
case " $* " in *" -c "*) echo "$start $finish" >> "$CC_LOG";; esac
exit $status
"""


def extract(work: Path, commit: str, name: str) -> Path:
  tree = work / name
  tree.mkdir()
  archive = subprocess.run(
    ["git", "archive", commit, "src", "lib", "etc", "include",
     "builds/stage.mk"],
    cwd=ROOT, check=True, stdout=subprocess.PIPE,
  ).stdout
  subprocess.run(["tar", "-x", "-C", str(tree)], input=archive, check=True)
  return tree


def source_size(tree: Path) -> dict[str, int]:
  files = lines = size = 0
  for directory in ("src", "lib"):
    for path in sorted((tree / directory).iterdir()):
      if path.suffix not in SOURCE_SUFFIXES or path.name == "x2c.x":
        continue
      data = path.read_bytes()
      files += path.suffix == ".x"
      lines += data.count(b"\n")
      size += len(data)
  return {"units": files, "source_lines": lines, "source_bytes": size}


def make(tree: Path, compiler: Path, *targets: str, **env: str) -> float:
  environment = os.environ.copy()
  for name in ("MAKEFLAGS", "MAKELEVEL", "MFLAGS"):
    environment.pop(name, None)
  environment.update(env, X2C_HOME=str(tree))
  start = time.monotonic()
  subprocess.run(
    ["make", "-j1", "-f", "../stage.mk", "-C", str(tree / "builds/9"),
     f"X2C_COMPILER={compiler}", *targets],
    env=environment, check=True,
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
  )
  return time.monotonic() - start


def translate(tree: Path, compiler: Path) -> tuple[float, float]:
  stage = tree / "builds/9"
  shutil.rmtree(stage, ignore_errors=True)
  stage.mkdir(parents=True)
  lib = make(tree, compiler, "lib/.translated")
  src = make(tree, compiler, "src/.translated")
  return lib, src


def measure_translation(
  tree: Path, compiler: Path, samples: int,
) -> dict[str, float]:
  runs = [translate(tree, compiler) for _ in range(samples)]
  lib = statistics.median(run[0] for run in runs)
  src = statistics.median(run[1] for run in runs)
  return {"lib_seconds": lib, "src_seconds": src, "seconds": lib + src}


def measure_compile(tree: Path, compiler: Path) -> dict[str, float]:
  stage = tree / "builds/9"
  wrapper = tree / "cc-timed"
  wrapper.write_text(CC_WRAPPER, encoding="utf-8")
  wrapper.chmod(0o755)
  log = tree / "cc.log"
  make(
    tree, compiler, f"CC={wrapper}",
    REAL_CC=os.environ.get("CC", "cc"), CC_LOG=str(log),
  )
  spans = [
    tuple(map(float, line.split()))
    for line in log.read_text(encoding="utf-8").splitlines()
  ]
  generated = sum(
    path.stat().st_size for directory in ("lib", "src")
    for path in (stage / directory).glob("*.c")
  )
  return {
    "cc_seconds": sum(finish - start for start, finish in spans),
    "cc_units": len(spans),
    "generated_c_bytes": generated,
  }


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  parser.add_argument(
    "--compiler", type=Path, default=ROOT / "builds/2/x2c",
    help="translator to measure (default: builds/2/x2c)",
  )
  parser.add_argument(
    "--pin", default=PIN_FILE.read_text(encoding="utf-8").strip(),
    help="commit whose tree is the fixed translation workload",
  )
  parser.add_argument("--samples", type=int, default=3)
  args = parser.parse_args()
  compiler = args.compiler.resolve()

  # Outside the checkout, the compiler cannot find this repository's
  # runtime in place of the tree's own.
  with tempfile.TemporaryDirectory(prefix="x2c-build-scaling-") as work:
    current = extract(Path(work), "HEAD", "current")
    record: dict[str, object] = {"pin": args.pin, **source_size(current)}
    record.update(measure_translation(current, compiler, args.samples))
    record.update(measure_compile(current, compiler))
    pinned = extract(Path(work), args.pin, "pinned")
    record["pinned_seconds"] = measure_translation(
      pinned, compiler, args.samples,
    )["seconds"]

  record["translate_seconds_per_kline"] = (
    record["seconds"] / record["source_lines"] * 1000
  )
  record["cc_seconds_per_mb"] = (
    record["cc_seconds"] / record["generated_c_bytes"] * 1e6
  )
  record["c_bytes_per_line"] = (
    record["generated_c_bytes"] / record["source_lines"]
  )
  for key, value in record.items():
    print(f"{key}: {value:.6g}" if isinstance(value, float)
          else f"{key}: {value}")
  print(json.dumps(record, sort_keys=True))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
