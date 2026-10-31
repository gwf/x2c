#!/usr/bin/env python3
"""Check unchanged contributed C through the native driver and x2c parser.

This optional observation is not a publication gate or a timing column.
Every run retains its commands, output bytes, diagnostics, and source hashes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace

import shootout as suite


def run_step(argv, directory, label, timeout, stdin_path=None):
  try:
    completed = suite.command(
      argv, timeout=timeout, check=False, stdin_path=stdin_path,
    )
    code, stdout, stderr = (
      completed.returncode, completed.stdout, completed.stderr,
    )
  except subprocess.TimeoutExpired as error:
    code, stdout, stderr = None, error.stdout or b"", error.stderr or b""
    stderr += f"\nTimed out after {timeout} seconds.\n".encode()
  except OSError as error:
    code, stdout, stderr = None, b"", str(error).encode()
  output = directory / f"{label}.stdout"
  errors = directory / f"{label}.stderr"
  output.write_bytes(stdout)
  errors.write_bytes(stderr)
  return {
    "command": argv, "returncode": code,
    "stdout": str(output), "stderr": str(errors),
  }


def compare_run(name, stage, case, expected, record):
  actual = Path(record["stdout"]).read_bytes()
  errors = Path(record["stderr"]).read_bytes()
  record["expected_sha256"] = hashlib.sha256(expected).hexdigest()
  record["actual_sha256"] = hashlib.sha256(actual).hexdigest()
  if record["returncode"] != 0 or errors:
    record["passed"] = False
    return False
  try:
    record["comparison"] = suite.compare_output(
      name, stage, case, expected, actual,
    )
    record["passed"] = True
  except suite.HarnessError as error:
    comparison = Path(record["stdout"]).with_suffix(".comparison.txt")
    comparison.write_text(str(error) + "\n")
    record["comparison_error"] = str(comparison)
    record["passed"] = False
  return record["passed"]


def check_fixtures(benchmark, binary, directory, label, timeout):
  source = suite.ROOT / "benchmarks" / benchmark["name"]
  checks = []
  for index, case in enumerate(benchmark["checks"], 1):
    stdin = source / case["stdin"] if case.get("stdin") else None
    record = run_step(
      [str(binary), *case["args"]], directory,
      f"{label}-fixture-{index}", timeout, stdin,
    )
    record["args"] = case["args"]
    record["stdin_sha256"] = suite.sha256(stdin) if stdin else None
    compare_run(
      benchmark["name"], label, case,
      (source / case["expected"]).read_bytes(), record,
    )
    checks.append(record)
  return checks


def check_benchmark(benchmark, manifest, toolchain, directory, args):
  name = benchmark["name"]
  source = suite.ROOT / "benchmarks" / name / "main.c"
  directory.mkdir()
  copied = directory / "reference.x"
  shutil.copyfile(source, copied)
  cppflags, ldflags = suite.native_flags(benchmark)
  includes = [*cppflags, *toolchain["cppflags"], "-I", str(source.parent)]
  native = directory / "native-program"
  native_argv = [
    str(toolchain["x2c"]), "build", "--cc", toolchain["cc"],
    *toolchain["cflags"], *includes,
    *benchmark.get("c_flags", []), *ldflags, *toolchain["ldflags"],
    *benchmark.get("c_link_flags", []),
    "--build-dir", str(directory / "native-build"),
    "--output", str(native), str(source),
  ]
  result = {
    "name": name, "source": str(source),
    "source_sha256": suite.sha256(source),
    "parser_input": str(copied), "parser_input_sha256": suite.sha256(copied),
    "native_driver": run_step(
      native_argv, directory, "native-build", args.timeout,
    ),
  }
  driver = result["native_driver"]
  if driver["returncode"] == 0:
    driver["fixtures"] = check_fixtures(
      benchmark, native, directory, "native", args.timeout,
    )
    driver["passed"] = all(check["passed"] for check in driver["fixtures"])
  else:
    driver["passed"] = False

  generated = directory / "generated"
  translate_argv = [
    str(toolchain["x2c"]), "translate", "--cpp", *includes,
    "--out-dir", str(generated), str(copied),
  ]
  parsed = result["x2c_parser"] = {
    "translate": run_step(
      translate_argv, directory, "translate", args.timeout,
    ),
    "passed": False,
  }
  if parsed["translate"]["returncode"] != 0:
    return result
  binary = directory / "translated-program"
  link = ["-rdynamic"] if sys.platform.startswith("linux") else []
  compile_argv = [
    toolchain["cc"], *toolchain["cflags"], *includes, *link,
    *benchmark.get("c_flags", []),
    str(generated / "reference.c"), "-iquote", str(toolchain["include"]),
    "-L", str(toolchain["runtime"].parent), "-lx2c", "-lm",
    *ldflags, *toolchain["ldflags"], *benchmark.get("c_link_flags", []),
    "-o", str(binary),
  ]
  parsed["compile"] = run_step(
    compile_argv, directory, "compile", args.timeout,
  )
  if parsed["compile"]["returncode"] != 0:
    return result
  parsed["fixtures"] = check_fixtures(
    benchmark, binary, directory, "parsed", args.timeout,
  )
  parsed["passed"] = all(check["passed"] for check in parsed["fixtures"])
  if not driver["passed"]:
    return result
  program_args = manifest["profiles"][args.profile][name]
  stdin = suite.profile_stdin(benchmark, args.profile, toolchain)
  driver["profile"] = run_step(
    [str(native), *program_args], directory, "native-profile", args.timeout,
    stdin,
  )
  parsed["profile"] = run_step(
    [str(binary), *program_args], directory, "parsed-profile", args.timeout,
    stdin,
  )
  oracle = driver["profile"]
  if oracle["returncode"] != 0 or Path(oracle["stderr"]).read_bytes():
    driver["passed"] = False
    parsed["passed"] = False
    return result
  case = {"args": program_args, "comparison": suite.profile_comparison(benchmark)}
  profile_pass = compare_run(
    name, "x2c_parser", case, Path(oracle["stdout"]).read_bytes(),
    parsed["profile"],
  )
  parsed["passed"] = parsed["passed"] and profile_pass
  return result


def render_report(report):
  rows = [
    "# Unchanged C through x2c", "",
    f"- Run: `{report['run_id']}`",
    f"- x2c: `{report['x2c']}`",
    f"- Compiler SHA-256: `{report['x2c_sha256']}`",
    f"- Profile comparison: `{report['profile']}`", "",
    "The native-driver path builds the original `.c` with `x2c build`.",
    "The parser path translates a byte-identical `.x` copy with `--cpp`,",
    "then compiles the emitted C. Both paths check the official fixtures.",
    "Successful parser builds also compare profile output with the",
    "fixture-verified native-driver program. No source is rewritten.", "",
    "| Problem | Native driver | x2c parser | Parser result |",
    "| --- | --- | --- | --- |",
  ]
  for entry in report["benchmarks"]:
    driver, parsed = entry["native_driver"], entry["x2c_parser"]
    detail = "official fixtures and profile output match"
    if not parsed["passed"]:
      stage = "translate" if parsed["translate"]["returncode"] != 0 else "compile"
      record = parsed.get(stage)
      if record and record["returncode"] != 0:
        errors = Path(record["stderr"]).read_text(errors="replace").splitlines()
        detail = errors[0] if errors else f"{stage} failed"
      else:
        detail = "output comparison failed; see retained logs"
    detail = detail.replace("|", "\\|")
    rows.append(
      f"| {entry['name']} | {'pass' if driver['passed'] else 'fail'} | "
      f"{'pass' if parsed['passed'] else 'fail'} | {detail} |"
    )
  rows += ["", "Commands, source hashes, stdout, stderr, and comparison details",
           "are retained beside `report.json`. This optional check is separate",
           "from timing results and publication gates.", ""]
  return "\n".join(rows)


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--x2c", type=Path,
                      default=suite.REPO / "builds/0/x2c")
  parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
  parser.add_argument("--cflags", default=suite.DEFAULT_CFLAGS)
  parser.add_argument("--profile", default="local")
  parser.add_argument("--timeout", type=float, default=120)
  parser.add_argument("--output", type=Path,
                      default=suite.BUILD.parent / "shootout-c")
  args = parser.parse_args()
  args.x2c = args.x2c.resolve()
  # The optional override selects an existing staged compiler and its runtime.
  suite.REPO = args.x2c.parents[2]
  manifest = suite.load_manifest()
  if args.profile not in manifest["profiles"]:
    parser.error(f"unknown profile: {args.profile}")
  toolchain = suite.resolve_toolchain(SimpleNamespace(
    cc=args.cc, python=sys.executable, action="run", cflags=args.cflags,
  ))
  toolchain["x2c"] = args.x2c
  run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
  directory = args.output.resolve() / run_id
  (directory / "tools").mkdir(parents=True)
  suite.BUILD = directory
  report = {
    "schema": 1, "run_id": run_id, "x2c": str(args.x2c),
    "x2c_sha256": suite.sha256(args.x2c), "profile": args.profile,
    "benchmarks": [],
  }
  for benchmark in manifest["benchmarks"]:
    entry = check_benchmark(
      benchmark, manifest, toolchain, directory / benchmark["name"], args,
    )
    report["benchmarks"].append(entry)
    suite.write_json(directory / "report.json", report)
    (directory / "report.md").write_text(render_report(report))
    print(f"{entry['name']}: native={'pass' if entry['native_driver']['passed'] else 'fail'}, "
          f"parser={'pass' if entry['x2c_parser']['passed'] else 'fail'}", flush=True)
  print(f"Report: {directory / 'report.md'}")
  return int(any(not entry[path]["passed"] for entry in report["benchmarks"]
                 for path in ("native_driver", "x2c_parser")))


if __name__ == "__main__":
  raise SystemExit(main())
