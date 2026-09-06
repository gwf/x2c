#!/usr/bin/env python3
"""Check and measure x2c against pinned C and Python reference data."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import gzip
import hashlib
import json
import math
import os
import platform
import re
import shlex
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent.parent
BUILD = ROOT.parent / "build" / "shootout"
LATEST = BUILD / "latest"
MANIFEST_PATH = ROOT / "benchmarks.json"
BASELINE_PATH = ROOT / "baseline.json"
CURRENT_JSON = ROOT / "results" / "current.json"
CURRENT_MARKDOWN = ROOT / "results" / "current.md"
DEFAULT_CFLAGS = "-O2 -DNDEBUG"
REFERENCE_IMPLEMENTATIONS = ("c", "python")
# Each benchmark carries two x2c programs. `main.x` writes the problem in
# x2c; `ported.x` keeps the C representation and uses x2c where the C was
# verbose. Both are checked and measured against the same pinned C median.
X2C_SOURCES = {"x2c": "main.x", "ported": "ported.x"}
X2C_IMPLEMENTATIONS = tuple(X2C_SOURCES)
IMPLEMENTATIONS = ("c", *X2C_IMPLEMENTATIONS, "python")


class HarnessError(RuntimeError):
  pass


def sha256(path: Path) -> str:
  digest = hashlib.sha256()
  with path.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
      digest.update(chunk)
  return digest.hexdigest()


def value_sha256(value: Any) -> str:
  data = json_text(value).encode("utf-8")
  return hashlib.sha256(data).hexdigest()


def tree_sha256(root: Path) -> str:
  digest = hashlib.sha256()
  for path in sorted(item for item in root.rglob("*") if item.is_file()):
    relative = path.relative_to(root).as_posix().encode("utf-8")
    digest.update(len(relative).to_bytes(8, "big"))
    digest.update(relative)
    digest.update(bytes.fromhex(sha256(path)))
  return digest.hexdigest()


def json_text(value: Any) -> str:
  return json.dumps(value, indent=2, sort_keys=True) + "\n"


def write_json(path: Path, value: Any) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json_text(value), encoding="utf-8")


def atomic_write(path: Path, text: str) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  descriptor, temporary = tempfile.mkstemp(
    prefix=f".{path.name}.", dir=path.parent
  )
  temporary_path = Path(temporary)
  try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
      output.write(text)
      output.flush()
      os.fsync(output.fileno())
    os.replace(temporary_path, path)
  finally:
    if temporary_path.exists():
      temporary_path.unlink()


def command(
  argv: list[str],
  *,
  cwd: Path | None = None,
  timeout: float | None = None,
  check: bool = True,
) -> subprocess.CompletedProcess[bytes]:
  own_process_group = timeout is not None and os.name == "posix"
  process = subprocess.Popen(
    argv,
    cwd=cwd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    start_new_session=own_process_group,
  )
  try:
    stdout, stderr = process.communicate(timeout=timeout)
  except subprocess.TimeoutExpired as error:
    if own_process_group:
      try:
        os.killpg(process.pid, signal.SIGKILL)
      except ProcessLookupError:
        pass
    elif process.poll() is None:
      process.kill()
    stdout, stderr = process.communicate()
    error.stdout = stdout
    error.stderr = stderr
    raise
  completed = subprocess.CompletedProcess(
    argv, process.returncode, stdout, stderr
  )
  if check and completed.returncode != 0:
    rendered = shlex.join(argv)
    output = completed.stdout.decode("utf-8", errors="replace")
    errors = completed.stderr.decode("utf-8", errors="replace")
    raise HarnessError(
      f"command failed ({completed.returncode}): {rendered}\n"
      f"stdout:\n{output}\nstderr:\n{errors}"
    )
  return completed


def command_text(argv: list[str], *, cwd: Path | None = None) -> str | None:
  try:
    completed = command(argv, cwd=cwd, check=False, timeout=10)
  except (OSError, subprocess.TimeoutExpired):
    return None
  if completed.returncode != 0:
    return None
  return completed.stdout.decode("utf-8", errors="replace").strip()


def git_receipt(path: Path) -> dict[str, Any]:
  revision = command_text(["git", "-C", str(path), "rev-parse", "HEAD"])
  status = command_text(["git", "-C", str(path), "status", "--porcelain"])
  paths = status.splitlines() if status else []
  return {
    "revision": revision,
    "dirty": bool(paths),
    "dirty_paths": paths,
  }


def validate_program_args(value: Any, owner: str) -> None:
  if (
    not isinstance(value, list)
    or not value
    or any(
      not isinstance(item, str)
      or re.fullmatch(r"[1-9][0-9]*", item) is None
      for item in value
    )
  ):
    raise HarnessError(f"{owner} requires positive integer arguments")


def load_manifest() -> dict[str, Any]:
  try:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError) as error:
    raise HarnessError(f"cannot load {MANIFEST_PATH}: {error}") from error
  if manifest.get("schema") != 1:
    raise HarnessError("unsupported benchmarks.json schema")
  benchmarks = manifest.get("benchmarks")
  profiles = manifest.get("profiles")
  if not isinstance(benchmarks, list) or not isinstance(profiles, dict):
    raise HarnessError("benchmarks.json requires benchmarks and profiles")

  names = [benchmark.get("name") for benchmark in benchmarks]
  if any(not isinstance(name, str) or not name for name in names):
    raise HarnessError("every benchmark requires a nonempty name")
  if len(names) != len(set(names)):
    raise HarnessError("benchmark names must be unique")
  discovered = {
    path.name
    for path in (ROOT / "benchmarks").iterdir()
    if path.is_dir()
  }
  if discovered != set(names):
    raise HarnessError(
      "benchmark directories differ from benchmarks.json: "
      f"manifest={sorted(names)}, directories={sorted(discovered)}"
    )

  expected_names = set(names)
  for profile_name, profile in profiles.items():
    if not isinstance(profile, dict) or set(profile) != expected_names:
      raise HarnessError(
        f"profile {profile_name!r} must cover every benchmark exactly"
      )
    for name, program_args in profile.items():
      validate_program_args(
        program_args, f"profile {profile_name!r} benchmark {name!r}"
      )

  for benchmark in benchmarks:
    name = benchmark["name"]
    source_root = ROOT / "benchmarks" / name
    for filename in ("main.c", "main.py", *X2C_SOURCES.values()):
      if not (source_root / filename).is_file():
        raise HarnessError(f"{name} is missing {filename}")
    checks = benchmark.get("checks")
    if not isinstance(checks, list) or not checks:
      raise HarnessError(f"benchmark {name!r} requires checks")
    for check_case in checks:
      validate_program_args(check_case.get("args"), f"check for {name!r}")
      expected = check_case.get("expected")
      expected_path = Path(expected) if isinstance(expected, str) else None
      if (
        expected_path is None
        or expected_path.is_absolute()
        or ".." in expected_path.parts
      ):
        raise HarnessError(f"invalid expected path for {name!r}")
      if not (source_root / expected_path).is_file():
        raise HarnessError(f"{name} is missing expected output {expected}")
  return manifest


def selected_benchmarks(
  manifest: dict[str, Any], names: list[str] | None
) -> list[dict[str, Any]]:
  benchmarks = manifest["benchmarks"]
  if not names:
    return benchmarks
  known = {item["name"]: item for item in benchmarks}
  unknown = sorted(set(names) - set(known))
  if unknown:
    raise HarnessError(f"unknown benchmark(s): {', '.join(unknown)}")
  if len(names) != len(set(names)):
    raise HarnessError("--only values must be unique")
  return [known[name] for name in names]


def resolve_toolchain(args: argparse.Namespace) -> dict[str, Any]:
  x2c = REPO / "builds/0/x2c"
  runtime = REPO / "builds/0/libx2c.a"
  include = REPO / "include"
  cc = shutil.which(args.cc)
  python = shutil.which(args.python) if args.action == "calibrate" else None
  missing = [
    str(path) for path in (x2c, runtime, include) if not path.exists()
  ]
  if missing:
    raise HarnessError(
      "x2c build is incomplete; missing: "
      + ", ".join(missing)
      + f"\nRun: make -C {shlex.quote(str(REPO))} build"
    )
  if not os.access(x2c, os.X_OK):
    raise HarnessError(f"x2c compiler is not executable: {x2c}")
  if not cc:
    raise HarnessError(f"C compiler not found: {args.cc}")
  if args.action == "calibrate" and not python:
    raise HarnessError(f"Python interpreter not found: {args.python}")

  build_mode_path = REPO / "etc/build-mode"
  build_mode = (
    build_mode_path.read_text(encoding="utf-8").strip()
    if build_mode_path.exists()
    else "unknown"
  )
  if build_mode != "optimize":
    raise HarnessError(
      f"x2c build mode is {build_mode!r}; run `make config-optimize`, clean, "
      "and rebuild before measuring"
    )
  if os.environ.get("BUILD_LTO", "0") != "0":
    raise HarnessError("the shootout requires BUILD_LTO=0")
  return {
    "x2c": x2c,
    "runtime": runtime,
    "include": include,
    "cc": cc,
    "python": python,
    "cflags": shlex.split(args.cflags),
    "build_mode": build_mode,
  }


def machine_receipt(toolchain: dict[str, Any]) -> dict[str, Any]:
  system = platform.system()
  cpu_model = None
  physical_cores = None
  memory_bytes = None
  translated = None
  power_source = None
  if system == "Darwin":
    cpu_model = command_text(["sysctl", "-n", "machdep.cpu.brand_string"])
    physical_cores = command_text(["sysctl", "-n", "hw.physicalcpu"])
    memory_bytes = command_text(["sysctl", "-n", "hw.memsize"])
    translated = command_text(["sysctl", "-n", "sysctl.proc_translated"])
    battery = command_text(["pmset", "-g", "batt"])
    if battery:
      power_source = battery.splitlines()[0]
  elif system == "Linux":
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
      match = re.search(
        r"^model name\s*:\s*(.+)$",
        cpuinfo.read_text(encoding="utf-8", errors="replace"),
        re.MULTILINE,
      )
      cpu_model = match.group(1) if match else None
    topology = command_text(["lscpu", "-p=SOCKET,CORE"])
    if topology:
      cores = {
        line
        for line in topology.splitlines()
        if line and not line.startswith("#")
      }
      physical_cores = len(cores)
    try:
      memory_bytes = os.sysconf("SC_PAGE_SIZE") * os.sysconf(
        "SC_PHYS_PAGES"
      )
    except (ValueError, OSError):
      memory_bytes = None

  try:
    load = list(os.getloadavg())
  except OSError:
    load = None
  return {
    "captured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "platform": platform.platform(),
    "system": system,
    "release": platform.release(),
    "machine": platform.machine(),
    "cpu_model": cpu_model,
    "logical_cores": os.cpu_count(),
    "physical_cores": int(physical_cores) if physical_cores else None,
    "memory_bytes": int(memory_bytes) if memory_bytes else None,
    "translated_process": translated,
    "power_source": power_source,
    "load_average": load,
    "harness_python": sys.version,
    "python": toolchain["python"],
    "python_version": (
      command_text([toolchain["python"], "--version"])
      if toolchain["python"]
      else None
    ),
    "cc": toolchain["cc"],
    "cc_version": command_text([toolchain["cc"], "--version"]),
    "cflags": toolchain["cflags"],
    "x2c_build_mode": toolchain["build_mode"],
    "x2c_binary_sha256": sha256(toolchain["x2c"]),
    "x2c_runtime_sha256": sha256(toolchain["runtime"]),
    "x2c_include_tree_sha256": tree_sha256(toolchain["include"]),
    "harness_source_sha256": {
      "benchmarks.json": sha256(MANIFEST_PATH),
      "tools/measure.c": sha256(ROOT / "tools/measure.c"),
      "tools/shootout.py": sha256(Path(__file__).resolve()),
    },
    "controlled_environment": {
      "LC_ALL": os.environ.get("LC_ALL"),
      "TZ": os.environ.get("TZ"),
    },
    "performance_environment": {
      name: os.environ[name]
      for name in (
        "DYLD_INSERT_LIBRARIES",
        "GLIBC_TUNABLES",
        "LD_PRELOAD",
        "MallocNanoZone",
        "MallocStackLogging",
      )
      if name in os.environ
    },
    "repository": git_receipt(REPO),
  }


def validate_machine(
  baseline: dict[str, Any],
  current: dict[str, Any],
  allow_mismatch: bool,
) -> None:
  calibrated = baseline["calibration"]["machine"]
  hard_fields = ("machine", "cpu_model", "logical_cores")
  mismatches = [
    f"{field}: calibrated={calibrated.get(field)!r}, "
    f"current={current.get(field)!r}"
    for field in hard_fields
    if calibrated.get(field) != current.get(field)
  ]
  if mismatches and not allow_mismatch:
    raise HarnessError(
      "machine does not match the pinned calibration:\n  "
      + "\n  ".join(mismatches)
      + "\nSet SHOOTOUT_ALLOW_MACHINE_MISMATCH=1 to override."
    )
  if mismatches:
    print("warning: machine mismatch override is active", file=sys.stderr)
  for field in ("system", "release", "platform", "power_source"):
    if calibrated.get(field) != current.get(field):
      print(
        f"warning: {field} changed since calibration: "
        f"{calibrated.get(field)!r} -> {current.get(field)!r}",
        file=sys.stderr,
      )


def dynamic_dependencies(path: Path) -> str | None:
  if platform.system() == "Darwin":
    return command_text(["otool", "-L", str(path)])
  if platform.system() == "Linux":
    return command_text(["ldd", str(path)])
  return None


def prepare_build(toolchain: dict[str, Any]) -> dict[str, Any]:
  if BUILD.exists():
    shutil.rmtree(BUILD)
  BUILD.mkdir(parents=True)
  measure = BUILD / "tools/measure"
  measure.parent.mkdir(parents=True)
  command(
    [
      toolchain["cc"],
      "-O2",
      "-DNDEBUG",
      str(ROOT / "tools/measure.c"),
      "-o",
      str(measure),
    ]
  )
  return {
    "schema": 1,
    "captured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "measure_sha256": sha256(measure),
    "benchmarks": {},
  }


def build_x2c(
  toolchain: dict[str, Any],
  benchmarks: list[dict[str, Any]],
  receipt: dict[str, Any],
) -> None:
  linker_flags = ["-rdynamic"] if platform.system() == "Linux" else []
  for benchmark in benchmarks:
    name = benchmark["name"]
    for implementation, filename in X2C_SOURCES.items():
      source = ROOT / "benchmarks" / name / filename
      generated = BUILD / name / implementation / "generated"
      binary = BUILD / name / implementation / "program"
      generated.mkdir(parents=True)
      translate_argv = [
        str(toolchain["x2c"]),
        "translate",
        "--out-dir",
        str(generated),
        str(source),
      ]
      started = time.perf_counter_ns()
      command(translate_argv, cwd=REPO)
      translate_ns = time.perf_counter_ns() - started
      generated_c = generated / f"{source.stem}.c"
      if not generated_c.exists():
        raise HarnessError(f"x2c did not produce {generated_c}")
      compile_argv = [
        toolchain["cc"],
        *toolchain["cflags"],
        *linker_flags,
        "-iquote",
        str(toolchain["include"]),
        str(generated_c),
        "-L",
        str(REPO / "builds/0"),
        "-lx2c",
        "-lm",
        "-o",
        str(binary),
      ]
      started = time.perf_counter_ns()
      command(compile_argv)
      compile_ns = time.perf_counter_ns() - started
      receipt["benchmarks"].setdefault(name, {})[implementation] = {
        "source": str(source.relative_to(ROOT)),
        "source_metrics": source_metrics(source),
        "binary": str(binary.relative_to(BUILD)),
        "binary_sha256": sha256(binary),
        "binary_bytes": binary.stat().st_size,
        "generated_c_sha256": sha256(generated_c),
        "dynamic_dependencies": dynamic_dependencies(binary),
        "translate_ns": translate_ns,
        "compile_ns": compile_ns,
        "translate_command": translate_argv,
        "compile_command": compile_argv,
      }
      print(f"built {name}: {implementation}", flush=True)


def build_references(
  toolchain: dict[str, Any],
  benchmarks: list[dict[str, Any]],
  receipt: dict[str, Any],
) -> None:
  python = toolchain["python"]
  if python is None:
    raise HarnessError("reference builds require Python")
  for benchmark in benchmarks:
    name = benchmark["name"]
    source_root = ROOT / "benchmarks" / name
    outputs = receipt["benchmarks"].setdefault(name, {})

    c_source = source_root / "main.c"
    c_binary = BUILD / name / "c/program"
    c_binary.parent.mkdir(parents=True)
    c_argv = [
      toolchain["cc"],
      *toolchain["cflags"],
      str(c_source),
      "-lm",
      "-o",
      str(c_binary),
    ]
    started = time.perf_counter_ns()
    command(c_argv)
    compile_ns = time.perf_counter_ns() - started
    outputs["c"] = {
      "source": str(c_source.relative_to(ROOT)),
      "source_metrics": source_metrics(c_source),
      "binary": str(c_binary.relative_to(BUILD)),
      "binary_sha256": sha256(c_binary),
      "binary_bytes": c_binary.stat().st_size,
      "dynamic_dependencies": dynamic_dependencies(c_binary),
      "compile_ns": compile_ns,
      "compile_command": c_argv,
    }

    python_source = source_root / "main.py"
    python_binary = BUILD / name / "python/program"
    python_binary.parent.mkdir(parents=True)
    source_text = python_source.read_text(encoding="utf-8")
    source_lines = source_text.splitlines(keepends=True)
    if source_lines and source_lines[0].startswith("#!"):
      source_text = "".join(source_lines[1:])
    python_binary.write_text(
      f"#!{python}\n" + source_text, encoding="utf-8"
    )
    python_binary.chmod(0o755)
    cache_root = BUILD / name / "python/cache"
    python_argv = [
      python,
      "-X",
      f"pycache_prefix={cache_root}",
      "-m",
      "py_compile",
      str(python_source),
    ]
    started = time.perf_counter_ns()
    command(python_argv)
    compile_ns = time.perf_counter_ns() - started
    outputs["python"] = {
      "source": str(python_source.relative_to(ROOT)),
      "source_metrics": source_metrics(python_source),
      "binary": str(python_binary.relative_to(BUILD)),
      "binary_sha256": sha256(python_binary),
      "binary_bytes": python_binary.stat().st_size,
      "dynamic_dependencies": None,
      "compile_ns": compile_ns,
      "compile_command": python_argv,
      "interpreter": python,
      "interpreter_version": command_text([python, "--version"]),
    }
    print(f"built {name}: C and Python references", flush=True)


def binary_path(name: str, implementation: str) -> Path:
  return BUILD / name / implementation / "program"


def run_captured(
  binary: Path, program_args: list[str], timeout: float
) -> bytes:
  try:
    completed = command(
      [str(binary), *program_args], timeout=timeout, check=False
    )
  except subprocess.TimeoutExpired as error:
    raise HarnessError(
      f"program timed out after {timeout}s: {binary}"
    ) from error
  if completed.returncode != 0:
    raise HarnessError(
      f"{binary} exited {completed.returncode}\n"
      + completed.stderr.decode("utf-8", errors="replace")
    )
  if completed.stderr:
    raise HarnessError(
      f"{binary} produced stderr:\n"
      + completed.stderr.decode("utf-8", errors="replace")
    )
  return completed.stdout


def compare_output(
  benchmark: str,
  implementation: str,
  check_case: dict[str, Any],
  expected: bytes,
  actual: bytes,
) -> str:
  comparison = check_case.get("comparison", {"kind": "exact"})
  kind = comparison.get("kind")
  if kind == "exact":
    if actual != expected:
      raise HarnessError(
        f"{benchmark}/{implementation} output differs for "
        f"{' '.join(check_case['args'])}\n"
        f"expected:\n{expected.decode(errors='replace')}\n"
        f"actual:\n{actual.decode(errors='replace')}"
      )
    return "exact"
  if kind != "numeric_lines":
    raise HarnessError(
      f"unknown output comparison {kind!r} for {benchmark}"
    )
  tolerance = comparison.get("absolute_tolerance")
  if not isinstance(tolerance, (int, float)) or tolerance < 0:
    raise HarnessError(f"invalid numeric tolerance for {benchmark}")
  try:
    expected_text = expected.decode("ascii")
    actual_text = actual.decode("ascii")
    expected_values = [float(line) for line in expected_text.splitlines()]
    actual_lines = actual_text.splitlines()
    actual_values = [float(line) for line in actual_lines]
  except (UnicodeDecodeError, ValueError) as error:
    raise HarnessError(
      f"{benchmark}/{implementation} produced nonnumeric output"
    ) from error
  format_pattern = re.compile(r"-?[0-9]+\.[0-9]{9}")
  if (
    not actual_text.endswith("\n")
    or len(actual_values) != len(expected_values)
    or any(format_pattern.fullmatch(line) is None for line in actual_lines)
    or any(
      abs(want - got) > tolerance
      for want, got in zip(expected_values, actual_values)
    )
  ):
    raise HarnessError(
      f"{benchmark}/{implementation} output is outside the "
      f"{tolerance:g} absolute tolerance or has the wrong format\n"
      f"expected:\n{expected_text}\nactual:\n{actual_text}"
    )
  return f"absolute tolerance {tolerance:g}"


def check_programs(
  benchmarks: list[dict[str, Any]],
  implementations: tuple[str, ...],
  timeout: float,
) -> dict[str, Any]:
  receipt: dict[str, Any] = {
    "schema": 1,
    "captured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    "implementations": list(implementations),
    "checks": [],
  }
  for benchmark in benchmarks:
    name = benchmark["name"]
    for check_case in benchmark["checks"]:
      expected_path = ROOT / "benchmarks" / name / check_case["expected"]
      expected = expected_path.read_bytes()
      outputs: dict[str, bytes] = {}
      comparison = ""
      for implementation in implementations:
        output = run_captured(
          binary_path(name, implementation),
          check_case["args"],
          timeout,
        )
        comparison = compare_output(
          name, implementation, check_case, expected, output
        )
        outputs[implementation] = output
        receipt["checks"].append(
          {
            "benchmark": name,
            "implementation": implementation,
            "args": check_case["args"],
            "comparison": comparison,
            "expected": str(expected_path.relative_to(ROOT)),
            "expected_sha256": hashlib.sha256(expected).hexdigest(),
            "stdout_sha256": hashlib.sha256(output).hexdigest(),
          }
        )
      if (
        comparison == "exact"
        and len(implementations) > 1
        and len(set(outputs.values())) != 1
      ):
        raise HarnessError(
          f"{name} fixed-case output differs across implementations"
        )
      print(
        f"checked {name} {' '.join(check_case['args'])}: "
        f"{', '.join(implementations)}; {comparison}",
        flush=True,
      )
  return receipt


def strip_c_comments(text: str) -> str:
  output: list[str] = []
  state = "code"
  quote = ""
  index = 0
  while index < len(text):
    char = text[index]
    following = text[index + 1] if index + 1 < len(text) else ""
    if state == "line":
      if char == "\n":
        output.append(char)
        state = "code"
      index += 1
      continue
    if state == "block":
      if char == "*" and following == "/":
        state = "code"
        index += 2
        continue
      if char == "\n":
        output.append(char)
      index += 1
      continue
    if state == "quote":
      output.append(char)
      if char == "\\" and following:
        output.append(following)
        index += 2
        continue
      if char == quote:
        state = "code"
      index += 1
      continue
    if char == "/" and following == "/":
      state = "line"
      index += 2
      continue
    if char == "/" and following == "*":
      state = "block"
      index += 2
      continue
    output.append(char)
    if char in ("'", '"'):
      state = "quote"
      quote = char
    index += 1
  return "".join(output)


def collapse_code_whitespace(text: str) -> str:
  output: list[str] = []
  state = "code"
  quote = ""
  pending_space = False
  index = 0
  while index < len(text):
    char = text[index]
    following = text[index + 1] if index + 1 < len(text) else ""
    if state == "quote":
      output.append(char)
      if char == "\\" and following:
        output.append(following)
        index += 2
        continue
      if char == quote:
        state = "code"
      index += 1
      continue
    if char.isspace():
      pending_space = bool(output)
      index += 1
      continue
    if pending_space:
      output.append(" ")
      pending_space = False
    output.append(char)
    if char in ("'", '"'):
      state = "quote"
      quote = char
    index += 1
  return "".join(output).strip()


def source_metrics(path: Path) -> dict[str, Any]:
  data = path.read_bytes()
  text = data.decode("utf-8")
  without_comments = strip_c_comments(text)
  normalized = collapse_code_whitespace(without_comments).encode("utf-8")
  return {
    "path": str(path.relative_to(ROOT)),
    "physical_lines": len(text.splitlines()),
    "nonblank_lines": sum(bool(line.strip()) for line in text.splitlines()),
    "source_lines": sum(
      bool(line.strip()) for line in without_comments.splitlines()
    ),
    "source_bytes": len(data),
    "game_style_gzip_bytes": len(
      gzip.compress(normalized, compresslevel=1, mtime=0)
    ),
    "sha256": hashlib.sha256(data).hexdigest(),
  }


def measure_once(
  measure: Path,
  binary: Path,
  program_args: list[str],
  timeout: float,
) -> dict[str, Any]:
  try:
    completed = command(
      [str(measure), str(binary), *program_args],
      timeout=timeout,
      check=False,
    )
  except subprocess.TimeoutExpired as error:
    raise HarnessError(
      f"timed run exceeded {timeout}s: {binary}"
    ) from error
  errors = completed.stderr.decode("utf-8", errors="replace")
  if completed.returncode != 0 or errors:
    raise HarnessError(
      f"measurement failed for {binary} "
      f"(status {completed.returncode})\nstderr:\n{errors}"
    )
  try:
    value = json.loads(completed.stdout)
  except json.JSONDecodeError as error:
    raise HarnessError(
      f"invalid measurement output: {completed.stdout!r}"
    ) from error
  if value["exit_code"] != 0 or value["signal"] != 0:
    raise HarnessError(f"measured child failed: {value}")
  return value


def percentile(values: list[float], percent: float) -> float:
  ordered = sorted(values)
  if len(ordered) == 1:
    return ordered[0]
  position = (len(ordered) - 1) * percent
  lower = math.floor(position)
  upper = math.ceil(position)
  if lower == upper:
    return ordered[lower]
  weight = position - lower
  return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def summarize(records: list[dict[str, Any]]) -> dict[str, Any]:
  elapsed = [record["elapsed_ns"] for record in records]
  cpu = [record["user_ns"] + record["system_ns"] for record in records]
  rss = [record["max_rss_bytes"] for record in records]
  median = statistics.median(elapsed)
  deviations = [abs(value - median) for value in elapsed]
  window = min(3, len(elapsed))
  first = statistics.median(elapsed[:window])
  last = statistics.median(elapsed[-window:])
  return {
    "samples": len(records),
    "median_elapsed_ns": median,
    "min_elapsed_ns": min(elapsed),
    "p95_elapsed_ns": percentile(elapsed, 0.95),
    "mad_elapsed_ns": statistics.median(deviations),
    "mean_cpu_ns": statistics.mean(cpu),
    "median_max_rss_bytes": statistics.median(rss),
    "max_rss_bytes": max(rss),
    "first_to_last_window_drift_percent": (
      (last / first - 1.0) * 100.0 if first else 0.0
    ),
  }


def compact_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
  fields = (
    "sample",
    "position",
    "elapsed_ns",
    "user_ns",
    "system_ns",
    "max_rss_bytes",
  )
  return [{field: record[field] for field in fields} for record in records]


def profile_comparison(benchmark: dict[str, Any]) -> dict[str, Any]:
  return benchmark["checks"][0].get("comparison", {"kind": "exact"})


def calibration_measurements(
  manifest: dict[str, Any],
  benchmarks: list[dict[str, Any]],
  toolchain: dict[str, Any],
  build_receipt: dict[str, Any],
  args: argparse.Namespace,
) -> dict[str, Any]:
  profile = manifest["profiles"][args.profile]
  measure = BUILD / "tools/measure"
  run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
  machine = machine_receipt(toolchain)
  machine["load_average_start"] = machine.pop("load_average")
  raw_path = BUILD / "calibration-raw.jsonl"
  results: dict[str, Any] = {}

  with raw_path.open("w", encoding="utf-8") as raw:
    for benchmark in benchmarks:
      name = benchmark["name"]
      program_args = profile[name]
      comparison = profile_comparison(benchmark)
      outputs = {
        implementation: run_captured(
          binary_path(name, implementation), program_args, args.timeout
        )
        for implementation in IMPLEMENTATIONS
      }
      for implementation in IMPLEMENTATIONS[1:]:
        compare_output(
          name,
          implementation,
          {"args": program_args, "comparison": comparison},
          outputs["c"],
          outputs[implementation],
        )
      if (
        comparison.get("kind", "exact") == "exact"
        and len(set(outputs.values())) != 1
      ):
        raise HarnessError(
          f"{name} profile output differs across implementations"
        )

      for warmup in range(1, args.warmups + 1):
        for implementation in IMPLEMENTATIONS:
          measure_once(
            measure,
            binary_path(name, implementation),
            program_args,
            args.timeout,
          )
        print(f"warmed {name} ({warmup}/{args.warmups})", flush=True)

      records = {implementation: [] for implementation in IMPLEMENTATIONS}
      for sample in range(1, args.samples + 1):
        offset = (sample - 1) % len(IMPLEMENTATIONS)
        order = IMPLEMENTATIONS[offset:] + IMPLEMENTATIONS[:offset]
        for position, implementation in enumerate(order, start=1):
          measured = measure_once(
            measure,
            binary_path(name, implementation),
            program_args,
            args.timeout,
          )
          record = {
            "schema": 1,
            "run_id": run_id,
            "benchmark": name,
            "implementation": implementation,
            "args": program_args,
            "sample": sample,
            "position": position,
            "binary_sha256": build_receipt["benchmarks"][name][
              implementation
            ]["binary_sha256"],
            **measured,
          }
          records[implementation].append(record)
          raw.write(json.dumps(record, sort_keys=True) + "\n")
          raw.flush()
        print(
          f"measured {name} calibration {sample}/{args.samples}",
          flush=True,
        )
      results[name] = {
        "args": program_args,
        "comparison": comparison,
        "stdout": base64.b64encode(outputs["c"]).decode("ascii"),
        "stdout_sha256": hashlib.sha256(outputs["c"]).hexdigest(),
        "implementations": {
          implementation: {
            "statistics": summarize(records[implementation]),
            "measurements": compact_records(records[implementation]),
          }
          for implementation in IMPLEMENTATIONS
        },
      }
  try:
    machine["load_average_end"] = list(os.getloadavg())
  except OSError:
    machine["load_average_end"] = None
  return {
    "schema": 1,
    "run_id": run_id,
    "profile": args.profile,
    "samples": args.samples,
    "warmups": args.warmups,
    "machine": machine,
    "benchmarks": results,
  }


def expected_receipt(benchmark: dict[str, Any]) -> list[dict[str, Any]]:
  name = benchmark["name"]
  result = []
  for check_case in benchmark["checks"]:
    path = ROOT / "benchmarks" / name / check_case["expected"]
    result.append(
      {
        "args": check_case["args"],
        "comparison": check_case.get("comparison", {"kind": "exact"}),
        "path": str(path.relative_to(ROOT)),
        "sha256": sha256(path),
      }
    )
  return result


def make_baseline(
  manifest: dict[str, Any],
  benchmarks: list[dict[str, Any]],
  build_receipt: dict[str, Any],
  calibration: dict[str, Any],
  args: argparse.Namespace,
) -> dict[str, Any]:
  return {
    "schema": 1,
    "methodology": {
      "profile": args.profile,
      "samples": args.samples,
      "warmups": args.warmups,
      "cflags": build_receipt["toolchain"]["cflags"],
      "execution_ratio": "ratio of implementation and C medians",
      "source_metric": "nonblank lines after C-style comment removal",
      "process_model": "fresh process per warmup and measured sample",
      "order": "rotating C,x2c,Python Latin order",
    },
    "calibration": {
      "run_id": calibration["run_id"],
      "captured_at_utc": calibration["machine"]["captured_at_utc"],
      "machine": calibration["machine"],
      "repository": calibration["machine"]["repository"],
    },
    "benchmarks": {
      benchmark["name"]: {
        "title": benchmark["title"],
        "args": calibration["benchmarks"][benchmark["name"]]["args"],
        "comparison": calibration["benchmarks"][benchmark["name"]][
          "comparison"
        ],
        "stdout": calibration["benchmarks"][benchmark["name"]]["stdout"],
        "stdout_sha256": calibration["benchmarks"][benchmark["name"]][
          "stdout_sha256"
        ],
        "checks": expected_receipt(benchmark),
        "c": {
          "source": build_receipt["benchmarks"][benchmark["name"]]["c"][
            "source_metrics"
          ],
          **calibration["benchmarks"][benchmark["name"]][
            "implementations"
          ]["c"],
        },
        "python": {
          "source": build_receipt["benchmarks"][benchmark["name"]]["python"][
            "source_metrics"
          ],
          **calibration["benchmarks"][benchmark["name"]][
            "implementations"
          ]["python"],
        },
      }
      for benchmark in benchmarks
    },
  }


def load_baseline(
  manifest: dict[str, Any], toolchain: dict[str, Any]
) -> dict[str, Any]:
  try:
    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError) as error:
    raise HarnessError(
      f"cannot load {BASELINE_PATH}: {error}; "
      "run `make shoot-calibrate`"
    ) from error
  if baseline.get("schema") != 1:
    raise HarnessError(
      "unsupported baseline schema; run `make shoot-calibrate`"
    )
  names = [benchmark["name"] for benchmark in manifest["benchmarks"]]
  if set(baseline.get("benchmarks", {})) != set(names):
    raise HarnessError(
      "baseline benchmark set differs from benchmarks.json; "
      "run `make shoot-calibrate`"
    )
  methodology = baseline.get("methodology", {})
  profile_name = methodology.get("profile")
  if profile_name != "local":
    raise HarnessError("the pinned baseline must use the local profile")
  if methodology.get("cflags") != toolchain["cflags"]:
    raise HarnessError(
      "current C flags differ from the calibration; "
      "run `make shoot-calibrate`"
    )

  for benchmark in manifest["benchmarks"]:
    name = benchmark["name"]
    entry = baseline["benchmarks"][name]
    if entry.get("args") != manifest["profiles"][profile_name][name]:
      raise HarnessError(
        f"{name} local arguments changed; run `make shoot-calibrate`"
      )
    for implementation, filename in (("c", "main.c"), ("python", "main.py")):
      current = source_metrics(ROOT / "benchmarks" / name / filename)
      if current != entry.get(implementation, {}).get("source"):
        raise HarnessError(
          f"{name}/{filename} differs from its pinned source metrics; "
          "run `make shoot-calibrate`"
        )
    if expected_receipt(benchmark) != entry.get("checks"):
      raise HarnessError(
        f"{name} expected-output contract changed; "
        "run `make shoot-calibrate`"
      )
  return baseline


def pinned_measurements(
  manifest: dict[str, Any],
  benchmarks: list[dict[str, Any]],
  baseline: dict[str, Any],
  toolchain: dict[str, Any],
  build_receipt: dict[str, Any],
  args: argparse.Namespace,
) -> dict[str, Any]:
  profile_name = baseline["methodology"]["profile"]
  profile = manifest["profiles"][profile_name]
  measure = BUILD / "tools/measure"
  run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
  machine = machine_receipt(toolchain)
  machine["load_average_start"] = machine.pop("load_average")
  raw_path = BUILD / "raw.jsonl"
  results: dict[str, Any] = {}

  with raw_path.open("w", encoding="utf-8") as raw:
    for benchmark in benchmarks:
      name = benchmark["name"]
      program_args = profile[name]
      baseline_entry = baseline["benchmarks"][name]
      expected = base64.b64decode(baseline_entry["stdout"])
      outputs: dict[str, bytes] = {}
      for implementation in X2C_IMPLEMENTATIONS:
        binary = binary_path(name, implementation)
        output = run_captured(binary, program_args, args.timeout)
        compare_output(
          name,
          implementation,
          {
            "args": program_args,
            "comparison": baseline_entry["comparison"],
          },
          expected,
          output,
        )
        outputs[implementation] = output
        for warmup in range(1, args.warmups + 1):
          measure_once(measure, binary, program_args, args.timeout)
          print(
            f"warmed {name} {implementation} ({warmup}/{args.warmups})",
            flush=True,
          )

      if (
        baseline_entry["comparison"].get("kind", "exact") == "exact"
        and len(set(outputs.values())) != 1
      ):
        raise HarnessError(f"{name} profile output differs between x2c files")

      records = {
        implementation: [] for implementation in X2C_IMPLEMENTATIONS
      }
      for sample in range(1, args.samples + 1):
        offset = (sample - 1) % len(X2C_IMPLEMENTATIONS)
        order = X2C_IMPLEMENTATIONS[offset:] + X2C_IMPLEMENTATIONS[:offset]
        for position, implementation in enumerate(order, start=1):
          measured = measure_once(
            measure,
            binary_path(name, implementation),
            program_args,
            args.timeout,
          )
          record = {
            "schema": 1,
            "run_id": run_id,
            "benchmark": name,
            "implementation": implementation,
            "args": program_args,
            "sample": sample,
            "position": position,
            "binary_sha256": build_receipt["benchmarks"][name][
              implementation
            ]["binary_sha256"],
            **measured,
          }
          records[implementation].append(record)
          raw.write(json.dumps(record, sort_keys=True) + "\n")
          raw.flush()
        print(f"measured {name} {sample}/{args.samples}", flush=True)
      results[name] = {
        "args": program_args,
        "implementations": {
          implementation: {
            "statistics": summarize(records[implementation]),
            "measurements": compact_records(records[implementation]),
          }
          for implementation in X2C_IMPLEMENTATIONS
        },
      }
  try:
    machine["load_average_end"] = list(os.getloadavg())
  except OSError:
    machine["load_average_end"] = None
  return {
    "schema": 1,
    "run_id": run_id,
    "profile": profile_name,
    "samples": args.samples,
    "warmups": args.warmups,
    "machine": machine,
    "benchmarks": results,
  }


def make_current(
  benchmarks: list[dict[str, Any]],
  baseline: dict[str, Any],
  baseline_sha256: str,
  build_receipt: dict[str, Any],
  run: dict[str, Any],
) -> dict[str, Any]:
  results: dict[str, Any] = {}
  factors: dict[str, list[float]] = {}
  measured = [
    implementation
    for implementation in X2C_IMPLEMENTATIONS
    if implementation
    in run["benchmarks"][benchmarks[0]["name"]]["implementations"]
  ]
  for benchmark in benchmarks:
    name = benchmark["name"]
    reference = baseline["benchmarks"][name]
    entry = run["benchmarks"][name]
    c_source = reference["c"]["source"]
    python_source = reference["python"]["source"]
    c_median = reference["c"]["statistics"]["median_elapsed_ns"]
    python_median = reference["python"]["statistics"]["median_elapsed_ns"]
    python_lines = python_source["source_lines"]

    row = {
      "time_python_over_c": python_median / c_median,
      "sloc_c_over_python": c_source["source_lines"] / python_lines,
    }
    programs: dict[str, Any] = {}
    for implementation in measured:
      build = build_receipt["benchmarks"][name][implementation]
      source = build["source_metrics"]
      result = entry["implementations"][implementation]
      row[f"time_{implementation}_over_c"] = (
        result["statistics"]["median_elapsed_ns"] / c_median
      )
      row[f"sloc_{implementation}_over_python"] = (
        source["source_lines"] / python_lines
      )
      programs[implementation] = {
        "source": source,
        "statistics": result["statistics"],
        "measurements": result["measurements"],
        "build": {
          field: build[field]
          for field in (
            "binary_bytes",
            "binary_sha256",
            "compile_ns",
            "generated_c_sha256",
            "translate_ns",
          )
        },
      }
    for key, value in row.items():
      factors.setdefault(key, []).append(value)
    results[name] = {
      "title": benchmark["title"],
      "args": entry["args"],
      "factors": row,
      **programs,
      "references": {
        implementation: {
          "source": reference[implementation]["source"],
          "statistics": reference[implementation]["statistics"],
        }
        for implementation in REFERENCE_IMPLEMENTATIONS
      },
    }
  return {
    "schema": 2,
    "benchmark_order": [benchmark["name"] for benchmark in benchmarks],
    "x2c_implementations": measured,
    "ratio_definition": "ratio of implementation and C medians",
    "source_ratio_definition": "source_lines / Python source_lines",
    "baseline_sha256": baseline_sha256,
    "run_id": run["run_id"],
    "profile": run["profile"],
    "samples": run["samples"],
    "warmups": run["warmups"],
    "machine": run["machine"],
    "benchmarks": results,
    "arithmetic_mean": {
      key: statistics.mean(values) for key, values in factors.items()
    },
    "median": {
      key: statistics.median(values) for key, values in factors.items()
    },
  }


def render_current(current: dict[str, Any]) -> str:
  measured = current["x2c_implementations"]
  columns = [
    *((f"Time {name}/C", f"time_{name}_over_c") for name in measured),
    ("Time Python/C", "time_python_over_c"),
    *(
      (f"SLOC {name}/Python", f"sloc_{name}_over_python")
      for name in measured
    ),
    ("SLOC C/Python", "sloc_c_over_python"),
  ]
  lines = [
    "# x2c language shootout result",
    "",
    f"- Run: `{current['run_id']}`",
    f"- Baseline: `{current['baseline_sha256'][:16]}`",
    f"- Profile: `{current['profile']}`",
    f"- Samples: {current['samples']} fresh-process x2c measurements after "
    f"{current['warmups']} warmup(s)",
    "- `x2c` is each benchmark's `main.x`, which writes the problem in x2c.",
    "  `ported` is its `ported.x`, which keeps the C representation and uses",
    "  x2c only where the C was verbose.",
    "- Time uses C as the implicit 1.00 baseline; SLOC uses Python as the",
    "  implicit 1.00 baseline. Larger values mean more cost.",
    "",
    "| Benchmark | " + " | ".join(label for label, _ in columns) + " |",
    "| --- |" + " ---: |" * len(columns),
  ]
  for name in current["benchmark_order"]:
    factors = current["benchmarks"][name]["factors"]
    cells = " | ".join(f"{factors[key]:.2f}" for _, key in columns)
    lines.append(f"| {name} | {cells} |")
  for label, summary in (
    ("Median", current["median"]),
    ("Arithmetic mean", current["arithmetic_mean"]),
  ):
    cells = " | ".join(f"**{summary[key]:.2f}**" for _, key in columns)
    lines.append(f"| **{label}** | {cells} |")
  lines.extend(
    [
      "",
      "The median and the mean are orientation aids, not composite scores.",
      "One benchmark dominates the mean, so the median is the more useful",
      "of the two; read the per-benchmark rows for anything that matters.",
      "",
    ]
  )
  return "\n".join(lines)


def write_latest(
  build_receipt: dict[str, Any],
  check_receipt: dict[str, Any],
  run: dict[str, Any],
  current: dict[str, Any],
) -> None:
  LATEST.mkdir(parents=True, exist_ok=True)
  write_json(LATEST / "build.json", build_receipt)
  write_json(LATEST / "check.json", check_receipt)
  write_json(LATEST / "receipt.json", run)
  write_json(LATEST / "summary.json", current)
  (LATEST / "summary.md").write_text(
    render_current(current), encoding="utf-8"
  )


def promote_current(current: dict[str, Any]) -> None:
  atomic_write(CURRENT_JSON, json_text(current))
  atomic_write(CURRENT_MARKDOWN, render_current(current))


def run_pinned(
  args: argparse.Namespace,
  manifest: dict[str, Any],
  benchmarks: list[dict[str, Any]],
  toolchain: dict[str, Any],
) -> None:
  baseline = load_baseline(manifest, toolchain)
  if args.profile != baseline["methodology"]["profile"]:
    raise HarnessError(
      f"the pinned baseline uses profile "
      f"{baseline['methodology']['profile']!r}, not {args.profile!r}"
    )
  start_machine = machine_receipt(toolchain)
  validate_machine(baseline, start_machine, args.allow_machine_mismatch)
  build_receipt = prepare_build(toolchain)
  build_receipt["toolchain"] = start_machine
  build_x2c(toolchain, benchmarks, build_receipt)
  check_receipt = check_programs(benchmarks, X2C_IMPLEMENTATIONS, args.timeout)
  run = pinned_measurements(
    manifest, benchmarks, baseline, toolchain, build_receipt, args
  )
  baseline_hash = sha256(BASELINE_PATH)
  current = make_current(
    benchmarks, baseline, baseline_hash, build_receipt, run
  )
  write_latest(build_receipt, check_receipt, run, current)
  markdown = render_current(current)
  print()
  print(markdown)
  print(f"raw results: {LATEST}", flush=True)
  if args.action == "update":
    promote_current(current)
    print(
      "updated examples/shootout/results/current.md and current.json",
      flush=True,
    )


def calibrate(
  args: argparse.Namespace,
  manifest: dict[str, Any],
  benchmarks: list[dict[str, Any]],
  toolchain: dict[str, Any],
) -> None:
  build_receipt = prepare_build(toolchain)
  build_receipt["toolchain"] = machine_receipt(toolchain)
  build_x2c(toolchain, benchmarks, build_receipt)
  build_references(toolchain, benchmarks, build_receipt)
  check_receipt = check_programs(
    benchmarks, IMPLEMENTATIONS, args.timeout
  )
  calibration = calibration_measurements(
    manifest, benchmarks, toolchain, build_receipt, args
  )
  baseline = make_baseline(
    manifest, benchmarks, build_receipt, calibration, args
  )
  baseline_hash = value_sha256(baseline)
  x2c_run = {
    "schema": 1,
    "run_id": calibration["run_id"],
    "profile": calibration["profile"],
    "samples": calibration["samples"],
    "warmups": calibration["warmups"],
    "machine": calibration["machine"],
    "benchmarks": {
      name: {
        "args": result["args"],
        "implementations": {
          implementation: result["implementations"][implementation]
          for implementation in X2C_IMPLEMENTATIONS
        },
      }
      for name, result in calibration["benchmarks"].items()
    },
  }
  current = make_current(
    benchmarks, baseline, baseline_hash, build_receipt, x2c_run
  )
  write_latest(build_receipt, check_receipt, calibration, current)
  atomic_write(BASELINE_PATH, json_text(baseline))
  promote_current(current)
  markdown = render_current(current)
  print()
  print(markdown)
  print("updated examples/shootout/baseline.json", flush=True)
  print(
    "updated examples/shootout/results/current.md and current.json",
    flush=True,
  )
  print(f"raw results: {LATEST}", flush=True)


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("action", choices=("run", "update", "calibrate"))
  parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
  parser.add_argument(
    "--python",
    default=os.environ.get("SHOOTOUT_PYTHON", sys.executable),
  )
  parser.add_argument(
    "--cflags",
    default=os.environ.get("SHOOTOUT_CFLAGS", DEFAULT_CFLAGS),
  )
  parser.add_argument("--profile", default="local")
  parser.add_argument("--samples", type=int, default=12)
  parser.add_argument("--warmups", type=int, default=1)
  parser.add_argument("--timeout", type=float, default=3600.0)
  parser.add_argument(
    "--only",
    action="append",
    help="run one benchmark; repeat to select more",
  )
  parser.add_argument(
    "--allow-machine-mismatch",
    action="store_true",
    default=os.environ.get("SHOOTOUT_ALLOW_MACHINE_MISMATCH") == "1",
  )
  args = parser.parse_args()
  if args.samples < 1:
    parser.error("--samples must be positive")
  if args.warmups < 0:
    parser.error("--warmups must be nonnegative")
  if args.timeout <= 0:
    parser.error("--timeout must be positive")
  if args.action == "calibrate" and args.samples % len(IMPLEMENTATIONS):
    parser.error(
      f"calibration samples must be a multiple of {len(IMPLEMENTATIONS)}"
    )
  if args.action in ("update", "calibrate") and args.only:
    parser.error(f"{args.action} requires the complete benchmark set")
  if args.action in ("update", "calibrate") and (
    args.samples != 12 or args.warmups != 1
  ):
    parser.error(f"{args.action} requires 12 samples and one warmup")
  if args.action == "calibrate" and args.profile != "local":
    parser.error("the tracked calibration must use the local profile")
  return args


def main() -> int:
  os.environ["LC_ALL"] = "C"
  os.environ["TZ"] = "UTC"
  if hasattr(time, "tzset"):
    time.tzset()
  args = parse_args()
  try:
    manifest = load_manifest()
    if args.profile not in manifest["profiles"]:
      raise HarnessError(f"unknown profile: {args.profile}")
    benchmarks = selected_benchmarks(manifest, args.only)
    toolchain = resolve_toolchain(args)
    if args.action == "calibrate":
      calibrate(args, manifest, benchmarks, toolchain)
    else:
      run_pinned(args, manifest, benchmarks, toolchain)
    return 0
  except HarnessError as error:
    print(f"shootout error: {error}", file=sys.stderr)
    return 1
  except KeyboardInterrupt:
    print("shootout interrupted", file=sys.stderr)
    return 130


if __name__ == "__main__":
  raise SystemExit(main())
