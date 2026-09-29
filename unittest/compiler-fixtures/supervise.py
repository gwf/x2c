#!/usr/bin/env python3
"""Bound each fixture, retain its evidence, and clean up cancelled workers."""

import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


def stop_group(process, grace=1):
  # Descendants can remain after the worker exits. Address its whole group,
  # allowing signal handlers a short grace before killing stubborn children.
  # macOS fails with EPERM when the group holds only zombies or members this
  # process may not signal. Like a vanished group, it has nothing to stop.
  try:
    os.killpg(process.pid, signal.SIGTERM)
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
      process.poll()
      os.killpg(process.pid, 0)
      time.sleep(0.02)
    os.killpg(process.pid, signal.SIGKILL)
  except (ProcessLookupError, PermissionError):
    pass
  process.wait()


def main():
  mode = sys.argv[1] if len(sys.argv) > 1 else "check"
  args = sys.argv[2:]
  if args and (len(args) != 2 or args[0] != "--fixture"):
    print("usage: run.sh [check|update] [--fixture <name>]", file=sys.stderr)
    return 2
  try:
    timeout = float(os.environ.get("FIXTURE_TIMEOUT_SECONDS", "60"))
    if not math.isfinite(timeout) or timeout <= 0:
      raise ValueError()
  except ValueError:
    print("FIXTURE_TIMEOUT_SECONDS must be a positive number", file=sys.stderr)
    return 2

  script_dir = Path(__file__).resolve().parent
  build = Path(os.environ.get(
    "FIXTURE_BUILD", script_dir.parent / "build/compiler-fixtures"))
  name = args[1] if args else None
  command = [str(script_dir / "run.sh"), mode]
  command += ["--worker", name] if name else ["--suite"]
  interrupted = 0

  def interrupt(signum, _frame):
    nonlocal interrupted
    interrupted = signum

  for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, interrupt)
  started = time.monotonic()
  process = subprocess.Popen(command, start_new_session=True)
  expired = False
  try:
    while process.poll() is None and not interrupted:
      elapsed = time.monotonic() - started
      if name and elapsed >= timeout:
        expired = True
        print(f"compiler fixture failure: {name} timed out after {timeout:g}s; "
              f"log: {build / name / 'log'}", file=sys.stderr, flush=True)
        break
      time.sleep(0.02)
  finally:
    stop_group(process, grace=1 if name else 2)
  elapsed = time.monotonic() - started

  if not name:
    times = [(float(path.read_text()), path.parent.name)
             for path in build.glob("*/elapsed")]
    if times:
      seconds, slowest = max(times)
      print(f"Compiler fixtures elapsed: {elapsed:.2f}s; "
            f"slowest: {slowest} ({seconds:.2f}s)", flush=True)
    return 128 + interrupted if interrupted else process.returncode

  case = build / name
  case.mkdir(parents=True, exist_ok=True)
  (case / "elapsed").write_text(f"{elapsed:.3f}\n")
  tally = case / "tally"
  if expired or interrupted or process.returncode or not tally.exists():
    reason = (f"timed out after {timeout:g}s" if expired else
              f"interrupted by signal {interrupted}" if interrupted else
              f"worker exited {process.returncode} without completing")
    with (case / "log").open("a") as log:
      log.write(f"compiler fixture failure: {name} {reason}\n")
    tally.write_text("1 0\n")
  failures, artifacts = map(int, tally.read_text().split())
  if not failures and mode == "update":
    fixture_dir = Path(os.environ.get("FIXTURE_DIR", script_dir))
    try:
      for actual in sorted((case / "updates").glob("*")):
        shutil.copyfile(actual, fixture_dir / f"{name}.{actual.name}")
    except OSError as error:
      failures = 1
      with (case / "log").open("a") as log:
        log.write(f"compiler fixture failure: {name} update failed: {error}\n")
      tally.write_text(f"1 {artifacts}\n")
  if interrupted:
    return 128 + interrupted
  if os.environ.get("FIXTURE_TALLY_ONLY"):
    return 0
  if failures:
    sys.stderr.write((case / "log").read_text())
    return 1
  print(f"Compiler fixture {name} passed ({elapsed:.2f}s)", file=sys.stderr)
  return 0


if __name__ == "__main__":
  sys.exit(main())
