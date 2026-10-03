#!/usr/bin/env python3
"""Bound each fixture, retain its evidence, and clean up cancelled workers."""

import hashlib
import json
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


def finish_fixture(process, name, started, build, fixture_dir, mode,
                   reason=None):
  stop_group(process)
  elapsed = time.monotonic() - started
  case = build / name
  case.mkdir(parents=True, exist_ok=True)
  (case / "elapsed").write_text(f"{elapsed:.3f}\n")
  tally = case / "tally"
  if reason or process.returncode or not tally.exists():
    reason = reason or f"worker exited {process.returncode} without completing"
    with (case / "log").open("a") as log:
      log.write(f"compiler fixture failure: {name} {reason}\n")
    tally.write_text("1 0\n")
  failures, artifacts = map(int, tally.read_text().split())
  if not failures and mode == "update":
    try:
      for actual in sorted((case / "updates").glob("*")):
        shutil.copyfile(actual, fixture_dir / f"{name}.{actual.name}")
    except OSError as error:
      failures = 1
      with (case / "log").open("a") as log:
        log.write(f"compiler fixture failure: {name} update failed: {error}\n")
      tally.write_text(f"1 {artifacts}\n")
  if failures:
    sys.stderr.write((case / "log").read_text())
    sys.stderr.flush()
  return failures, artifacts, elapsed


def retry_history(path):
  # Hints can survive source edits, but never authorize skipping a fixture.
  try:
    history = json.loads(path.read_text())
    return ({name: result for name, result in history.items()
             if result in ("failed", "passed")}
            if isinstance(history, dict) else {})
  except (OSError, ValueError):
    return {}


def save_history(path, history):
  path.parent.mkdir(parents=True, exist_ok=True)
  temporary = path.with_suffix(f".{os.getpid()}.tmp")
  temporary.write_text(json.dumps(history, sort_keys=True) + "\n")
  temporary.replace(path)


def main():
  mode = sys.argv[1] if len(sys.argv) > 1 else "check"
  args = sys.argv[2:]
  if (mode not in {"check", "update"} or
      (args and (len(args) != 2 or args[0] != "--fixture"))):
    print("usage: run.sh [check|update] [--fixture <name>]", file=sys.stderr)
    return 2
  try:
    timeout = float(os.environ.get("FIXTURE_TIMEOUT_SECONDS", "60"))
    jobs = int(os.environ.get("JOBS", os.cpu_count() or 1))
    if not math.isfinite(timeout) or timeout <= 0 or jobs <= 0:
      raise ValueError()
  except ValueError:
    print("FIXTURE_TIMEOUT_SECONDS and JOBS must be positive numbers; "
          "JOBS must be an integer", file=sys.stderr)
    return 2

  script_dir = Path(__file__).resolve().parent
  fixture_dir = Path(os.environ.get("FIXTURE_DIR", script_dir))
  build = Path(os.environ.get(
    "FIXTURE_BUILD", script_dir.parent / "build/compiler-fixtures"))
  name = args[1] if args else None
  names = [name] if name else sorted(
    manifest.stem for manifest in fixture_dir.glob("*.phases"))
  identity = f"{fixture_dir.resolve()}\n{build.resolve()}".encode()
  state = script_dir.parent.parent / "debug/fixture-retry" / (
    hashlib.sha256(identity).hexdigest()[:16] + ".json")
  state = Path(os.environ.get("FIXTURE_RETRY_STATE", state))
  remember = mode == "check" and name is None
  history = retry_history(state) if remember else {}
  history = {item: result for item, result in history.items() if item in names}
  if remember:
    batches = [[item for item in names if history.get(item) == result]
               for result in ("failed", None, "passed")]
  else:
    batches = [names]
  if not name:
    shutil.rmtree(build, ignore_errors=True)
  build.mkdir(parents=True, exist_ok=True)
  interrupted = 0

  def interrupt(signum, _frame):
    nonlocal interrupted
    interrupted = signum

  for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, interrupt)
  started = time.monotonic()
  active = {}
  failures = artifacts = completed = 0
  times = []
  try:
    for batch in batches:
      pending = iter(batch)
      exhausted = False
      while active or not exhausted:
        # Observe all completions before dispatching replacements. A failure
        # stops new work while already running fixtures finish normally.
        for item, (process, launched) in list(active.items()):
          expired = (process.poll() is None and
                     time.monotonic() - launched >= timeout)
          if process.poll() is None and not expired:
            continue
          reason = f"timed out after {timeout:g}s" if expired else None
          result, count, elapsed = finish_fixture(
            process, item, launched, build, fixture_dir, mode, reason)
          del active[item]
          failures += result
          artifacts += count
          completed += 1
          times.append((elapsed, item))
          if remember:
            history[item] = "failed" if result else "passed"
            save_history(state, history)
        if interrupted:
          break
        if failures and mode == "check":
          exhausted = True
        while not exhausted and len(active) < jobs:
          item = next(pending, None)
          if item is None:
            exhausted = True
            break
          process = subprocess.Popen(
            [str(script_dir / "run.sh"), mode, "--worker", item],
            start_new_session=True)
          active[item] = (process, time.monotonic())
        if active:
          time.sleep(0.02)
      if interrupted or (failures and mode == "check"):
        break
  finally:
    # Signal all groups before waiting for any one of them.
    for process, _ in active.values():
      try:
        os.killpg(process.pid, signal.SIGTERM)
      except (ProcessLookupError, PermissionError):
        pass
    for item, (process, _) in active.items():
      stop_group(process)
      if remember and history.get(item) != "failed":
        history.pop(item, None)
    if remember:
      save_history(state, history)

  elapsed = time.monotonic() - started
  if times:
    seconds, slowest = max(times)
    print(f"Compiler fixtures elapsed: {elapsed:.2f}s; "
          f"slowest: {slowest} ({seconds:.2f}s)", flush=True)
  if interrupted:
    return 128 + interrupted
  if failures:
    print(f"Compiler fixtures: {failures} failure(s); "
          f"{completed}/{len(names)} fixtures completed", file=sys.stderr)
    return 1
  if name:
    print(f"Compiler fixture {name} passed ({elapsed:.2f}s)", file=sys.stderr)
  elif mode == "update":
    print(f"Compiler fixtures: updated {artifacts} artifacts across "
          f"{completed} fixtures")
  else:
    print(f"Compiler fixtures: {completed} passed ({artifacts} artifacts)")
  return 0


if __name__ == "__main__":
  sys.exit(main())
