#!/usr/bin/env python3
"""Print retained build-cost rows, optionally replaying selected commits.

New CPU rows and historical driver-cycle rows retain separate metric and
baseline identities. Explicit replays use the commit's stage-0 translator.
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
FIELDS = (
  "commit", "date", "metric_id", "baseline_id", "authored_source_lines",
  "generated_source_lines", "total_source_lines",
  "cpu_seconds_per_authored_line", "legacy_source_lines", "cycles_per_line",
  "score",
)


def load(name: str, file: str):
  spec = importlib.util.spec_from_file_location(name, HERE / file)
  assert spec and spec.loader
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)
  return module


scaling = load("build_scaling", "build-scaling.py")
snapshot = load("performance_snapshot", "performance-snapshot.py")


def commit_facts(commit: str) -> tuple[str, str, int]:
  full, date, stamp = subprocess.run(
    ["git", "log", "-1", "--format=%H %cs %ct", commit],
    cwd=scaling.ROOT, check=True, stdout=subprocess.PIPE, text=True,
  ).stdout.split()
  return full, date, int(stamp)


def row_key(row: dict[str, object]) -> tuple[str, str, str]:
  return (str(row["commit"]), str(row["metric_id"]), str(row["baseline_id"]))


def legacy_row(commit: str, date: str, scores: dict[str, object]):
  if "cycles_per_line" not in scores:
    return None
  baseline = str(scores.get("baseline_commit", "unknown"))
  return {
    "commit": commit, "date": date,
    "metric_id": "driver-cycles-per-source-line/v0",
    "baseline_id": f"legacy-driver-cycles:{baseline}",
    "legacy_source_lines": scores.get("source_lines", ""),
    "cycles_per_line": scores["cycles_per_line"],
    "score": scores.get("score", ""),
  }


def saved(root: Path) -> dict[tuple[str, str, str], dict[str, object]]:
  rows = {}
  for path in (root / "replay.csv", root / "replay-child-cpu-v1.csv"):
    if not path.exists():
      continue
    with path.open(encoding="utf-8") as source:
      for raw in csv.DictReader(source):
        if raw.get("metric_id") == scaling.METRIC_ID:
          row = raw
        else:
          _, date, _ = commit_facts(raw["commit"])
          row = legacy_row(raw["commit"], date, raw)
        if row:
          rows[row_key(row)] = row

  history = root / "history.jsonl"
  if history.exists():
    for line in history.read_text(encoding="utf-8").splitlines():
      entry = json.loads(line)
      scores = entry.get("build_scaling") or {}
      if scores.get("metric_id") == scaling.METRIC_ID:
        row = {
          "commit": entry["commit"], "date": entry["local_date"],
          **{field: scores.get(field, "") for field in (
            "metric_id", "baseline_id", "authored_source_lines",
            "generated_source_lines", "total_source_lines",
            "cpu_seconds_per_authored_line", "score",
          )},
        }
      else:
        row = legacy_row(entry["commit"], entry["local_date"], scores)
      if row:
        key = row_key(row)
        if key[1] == "driver-cycles-per-source-line/v0":
          rows.pop((key[0], key[1], "legacy-driver-cycles:unknown"), None)
        rows[key] = row
  return rows


def replay(root: Path, commits: list[str]) -> None:
  baseline = json.loads(scaling.BASELINE.read_text(encoding="utf-8"))
  if baseline.get("metric_id") != scaling.METRIC_ID:
    raise ValueError("rebaseline build cost before replaying CPU scores")
  path = root / "replay-child-cpu-v1.csv"
  known = saved(root)
  for commit in commits:
    full, date, _ = commit_facts(commit)
    key = (full, scaling.METRIC_ID, baseline["baseline_id"])
    if key in known:
      print(f"{full[:8]}: saved for this metric and baseline", file=sys.stderr)
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
      counts, seconds = scaling.measure(tree, tree / "builds/0/x2c")
    per_line = seconds / counts["authored_source_lines"]
    row = {
      "commit": full, "date": date, "metric_id": scaling.METRIC_ID,
      "baseline_id": baseline["baseline_id"], **counts,
      "cpu_seconds_per_authored_line": per_line,
      "score": 100 * per_line / baseline["cpu_seconds_per_authored_line"],
    }
    new = not path.exists()
    with path.open("a", encoding="utf-8", newline="") as target:
      writer = csv.DictWriter(target, FIELDS, extrasaction="ignore")
      if new:
        writer.writeheader()
      writer.writerow(row)
    known[key] = row


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  parser.add_argument("--replay", nargs="+", metavar="COMMIT")
  parser.add_argument("--history-root", type=Path,
                      default=snapshot.default_output_root())
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
  writer = csv.DictWriter(sys.stdout, FIELDS, extrasaction="ignore")
  writer.writeheader()
  writer.writerows(rows)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
