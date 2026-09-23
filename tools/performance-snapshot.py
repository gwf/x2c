#!/usr/bin/env python3
"""Run and retain the representative x2c performance snapshot.

Performance evidence is deliberately separate from correctness and publication
gates. Complete output is kept under a persistent history directory, with one
compact JSONL row per attempt for longitudinal reporting.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid


ROOT = Path(__file__).resolve().parent.parent
SHOOTOUT_LATEST = ROOT / "examples/build/shootout/latest"
SHOOTOUT_RAW = ROOT / "examples/build/shootout/raw.jsonl"
PERFORMANCE_ENV = (
  "DYLD_INSERT_LIBRARIES", "GLIBC_TUNABLES", "LD_PRELOAD",
  "MallocNanoZone", "MallocStackLogging",
)
COMMANDS = (
  ("setup", ["make", "build-safe"]),
  ("stage-3", ["make", "stage-3"]),
  ("stage-diff", [
    "make", "stage-diff-0", "stage-diff-1", "stage-diff-2",
    "stage-diff-3",
  ]),
  ("build-scaling", ["make", "bm-build-scaling"]),
  ("shootout", ["make", "shoot-run"]),
  ("runtime", ["make", "performance-runtime"]),
  ("compiler", ["make", "bm-compiler"]),
)

# Size-normalized rates first, then the fixed workload and the raw sizes.
BUILD_SCALING_METRICS = (
  "translate_seconds_per_kline", "cc_seconds_per_mb", "c_bytes_per_line",
  "pinned_seconds", "seconds", "cc_seconds", "source_lines",
  "generated_c_bytes",
)


class SnapshotError(RuntimeError):
  """A snapshot prerequisite or command failed."""


def git(*args: str, cwd: Path = ROOT) -> str:
  result = subprocess.run(
    ["git", *args], cwd=cwd, check=True, capture_output=True, text=True,
  )
  return result.stdout.strip()


def default_output_root() -> Path:
  common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir"))
  return common.parent / "debug/performance-history"


def atomic_json(path: Path, value: object) -> None:
  temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
  temporary.write_text(
    json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8",
  )
  os.replace(temporary, path)


def successful_today(history: Path, local_date: str) -> bool:
  if not history.exists():
    return False
  for line in history.read_text(encoding="utf-8").splitlines():
    try:
      row = json.loads(line)
    except json.JSONDecodeError:
      continue
    if row.get("local_date") == local_date and row.get("status") == "success":
      return True
  return False


def previous_success(history: Path) -> dict[str, object] | None:
  if not history.exists():
    return None
  for line in reversed(history.read_text(encoding="utf-8").splitlines()):
    try:
      row = json.loads(line)
    except json.JSONDecodeError:
      continue
    if row.get("status") == "success":
      return row
  return None


def sha256(path: Path) -> str:
  digest = hashlib.sha256()
  with path.open("rb") as source:
    for block in iter(lambda: source.read(1024 * 1024), b""):
      digest.update(block)
  return digest.hexdigest()


def run_logged(
  name: str, command: list[str], run_dir: Path, environment: dict[str, str],
  timeout_seconds: int,
) -> dict[str, object]:
  log_path = run_dir / f"{name}.log"
  started_at = dt.datetime.now(dt.timezone.utc).isoformat()
  started = time.monotonic_ns()
  with log_path.open("w", encoding="utf-8") as log:
    process = subprocess.Popen(
      command, cwd=ROOT, env=environment, stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT, text=True, errors="replace", bufsize=1,
      start_new_session=True,
    )
    assert process.stdout is not None
    def copy_output() -> None:
      for line in process.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        log.write(line)
    reader = threading.Thread(target=copy_output)
    reader.start()
    timed_out = False
    try:
      returncode = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
      timed_out = True
      try:
        os.killpg(process.pid, signal.SIGTERM)
      except ProcessLookupError:
        pass
      try:
        returncode = process.wait(timeout=10)
      except subprocess.TimeoutExpired:
        try:
          os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
          pass
        returncode = process.wait()
    reader.join()
    process.stdout.close()
  elapsed_ns = time.monotonic_ns() - started
  return {
    "name": name,
    "command": command,
    "started_at_utc": started_at,
    "finished_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "elapsed_seconds": elapsed_ns / 1_000_000_000,
    "log": log_path.name,
    "log_sha256": sha256(log_path),
    "returncode": returncode,
    "timed_out": timed_out,
  }


def compiler_summary(log_path: Path) -> dict[str, float]:
  rows = []
  for line in log_path.read_text(encoding="utf-8").splitlines():
    if line.startswith(("benchmark,stage,", "translation,stage-")):
      rows.append(line)
  if not rows:
    raise SnapshotError("compiler benchmark produced no CSV rows")
  parsed = list(csv.DictReader(rows))
  grouped: dict[str, list[float]] = {}
  for row in parsed:
    key = f"{row['stage']}/{row['mode']}"
    grouped.setdefault(key, []).append(float(row["seconds"]))
  medians = {}
  for key, values in grouped.items():
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
      medians[key] = ordered[middle]
    else:
      medians[key] = (ordered[middle - 1] + ordered[middle]) / 2
  return medians


def median(values: list[float]) -> float:
  ordered = sorted(values)
  middle = len(ordered) // 2
  if len(ordered) % 2:
    return ordered[middle]
  return (ordered[middle - 1] + ordered[middle]) / 2


def runtime_summary(log_path: Path) -> dict[str, object]:
  target = None
  mode = None
  sample = None
  inferred: dict[tuple[str, str | None, str], int] = {}
  records = []
  for line in log_path.read_text(encoding="utf-8").splitlines():
    fields = line.split(",")
    if len(fields) == 2 and fields[0] == "x2c-performance-target":
      target, mode, sample = fields[1], None, None
      continue
    if target is None:
      continue
    if len(fields) == 2 and fields[0] == "sample" and fields[1].isdigit():
      sample = int(fields[1])
      continue
    if (
      len(fields) == 2 and fields[0].endswith("-sample")
      and fields[1].isdigit()
    ):
      mode = fields[0][:-len("-sample")]
      sample = int(fields[1])
      continue
    if len(fields) == 4 and fields[1].isdigit():
      try:
        value = float(fields[3])
      except ValueError:
        continue
      records.append({
        "target": target, "mode": fields[0], "sample": int(fields[1]),
        "metric": fields[2], "value": value,
      })
      continue
    if len(fields) != 2:
      continue
    try:
      value = float(fields[1])
    except ValueError:
      continue
    metric = fields[0]
    current_sample = sample
    if current_sample is None:
      key = (target, mode, metric)
      inferred[key] = inferred.get(key, 0) + 1
      current_sample = inferred[key]
    records.append({
      "target": target, "mode": mode, "sample": current_sample,
      "metric": metric, "value": value,
    })

  grouped: dict[tuple[str, str | None, str], list[float]] = {}
  for record in records:
    key = (record["target"], record["mode"], record["metric"])
    grouped.setdefault(key, []).append(record["value"])
  medians = [
    {
      "target": key[0], "mode": key[1], "metric": key[2],
      "samples": len(values), "median": median(values),
    }
    for key, values in sorted(
      grouped.items(), key=lambda item: tuple(value or "" for value in item[0])
    )
  ]
  return {"records": records, "medians": medians}


def command_text(command: list[str]) -> str | None:
  result = subprocess.run(command, capture_output=True, text=True)
  return result.stdout.strip() if result.returncode == 0 else None


def machine_receipt() -> dict[str, object]:
  receipt: dict[str, object] = {
    "platform": platform.platform(),
    "machine": platform.machine(),
    "logical_cores": os.cpu_count(),
    "python": sys.version,
    "cc_version": command_text([os.environ.get("CC", "cc"), "--version"]),
  }
  if sys.platform == "darwin":
    for key, sysctl_name in (
      ("cpu_model", "machdep.cpu.brand_string"),
      ("physical_cores", "hw.physicalcpu"),
      ("memory_bytes", "hw.memsize"),
    ):
      receipt[key] = command_text(["sysctl", "-n", sysctl_name])
    receipt["power_source"] = command_text(["pmset", "-g", "batt"])
  try:
    receipt["load_average"] = list(os.getloadavg())
  except OSError:
    receipt["load_average"] = None
  return receipt


def compact_history(summary: dict[str, object]) -> dict[str, object]:
  shootout = summary.get("shootout") or {}
  return {
    "run_id": summary["run_id"],
    "local_date": summary["local_date"],
    "status": summary["status"],
    "commit": summary["repository"]["commit"],
    "tree": summary["repository"]["tree"],
    "started_at_utc": summary["started_at_utc"],
    "finished_at_utc": summary.get("finished_at_utc"),
    "machine": summary["machine"],
    "stage_3_seconds": summary.get("stage_3_seconds"),
    "compiler_median_seconds": summary.get("compiler_median_seconds"),
    "build_scaling": summary.get("build_scaling"),
    "runtime_medians": summary.get("runtime_medians"),
    "shootout_median": shootout.get("median"),
    "shootout_arithmetic_mean": shootout.get("arithmetic_mean"),
    "failure": summary.get("failure"),
  }


def append_history(path: Path, row: dict[str, object]) -> None:
  with path.open("a", encoding="utf-8") as history:
    history.write(json.dumps(row, sort_keys=True) + "\n")
    history.flush()
    os.fsync(history.fileno())


def percent_change(current: float, previous: float) -> str:
  if previous == 0:
    return "n/a"
  return f"{100 * (current - previous) / previous:+.2f}%"


def comparable_metrics(row: dict[str, object]) -> dict[str, float]:
  metrics = {}
  stage = row.get("stage_3_seconds")
  if isinstance(stage, (int, float)):
    metrics["stage-3 seconds"] = float(stage)
  scaling = row.get("build_scaling") or {}
  for key in BUILD_SCALING_METRICS:
    if key in scaling:
      metrics[f"build {key}"] = float(scaling[key])
  for key, value in (row.get("compiler_median_seconds") or {}).items():
    metrics[f"compiler {key} seconds"] = float(value)
  for key, value in (row.get("shootout_median") or {}).items():
    if key in {"time_x2c_over_c", "time_ported_over_c"}:
      metrics[f"shootout median {key}"] = float(value)
  for item in row.get("runtime_medians") or []:
    mode = f"/{item['mode']}" if item.get("mode") else ""
    key = f"runtime {item['target']}{mode}/{item['metric']}"
    metrics[key] = float(item["median"])
  return metrics


def render_report(
  current: dict[str, object], previous: dict[str, object] | None,
) -> str:
  lines = [
    "# x2c performance snapshot",
    "",
    f"- Status: `{current['status']}`",
    f"- Commit: `{current['commit']}`",
    f"- Run: `{current['run_id']}`",
  ]
  if current["status"] != "success":
    lines.extend(["", f"Failure: {current.get('failure', 'unknown failure')}"])
    return "\n".join(lines) + "\n"
  if previous is None:
    lines.extend(["", "This is the first successful retained snapshot."])
    return "\n".join(lines) + "\n"

  old = comparable_metrics(previous)
  new = comparable_metrics(current)
  shared = sorted(set(old) & set(new))
  headline = [key for key in shared if not key.startswith("runtime ")]
  runtime = sorted(
    (key for key in shared if key.startswith("runtime ")),
    key=lambda key: abs((new[key] - old[key]) / old[key]) if old[key] else 0,
    reverse=True,
  )[:10]
  lines.extend([
    "",
    f"Compared with `{previous['run_id']}` at `{previous['commit']}`.",
    "Lower is better for the stage, compiler, and shootout timing rows.",
    "Runtime-suite rows are the ten largest changes and retain their original",
    "metric names; interpret non-timing counters by their documented meaning.",
    "",
    "| Metric | Previous | Current | Change |",
    "| --- | ---: | ---: | ---: |",
  ])
  for key in [*headline, *runtime]:
    lines.append(
      f"| {key} | {old[key]:.6g} | {new[key]:.6g} | "
      f"{percent_change(new[key], old[key])} |"
    )
  return "\n".join(lines) + "\n"


def run_snapshot_locked(
  output_root: Path, skip_today: bool, timeout_seconds: int,
) -> int:
  status = git("status", "--porcelain", "--untracked-files=all")
  if status:
    raise SnapshotError("performance snapshots require a clean worktree")
  build_mode = (ROOT / "etc/build-mode").read_text(encoding="utf-8").strip()
  if build_mode != "optimize":
    raise SnapshotError("tracked etc/build-mode must be optimize")

  output_root.mkdir(parents=True, exist_ok=True)
  history_path = output_root / "history.jsonl"
  prior = previous_success(history_path)
  local_date = dt.datetime.now().astimezone().date().isoformat()
  if skip_today and successful_today(history_path, local_date):
    print(f"performance snapshot already succeeded on {local_date}")
    return 0

  commit = git("rev-parse", "HEAD")
  timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
  run_id = timestamp + "-" + commit[:12]
  run_dir = output_root / "runs" / local_date.replace("-", "/") / run_id
  if run_dir.exists():
    run_dir = run_dir.with_name(run_dir.name + "-" + uuid.uuid4().hex[:8])
  run_dir.mkdir(parents=True)

  summary: dict[str, object] = {
    "schema": 1,
    "run_id": run_dir.name,
    "local_date": local_date,
    "status": "running",
    "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "repository": {
      "commit": commit,
      "tree": git("rev-parse", "HEAD^{tree}"),
      "remote": git("remote", "get-url", "origin"),
    },
    "configuration": {"build_mode": build_mode, "build_lto": 0},
    "machine": machine_receipt(),
    "steps": [],
  }
  atomic_json(run_dir / "summary.json", summary)

  environment = os.environ.copy()
  for name in ("MAKEFLAGS", "MAKELEVEL", "MFLAGS"):
    environment.pop(name, None)
  environment.update({
    "BUILD_MODE": "optimize", "BUILD_LTO": "0", "LC_ALL": "C", "TZ": "UTC",
    "BUILD_JOBS": str(os.cpu_count() or 1),
  })
  summary["configuration"].update({
    "build_jobs": environment["BUILD_JOBS"],
    "cc": environment.get("CC", "cc"),
    "performance_environment": {
      name: environment[name] for name in PERFORMANCE_ENV if name in environment
    },
  })
  try:
    for name, command in COMMANDS:
      result = run_logged(
        name, command, run_dir, environment, timeout_seconds,
      )
      summary["steps"].append(result)
      atomic_json(run_dir / "summary.json", summary)
      if result["returncode"]:
        raise SnapshotError(
          f"{name} failed with status {result['returncode']}"
        )
      if name == "stage-3":
        summary["stage_3_seconds"] = result["elapsed_seconds"]
      elif name == "build-scaling":
        log = (run_dir / "build-scaling.log").read_text(encoding="utf-8")
        summary["build_scaling"] = json.loads(next(
          line for line in reversed(log.splitlines()) if line.startswith("{")
        ))
      elif name == "shootout":
        if not SHOOTOUT_LATEST.is_dir():
          raise SnapshotError("shootout did not produce its latest receipt")
        destination = run_dir / "shootout"
        shutil.copytree(SHOOTOUT_LATEST, destination)
        if SHOOTOUT_RAW.exists():
          shutil.copy2(SHOOTOUT_RAW, destination / SHOOTOUT_RAW.name)
        summary["shootout"] = json.loads(
          (destination / "summary.json").read_text(encoding="utf-8")
        )
      elif name == "compiler":
        summary["compiler_median_seconds"] = compiler_summary(
          run_dir / "compiler.log"
        )
      elif name == "runtime":
        runtime = runtime_summary(run_dir / "runtime.log")
        atomic_json(run_dir / "runtime.json", runtime)
        summary["runtime_medians"] = runtime["medians"]
      atomic_json(run_dir / "summary.json", summary)
    summary["status"] = "success"
  except (OSError, SnapshotError, subprocess.SubprocessError) as error:
    summary["status"] = "failed"
    summary["failure"] = str(error)
  summary["finished_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
  summary["machine_end"] = machine_receipt()
  atomic_json(run_dir / "summary.json", summary)
  history_row = compact_history(summary)
  report = render_report(history_row, prior)
  (run_dir / "report.md").write_text(report, encoding="utf-8")
  append_history(history_path, history_row)
  atomic_json(output_root / "latest-attempt.json", summary)
  if summary["status"] == "success":
    atomic_json(output_root / "latest.json", summary)
    temporary_report = output_root / ("latest.md.tmp-" + uuid.uuid4().hex)
    temporary_report.write_text(report, encoding="utf-8")
    os.replace(temporary_report, output_root / "latest.md")
  print(report, end="")
  print(f"performance snapshot: {summary['status']}")
  print(f"summary: {run_dir / 'summary.json'}")
  return 0 if summary["status"] == "success" else 1


def run_snapshot(
  output_root: Path, skip_today: bool, timeout_seconds: int,
) -> int:
  output_root.mkdir(parents=True, exist_ok=True)
  with (output_root / "snapshot.lock").open("a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    return run_snapshot_locked(output_root, skip_today, timeout_seconds)


def run_ref(args: argparse.Namespace, output_root: Path) -> int:
  if args.fetch:
    subprocess.run(
      ["git", "fetch", "origin", "dev"], cwd=ROOT, check=True,
    )
  temporary = Path(tempfile.mkdtemp(prefix="x2c-performance-"))
  worktree = temporary / "worktree"
  added = False
  try:
    subprocess.run(
      ["git", "worktree", "add", "--detach", str(worktree), args.ref],
      cwd=ROOT, check=True,
    )
    added = True
    command = [
      sys.executable, str(worktree / "tools/performance-snapshot.py"),
      "--run-here", "--output-root", str(output_root),
      "--step-timeout", str(args.step_timeout),
    ]
    if args.skip_if_success_today:
      command.append("--skip-if-success-today")
    return subprocess.run(command, cwd=worktree).returncode
  finally:
    if added:
      subprocess.run(
        ["git", "worktree", "remove", "--force", str(worktree)],
        cwd=ROOT, check=False,
      )
    shutil.rmtree(temporary, ignore_errors=True)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser()
  parser.add_argument(
    "--output-root", type=Path,
    help="persistent history directory; defaults to the main checkout debug/",
  )
  parser.add_argument(
    "--ref", help="measure a ref in a temporary detached worktree",
  )
  parser.add_argument(
    "--fetch", action="store_true",
    help="fetch origin/dev before resolving --ref",
  )
  parser.add_argument(
    "--skip-if-success-today", action="store_true",
    help="exit successfully when local history already has today's run",
  )
  parser.add_argument(
    "--dry-run", action="store_true",
    help="print the measured commands without creating output",
  )
  parser.add_argument(
    "--step-timeout", type=int, default=7200,
    help="maximum seconds for each suite command (default: 7200)",
  )
  parser.add_argument(
    "--run-here", action="store_true", help=argparse.SUPPRESS,
  )
  return parser.parse_args()


def main() -> int:
  args = parse_args()
  if args.fetch and not args.ref:
    raise SnapshotError("--fetch requires --ref")
  if args.step_timeout < 1:
    raise SnapshotError("--step-timeout must be positive")
  if args.dry_run:
    for name, command in COMMANDS:
      print(f"{name}: {' '.join(command)}")
    return 0
  output_root = (
    args.output_root.expanduser().resolve()
    if args.output_root else default_output_root()
  )
  if args.ref and not args.run_here:
    return run_ref(args, output_root)
  return run_snapshot(
    output_root, args.skip_if_success_today, args.step_timeout,
  )


if __name__ == "__main__":
  try:
    raise SystemExit(main())
  except (SnapshotError, subprocess.SubprocessError) as error:
    print(f"performance snapshot: {error}", file=sys.stderr)
    raise SystemExit(2)
