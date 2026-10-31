#!/usr/bin/env python3
"""Compare c2x2c counting, merging, and parallel API costs with native C."""

from __future__ import annotations

import argparse
from collections import Counter
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import statistics
import string
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent


def digest(path: Path) -> str:
  return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(source: Path, destination: Path) -> list[Path]:
  """Follow file links, but skip child directory links, like Path.walk."""
  destination.mkdir()
  files = []
  for folder, directories, names in os.walk(source, followlinks=False):
    (destination / Path(folder).relative_to(source)).mkdir(parents=True, exist_ok=True)
    directories.sort()
    for name in sorted(names):
      path = Path(folder) / name
      if path.is_file():
        target = destination / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        files.append(target)
  return files


def frequencies(files: list[Path]) -> Counter:
  counts = Counter()
  for path in files:
    counts.update(path.read_bytes().translate(None, string.punctuation.encode())
                  .lower().split())
  return counts


def check_output(path: Path, counts: Counter, version: int) -> None:
  pairs = [(count, word) for word, count in counts.items()]
  expected = (sorted(pairs, key=lambda pair: (-pair[0], pair[1]))[:10]
              if version <= 2 else sorted(pairs)[-10:])
  actual = []
  for line in path.read_bytes().splitlines():
    count, word = line.split(b"\t", 1)
    actual.append((int(count), word))
  if actual != expected:
    raise RuntimeError(f"incorrect top ten: {path}")


def measure(command: list[str], folder: Path, environment: dict) -> dict:
  folder.mkdir()
  with (folder / "stdout").open("wb") as out, \
       (folder / "stderr").open("wb") as err:
    start = time.perf_counter()
    child = subprocess.Popen(command, stdout=out, stderr=err, env=environment)
    _, status, usage = os.wait4(child.pid, 0)
    wall = time.perf_counter() - start
    child.returncode = os.waitstatus_to_exitcode(status)
  if child.returncode:
    raise RuntimeError(f"command failed ({child.returncode}): {folder / 'stderr'}")
  rss_bytes = usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024)
  return {"command": command, "stdout": str(folder / "stdout"),
          "cpu_s": usage.ru_utime + usage.ru_stime, "wall_s": wall,
          "peak_rss_mib": rss_bytes / 1048576}


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--compiler", type=Path, default=ROOT / "builds/0/x2c")
  parser.add_argument("--runtime", type=Path, default=ROOT / "builds/0/libx2c.a",
                      help="runtime archive compatible with the compiler's headers")
  parser.add_argument("--file", type=Path, default=ROOT / "site/public/llms-full.txt")
  parser.add_argument("--directory", type=Path, default=ROOT / "docs")
  parser.add_argument("--samples", type=int, default=5)
  parser.add_argument("--all-versions", action="store_true")
  parser.add_argument("--output-dir", type=Path)
  args = parser.parse_args()
  if args.samples < 1:
    parser.error("--samples must be positive")
  compiler, runtime = args.compiler.resolve(), args.runtime.resolve()
  file, directory = args.file.resolve(), args.directory.resolve()
  if not file.is_file() or not directory.is_dir():
    parser.error("--file must name a file and --directory must name a directory")
  stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
  output = (args.output_dir or ROOT / "unittest/build/benchmarks/c2x2c" / stamp).resolve()
  if output.is_relative_to(directory):
    parser.error("--output-dir must be outside --directory")
  output.mkdir(parents=True, exist_ok=False)
  inputs = output / "inputs"
  inputs.mkdir()
  shutil.copyfile(file, inputs / "file.txt")
  files = snapshot(directory, inputs / "directory")
  if not files:
    parser.error("--directory has no readable files")
  corpora = {"file": [inputs / "file.txt"], "directory": files}
  expected = {name: frequencies(paths) for name, paths in corpora.items()}
  generated = output / "generated"
  generated.mkdir()
  cc = shlex.split(os.environ.get("CC", "cc"))
  flags = [*cc, "-O2", "-DNDEBUG", "-fsigned-char", "-pthread",
           "-iquote", str(generated), "-iquote", str(ROOT / "include/x2c"),
           "-I", str(ROOT / "examples/c2x2c")]
  versions = list(range(1, 9)) if args.all_versions else [4, 6, 8]
  binaries = {}
  commands = []
  state = {"metric_id": "c2x2c-child-cpu-over-native-c/v1", "status": "building",
           "samples": [], "build_commands": commands,
           "compiler_sha256": digest(compiler), "runtime_sha256": digest(runtime),
           "source_commit": subprocess.check_output(
             ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
           "source_sha256": {str(path.relative_to(ROOT)): digest(path)
                             for path in [Path(__file__).resolve(),
                                          *sorted((ROOT / "examples/c2x2c").glob("*.x")),
                                          *sorted((ROOT / "examples/c2x2c").glob("*.c")),
                                          ROOT / "examples/c2x2c/bench-directory.sh"]},
           "platform": platform.platform(), "flags": flags,
           "environment": {"LC_ALL": "C", "X2C_SCOPE_ACCOUNTING": None,
                           **{name: os.environ[name] for name in
                              ["MallocNanoZone", "MallocStackLogging",
                               "DYLD_INSERT_LIBRARIES", "LD_PRELOAD", "GLIBC_TUNABLES"]
                              if name in os.environ}},
           "cc_version": subprocess.check_output([*cc, "--version"], text=True).splitlines()[0],
           "inputs": {name: {"files": len(paths), "bytes": sum(p.stat().st_size for p in paths),
                              "sha256": {str(p.relative_to(inputs)): digest(p) for p in paths}}
                      for name, paths in corpora.items()}}

  def save() -> None:
    (output / "results.json").write_text(json.dumps(state, indent=2) + "\n")

  def build(command: list[str]) -> None:
    commands.append(command)
    with (output / "build.log").open("a") as log:
      subprocess.run(command, check=True, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)

  save()
  try:
    tutorial = ROOT / "examples/c2x2c"
    for label, source in [("c", "words-v0.c"), ("c-aggregate", "words-v0-aggregate.c")]:
      binary = output / label
      build([*flags, str(tutorial / source), "-o", str(binary)])
      binaries[label] = str(binary)
    for version in versions:
      sources = [tutorial / f"words-v{version}.x"]
      if version == 8:
        sources.append(tutorial / "frequencies.x")
      build([str(compiler), "translate", "-I", str(ROOT / "lib"),
             "-I", str(tutorial), "--out-dir", str(generated), *map(str, sources)])
      binary = output / f"v{version}"
      build([*flags, *[str(generated / (source.stem + ".c")) for source in sources],
             str(runtime), "-lm", "-o", str(binary)])
      binaries[str(version)] = str(binary)
    state["binaries"] = {name: {"path": path, "sha256": digest(Path(path))}
                         for name, path in binaries.items()}
    state["status"] = "running"
    save()
    environment = os.environ.copy()
    environment["LC_ALL"] = "C"
    environment.pop("X2C_SCOPE_ACCOUNTING", None)
    for sample in range(args.samples):
      for workload in corpora:
        cohort = [0, *[v for v in versions if workload == "file" or v >= 6]]
        shift = sample % len(cohort)
        cohort = cohort[shift:] + cohort[:shift]
        if sample % 2:
          cohort.reverse()
        for version in cohort:
          argument = str(inputs / ("file.txt" if workload == "file" else "directory"))
          if version:
            command = [binaries[str(version)], argument]
          elif workload == "file":
            command = [binaries["c"], argument]
          else:
            command = [str(tutorial / "bench-directory.sh"), "aggregate",
                       binaries["c-aggregate"], argument]
          folder = output / f"{workload}-{sample + 1}-v{version}"
          result = measure(command, folder, environment)
          check_output(folder / "stdout", expected[workload], version)
          result.update(workload=workload, version=version, sample=sample + 1,
                        oracle_top10_match=True)
          state["samples"].append(result)
          save()
    summaries = []
    for workload in corpora:
      rows = [row for row in state["samples"] if row["workload"] == workload]
      baseline = statistics.median(row["cpu_s"] for row in rows if row["version"] == 0)
      baseline_wall = statistics.median(row["wall_s"] for row in rows if row["version"] == 0)
      for version in sorted({row["version"] for row in rows}):
        selected = [row for row in rows if row["version"] == version]
        summary = {"workload": workload, "version": version,
                   **{key: statistics.median(row[key] for row in selected)
                      for key in ["cpu_s", "wall_s", "peak_rss_mib"]}}
        summary["cpu_score"] = summary["cpu_s"] / baseline
        summary["wall_ratio"] = summary["wall_s"] / baseline_wall
        summaries.append(summary)
    state.update(status="complete", summary=summaries)
    save()
    print("workload,version,cpu_ms,wall_ms,peak_rss_mib,cpu_score,wall_ratio")
    for row in summaries:
      print(f"{row['workload']},V{row['version']},{row['cpu_s'] * 1000:.3f},"
            f"{row['wall_s'] * 1000:.3f},{row['peak_rss_mib']:.2f},"
            f"{row['cpu_score']:.3f},{row['wall_ratio']:.3f}")
    print(f"Results: {output / 'results.json'}")
    return 0
  except BaseException as error:
    state.update(status="failed", failure=str(error))
    save()
    raise


if __name__ == "__main__":
  raise SystemExit(main())
