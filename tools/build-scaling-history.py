#!/usr/bin/env python3
"""Print the saved build cost score history, optionally scoring old commits.

  tools/build-scaling-history.py                    # print; builds nothing
  tools/build-scaling-history.py --replay C1 C2 ... # score unsaved commits

The series joins the nightly snapshot's history.jsonl with replay.csv, both
in the performance history directory, and prints CSV oldest first with the
newest commit at 100. A replay builds each commit that has no saved score:
its own stage 0 from the bootstrap, then three counted stage builds, a few
minutes per commit. Each result is appended to replay.csv, so no commit is
ever built twice.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
FIELDS = ("commit", "date", "source_lines", "cycles_per_line")


def load(name: str, file: str):
  spec = importlib.util.spec_from_file_location(name, HERE / file)
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)
  return module


scaling = load("build_scaling", "build-scaling.py")
snapshot = load("performance_snapshot", "performance-snapshot.py")


def commit_facts(commit: str) -> tuple[str, str, int]:
  """Returns the full hash, commit date, and commit time of `commit`."""
  full, date, stamp = subprocess.run(
    ["git", "log", "-1", "--format=%H %cs %ct", commit],
    cwd=scaling.ROOT, check=True, stdout=subprocess.PIPE, text=True,
  ).stdout.split()
  return full, date, int(stamp)


def saved(root: Path) -> dict[str, dict[str, object]]:
  """Returns saved scores by full commit hash; nightly rows win."""
  rows: dict[str, dict[str, object]] = {}
  replay = root / "replay.csv"
  if replay.exists():
    with replay.open(encoding="utf-8") as source:
      for row in csv.DictReader(source):
        rows[row["commit"]] = row
  history = root / "history.jsonl"
  if history.exists():
    for line in history.read_text(encoding="utf-8").splitlines():
      row = json.loads(line)
      scores = row.get("build_scaling") or {}
      if "cycles_per_line" in scores:
        rows[row["commit"]] = {
          "commit": row["commit"], "date": row["local_date"],
          "source_lines": scores["source_lines"],
          "cycles_per_line": scores["cycles_per_line"],
        }
  return rows


def replay(root: Path, commits: list[str]) -> None:
  replay_csv = root / "replay.csv"
  known = saved(root)
  for commit in commits:
    full, date, _ = commit_facts(commit)
    if full in known:
      print(f"{full[:8]}: saved", file=sys.stderr)
      continue
    print(f"{full[:8]}: building", file=sys.stderr)
    with tempfile.TemporaryDirectory(prefix="x2c-build-replay-") as work:
      tree = scaling.extract(Path(work), full)
      environment = {
        name: value for name, value in os.environ.items()
        if name not in {"MAKEFLAGS", "MAKELEVEL", "MFLAGS"}
      }
      subprocess.run(
        ["make", "build-safe"], cwd=tree, env=environment, check=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
      )
      lines, cycles = scaling.measure(tree, tree / "builds/0/x2c")
    new = not replay_csv.exists()
    with replay_csv.open("a", encoding="utf-8", newline="") as target:
      writer = csv.DictWriter(target, FIELDS)
      if new:
        writer.writeheader()
      writer.writerow({
        "commit": full, "date": date, "source_lines": lines,
        "cycles_per_line": f"{cycles / lines:.0f}",
      })
    known[full] = {}


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  parser.add_argument(
    "--replay", nargs="+", metavar="COMMIT",
    help="score these commits unless a score is already saved",
  )
  parser.add_argument(
    "--history-root", type=Path, default=snapshot.default_output_root(),
    help="performance history directory",
  )
  args = parser.parse_args()
  args.history_root.mkdir(parents=True, exist_ok=True)
  if args.replay:
    replay(args.history_root, args.replay)

  rows = sorted(
    saved(args.history_root).values(),
    key=lambda row: commit_facts(str(row["commit"]))[2],
  )
  if not rows:
    print("no saved build cost scores", file=sys.stderr)
    return 1
  newest = float(rows[-1]["cycles_per_line"])
  print("commit,date,source_lines,cycles_per_line,score")
  for row in rows:
    per_line = float(row["cycles_per_line"])
    print(f"{str(row['commit'])[:8]},{row['date']},{row['source_lines']},"
          f"{per_line:.0f},{100 * per_line / newest:.0f}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
