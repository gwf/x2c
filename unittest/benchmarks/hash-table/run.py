#!/usr/bin/env python3
"""Run the additive runtime-free U32Map benchmark campaign."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "unittest/benchmarks/hash-table"
BUILD = ROOT / "unittest/build/benchmarks/hash-table"
SCALAR_BUILD = BUILD / "x2c"
GENERATED = SCALAR_BUILD / "generated"
BIN = SCALAR_BUILD / "bin"
JACKSON_SOURCE = BUILD / "jackson/source"
UDB3_SOURCE = BUILD / "udb3/source"

JACKSON_URL = "https://github.com/JacksonAllan/c_cpp_hash_tables_benchmark.git"
JACKSON_COMMIT = "71f0e4075b30d3b0e9baadc07bc7e889b04836ea"
UDB3_URL = "https://github.com/attractivechaos/udb3.git"
UDB3_COMMIT = "4ac803847c27accc3ddc66f13caffcbd099aa5d2"
KHASHL_COMMIT = "97a0fcb790b43b9e5da8994f4671021fec036f19"
KHASHL_SHA256 = (
    "ae4a4faa2aee719b0d7a9ab9bc51a50b"
    "aea3b5d0b37e948dc2702c7cd8f86ff0"
)
KHASHL_URL = (
    "https://raw.githubusercontent.com/attractivechaos/klib/"
    f"{KHASHL_COMMIT}/khashl.h"
)

UDB3_COHORT = [
    "x2c_u32",
    "verstable",
    "khashl",
    "CC",
    "STC",
    "robin_hood",
    "ska_bytell",
    "unordered_dense",
]
JACKSON_MATCHED = ["x2c_u32", "ankerl", "tsl", "ska", "std"]
JACKSON_FIXED = ["x2c_u32", "boost", "absl", "ankerl"]

PROFILE_FLAGS = {
    "standard": ["-O3", "-DNDEBUG"],
    "lto": ["-O3", "-DNDEBUG", "-flto"],
}


class CampaignError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_text(command: list[str]) -> str:
    return shlex.join(str(part) for part in command)


class Runner:
    def __init__(self, results: Path, cc: str, cxx: str) -> None:
        self.results = results
        self.cc = cc
        self.cxx = cxx
        self.command_log = results / "commands.log"

    def run(
        self,
        command: list[str | Path],
        *,
        cwd: Path = ROOT,
        output: Path | None = None,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        rendered = [str(part) for part in command]
        with self.command_log.open("a", encoding="utf-8") as log:
            log.write(f"cwd={cwd}\n$ {command_text(rendered)}\n")
        print(f"[{cwd.name}] {command_text(rendered)}", flush=True)
        completed = subprocess.run(
            rendered,
            cwd=cwd,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if output is not None:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(completed.stdout, encoding="utf-8")
        if completed.returncode:
            sys.stdout.write(completed.stdout)
            raise CampaignError(
                f"command failed ({completed.returncode}): "
                f"{command_text(rendered)}"
            )
        return completed


def ensure_checkout(
    runner: Runner, path: Path, url: str, commit: str
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not (path / ".git").is_dir():
        runner.run(["git", "clone", url, path])
    exists = subprocess.run(
        ["git", "-C", str(path), "cat-file", "-e", f"{commit}^{{commit}}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0
    if not exists:
        runner.run(["git", "fetch", "origin", commit], cwd=path)
    head = subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()
    if head == commit:
        return
    dirty = subprocess.check_output(
        ["git", "-C", str(path), "status", "--porcelain"], text=True
    ).strip()
    if dirty:
        raise CampaignError(f"refusing to replace dirty checkout at {path}")
    runner.run(["git", "checkout", "--detach", commit], cwd=path)


def translate_scalar(runner: Runner) -> dict[str, str]:
    source = HERE / "x2c/u32-map.x"
    compiler = ROOT / "builds/0/x2c"
    manifest_path = SCALAR_BUILD / "translation.json"
    current = {
        "source": str(source.relative_to(ROOT)),
        "source_sha256": sha256(source),
        "compiler": str(compiler.relative_to(ROOT)),
        "compiler_sha256": sha256(compiler),
    }
    generated_files = [GENERATED / "u32-map.c", GENERATED / "u32-map.h"]
    cached = False
    if manifest_path.exists() and all(
        path.exists() for path in generated_files
    ):
        prior = json.loads(manifest_path.read_text(encoding="utf-8"))
        cached = prior == current
    if not cached:
        GENERATED.mkdir(parents=True, exist_ok=True)
        runner.run(
            [compiler, "translate", "--out-dir", GENERATED, source],
            output=runner.results / "translation.log",
        )
        manifest_path.write_text(
            json.dumps(current, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    else:
        (runner.results / "translation.log").write_text(
            "reused generated C; source and compiler checksums match\n",
            encoding="utf-8",
        )
    current["generated_c_sha256"] = sha256(GENERATED / "u32-map.c")
    current["generated_h_sha256"] = sha256(GENERATED / "u32-map.h")
    current["cache"] = "hit" if cached else "miss"
    return current


def compile_scalar_object(runner: Runner, profile: str) -> Path:
    BIN.mkdir(parents=True, exist_ok=True)
    output = SCALAR_BUILD / f"u32-map-bridge-{profile}.o"
    command = [
        runner.cc,
        "-std=c11",
        *PROFILE_FLAGS[profile],
        "-Wall",
        "-Wextra",
        "-Werror",
        "-I",
        GENERATED,
        "-I",
        HERE / "x2c",
        "-iquote",
        ROOT / "include",
        "-c",
        HERE / "x2c/u32-map-bridge.c",
        "-o",
        output,
    ]
    runner.run(command, output=runner.results / f"compile-u32-{profile}.log")
    return output


def compile_scalar_profile_object(runner: Runner) -> Path:
    BIN.mkdir(parents=True, exist_ok=True)
    output = SCALAR_BUILD / "u32-map-bridge-counters.o"
    runner.run([
        runner.cc, "-std=c11", *PROFILE_FLAGS["standard"],
        "-DU32_MAP_PROFILE", "-Wall", "-Wextra", "-Werror",
        "-I", GENERATED, "-I", HERE / "x2c",
        "-iquote", ROOT / "include", "-c",
        HERE / "x2c/u32-map-bridge.c", "-o", output,
    ], output=runner.results / "compile-u32-counters.log")
    return output


def audit_binary(
    runner: Runner, binary: Path, label: str, directory: Path
) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    unresolved = runner.run(["nm", "-u", binary]).stdout
    (directory / f"{label}-nm-u.txt").write_text(unresolved, encoding="utf-8")
    linked = runner.run(["otool", "-L", binary]).stdout
    (directory / f"{label}-otool-L.txt").write_text(linked, encoding="utf-8")
    lowered = unresolved.lower()
    forbidden = [name for name in ("x2c", "var", "scope", "bytes", "block")
                 if name in lowered]
    if label.startswith("x2c-u32") and forbidden:
        names = ", ".join(forbidden)
        raise CampaignError(f"runtime symbol audit failed: {names}")
    if label.startswith("x2c-u32") and "libx2c" in linked.lower():
        raise CampaignError("runtime-free binary links libx2c")


def ensure_khashl(runner: Runner) -> Path:
    vendor = BUILD / "vendor/khashl.h"
    if not vendor.exists() or sha256(vendor) != KHASHL_SHA256:
        vendor.parent.mkdir(parents=True, exist_ok=True)
        downloaded = vendor.with_suffix(".download")
        runner.run(["curl", "-fsSL", KHASHL_URL, "-o", downloaded])
        if sha256(downloaded) != KHASHL_SHA256:
            raise CampaignError("downloaded khashl.h checksum mismatch")
        downloaded.replace(vendor)
    return vendor


def validate_scalar(runner: Runner, translation: dict[str, str]) -> None:
    BIN.mkdir(parents=True, exist_ok=True)
    vendor = ensure_khashl(runner)
    normal = BIN / "test-u32-map"
    common = [
        "-I", GENERATED,
        "-I", HERE / "x2c",
        "-I", vendor.parent,
        "-iquote", ROOT / "include",
    ]
    runner.run([
        runner.cc, "-std=c11", *PROFILE_FLAGS["standard"],
        "-Wall", "-Wextra", "-Werror", *common,
        HERE / "x2c/u32-map-bridge.c", HERE / "x2c/test-u32-map.c",
        "-o", normal,
    ], output=runner.results / "compile-differential.log")
    runner.run([normal], output=runner.results / "differential.log")
    audit_binary(runner, normal, "x2c-u32-test", runner.results / "symbols")

    sanitizer = BIN / "test-u32-map-sanitize"
    runner.run([
        runner.cc, "-std=c11", "-O1", "-g", "-fno-omit-frame-pointer",
        "-fsanitize=address,undefined", "-Wall", "-Wextra", "-Werror",
        *common, HERE / "x2c/u32-map-bridge.c",
        HERE / "x2c/test-u32-map.c", "-o", sanitizer,
    ], output=runner.results / "compile-sanitizer.log")
    environment = os.environ.copy()
    environment["ASAN_OPTIONS"] = "detect_leaks=0"
    runner.run(
        [sanitizer], env=environment,
        output=runner.results / "sanitizer.log",
    )
    (runner.results / "translation.json").write_text(
        json.dumps(translation, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def jackson_single_define(implementation: str | None) -> str | None:
    mapping = {
        "x2c_u32": "X2C_SHIM_SCALAR_ONLY",
        "ankerl": "X2C_SHIM_ANKERL_ONLY",
        "tsl": "X2C_SHIM_TSL_ONLY",
        "ska": "X2C_SHIM_SKA_ONLY",
        "std": "X2C_SHIM_STD_ONLY",
        "boost": "X2C_SHIM_BOOST_ONLY",
        "absl": "X2C_SHIM_ABSL_ONLY",
    }
    if implementation is None:
        return None
    if implementation not in mapping:
        raise CampaignError(
            f"{implementation} is not a Jackson implementation"
        )
    return mapping[implementation]


def prepare_jackson(runner: Runner) -> None:
    ensure_checkout(runner, JACKSON_SOURCE, JACKSON_URL, JACKSON_COMMIT)
    (JACKSON_SOURCE / "shims/x2c_u32_map").mkdir(parents=True, exist_ok=True)
    shutil.copy2(HERE / "jackson/u32-config.h", JACKSON_SOURCE / "config.h")
    shutil.copy2(
        HERE / "jackson/u32-shim.h",
        JACKSON_SOURCE / "shims/x2c_u32_map/shim.h",
    )
    shutil.copy2(
        HERE / "x2c/u32-map-abi.h", JACKSON_SOURCE / "x2c-u32-map-abi.h"
    )


def parse_jackson(
    csv_path: Path, profile: str, policy: str, output: Path
) -> None:
    operation_names = {
        "Total time to insert": "insert_nonexisting",
        "Time to erase 1,000 existing": "erase_existing",
        "Time to replace": "replace_existing",
        "Time to erase 1,000 nonexisting": "erase_nonexisting",
        "Time to look up 1,000 existing": "lookup_existing",
        "Time to look up 1,000 nonexisting": "lookup_nonexisting",
        "Time to iterate": "iterate",
    }
    entries: list[str] = []
    implementation = ""
    operation = ""
    rows: list[list[str]] = []
    with csv_path.open(encoding="utf-8") as source:
        for raw in source:
            fields = raw.rstrip("\n").split(";")
            if fields[0] == "N":
                entries = [value for value in fields[1:] if value]
            elif len(fields) == 1 and fields[0].count(":") >= 2:
                _, description, implementation = fields[0].split(":", 2)
                operation = next(
                    (name for prefix, name in operation_names.items()
                     if description.startswith(prefix)),
                    "",
                )
            elif fields[0] == "Adjusted average" and operation:
                values = [value for value in fields[1:] if value]
                for count, value in zip(entries, values):
                    normalized = float(value)
                    if operation == "insert_nonexisting":
                        normalized = normalized * 1000.0 / int(count)
                    else:
                        normalized /= 1000.0
                    rows.append([
                        profile, policy, implementation, count, operation,
                        f"{normalized:.6f}",
                    ])
    with output.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "profile", "policy", "implementation", "entries", "operation",
            "ns_per_operation",
        ])
        writer.writerows(rows)


def run_jackson(
    runner: Runner,
    mode: str,
    profile: str,
    policy: str,
    scalar_object: Path,
    implementation: str | None,
) -> Path:
    prepare_jackson(runner)
    result = runner.results / "jackson" / profile / policy
    result.mkdir(parents=True, exist_ok=True)
    binary = BIN / f"jackson-{mode}-{profile}-{policy}"
    mode_flags: list[str] = []
    if mode == "smoke":
        mode_flags = [
            "-DKEY_COUNT=5000",
            "-DKEY_COUNT_MEASUREMENT_INTERVAL=500",
            "-DRUN_COUNT=2",
            "-DDISCARDED_RUNS_COUNT=0",
            "-DAPPROXIMATE_CACHE_SIZE=1000000",
            "-DMILLISECOND_COOLDOWN_BETWEEN_BENCHMARKS=0",
        ]
    policy_flags = ["-DX2C_FIXED_POLICY_PROFILE"] if policy == "fixed" else []
    single = jackson_single_define(implementation)
    if single:
        policy_flags.append(f"-D{single}")
    runner.run([
        runner.cxx, "-I.", "-std=c++20", *PROFILE_FLAGS[profile],
        "-Wall", "-Wpedantic", *mode_flags, *policy_flags,
        "main.cpp", scalar_object, "-o", binary,
    ], cwd=JACKSON_SOURCE, output=result / "compile.log")
    runner.run([binary], cwd=result, output=result / "run.log")
    csv_files = sorted(result.glob("*.csv"))
    if len(csv_files) != 1:
        raise CampaignError(f"Jackson produced {len(csv_files)} CSV files")
    parse_jackson(csv_files[0], profile, policy, result / "summary.tsv")
    audit_binary(runner, binary, f"x2c-u32-jackson-{profile}-{policy}",
                 result / "symbols")
    return result / "summary.tsv"


def prepare_udb3(runner: Runner) -> None:
    ensure_checkout(runner, UDB3_SOURCE, UDB3_URL, UDB3_COMMIT)


def compile_udb_scalar(
    runner: Runner, profile: str, scalar_object: Path
) -> Path:
    binary = BIN / f"udb3-x2c-u32-{profile}"
    runner.run([
        runner.cc, "-std=c11", *PROFILE_FLAGS[profile],
        "-Wall", "-Wextra", "-Werror", "-I", HERE / "x2c",
        "-I", UDB3_SOURCE, HERE / "udb3/u32-test.c", scalar_object,
        "-o", binary,
    ], output=runner.results / f"compile-udb3-x2c-u32-{profile}.log")
    return binary


def compile_production_control(runner: Runner) -> Path:
    binary = BIN / "udb3-x2c-production-standard"
    runner.run([
        runner.cc, "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-I", UDB3_SOURCE, "-iquote", ROOT / "include",
        HERE / "udb3/test.c", "-L", ROOT / "builds/0", "-lx2c",
        "-lm", "-o", binary,
    ], output=runner.results / "compile-udb3-production-standard.log")
    return binary


def compile_typed_control(runner: Runner) -> Path:
    binary = BIN / "udb3-x2c-typed-standard"
    runner.run([
        runner.cc, "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-I", UDB3_SOURCE, "-iquote", ROOT / "include",
        HERE / "udb3/typed-test.c", "-L", ROOT / "builds/0", "-lx2c",
        "-lm", "-o", binary,
    ], output=runner.results / "compile-udb3-typed-standard.log")
    return binary


def translate_flat(runner: Runner) -> Path:
    GENERATED.mkdir(parents=True, exist_ok=True)
    runner.run(
        [ROOT / "builds/0/x2c", "translate", "--out-dir", GENERATED,
         HERE / "x2c/flat-map.x"],
        output=runner.results / "translation-flat.log",
    )
    return GENERATED / "flat-map.c"


def compile_flat_control(runner: Runner) -> Path:
    generated = translate_flat(runner)
    binary = BIN / "udb3-x2c-flat-standard"
    runner.run([
        runner.cc, "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-I", UDB3_SOURCE, "-iquote", ROOT / "include", "-I", GENERATED,
        HERE / "udb3/flat-test.c", generated,
        "-L", ROOT / "builds/0", "-lx2c", "-lm", "-o", binary,
    ], output=runner.results / "compile-udb3-flat-standard.log")
    return binary


def compile_meta_control(runner: Runner) -> Path:
    generated = translate_flat(runner)
    binary = BIN / "udb3-x2c-meta-standard"
    runner.run([
        runner.cc, "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-I", UDB3_SOURCE, "-iquote", ROOT / "include", "-I", GENERATED,
        HERE / "udb3/meta-test.c", generated,
        "-L", ROOT / "builds/0", "-lx2c", "-lm", "-o", binary,
    ], output=runner.results / "compile-udb3-meta-standard.log")
    return binary


def compile_wide_control(runner: Runner) -> Path:
    generated = translate_flat(runner)
    binary = BIN / "udb3-x2c-wide-standard"
    runner.run([
        runner.cc, "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-I", UDB3_SOURCE, "-iquote", ROOT / "include", "-I", GENERATED,
        HERE / "udb3/wide-test.c", generated,
        "-L", ROOT / "builds/0", "-lx2c", "-lm", "-o", binary,
    ], output=runner.results / "compile-udb3-wide-standard.log")
    return binary


def compile_khashl_backend_control(runner: Runner) -> Path:
    vendor = ensure_khashl(runner)
    binary = BIN / "udb3-x2c-khashl-standard"
    runner.run([
        runner.cc, "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-I", UDB3_SOURCE, "-iquote", ROOT / "include",
        "-I", HERE / "x2c", "-I", vendor.parent,
        HERE / "udb3/khashl-backend-test.c", HERE / "x2c/khashl-map.c",
        "-L", ROOT / "builds/0", "-lx2c", "-lm", "-o", binary,
    ], output=runner.results / "compile-udb3-khashl-backend-standard.log")
    return binary


def compile_udb_external(
    runner: Runner, implementation: str, profile: str
) -> Path:
    directory = UDB3_SOURCE / implementation
    c_driver = runner.cc + " " + " ".join(PROFILE_FLAGS[profile][1:])
    cxx_driver = runner.cxx + " " + " ".join(PROFILE_FLAGS[profile][1:])
    runner.run([
        "make", "-B", f"CC={c_driver}", f"CXX={cxx_driver}", "run-test"
    ], cwd=directory, output=runner.results /
       f"compile-udb3-{implementation}-{profile}.log")
    binary = directory / "run-test"
    if not binary.exists():
        raise CampaignError(f"udb3 did not build {binary}")
    return binary


def parse_udb_log(
    log: Path, profile: str, implementation: str, rows: list[list[str]]
) -> None:
    for line in log.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if fields[0] not in ("MI", "MD"):
            continue
        rows.append([profile, implementation, *fields])


def verify_udb(
    rows: list[list[str]], expected_cohort: list[str], mode: str
) -> None:
    expected: dict[tuple[str, str, str], tuple[str, str, str]] = {}
    cohort_rows = 0
    for row in rows:
        profile, implementation, workload, inputs, size, checksum = row[:6]
        key = profile, workload, inputs
        value = size, checksum, implementation
        if implementation in expected_cohort:
            cohort_rows += 1
        if key not in expected:
            expected[key] = value
        elif expected[key][:2] != value[:2]:
            owner = expected[key][2]
            raise CampaignError(
                f"udb3 mismatch at {key}: {implementation} has {value[:2]}, "
                f"expected {expected[key][:2]} from {owner}"
            )
    checkpoints = 10 if mode == "smoke" else 22
    required = checkpoints * len(expected_cohort)
    if cohort_rows != required:
        raise CampaignError(
            f"udb3 cohort produced {cohort_rows} rows; expected {required}"
        )


def run_udb3(
    runner: Runner,
    mode: str,
    profile: str,
    scalar_object: Path,
    implementations: list[str],
    production_control: bool,
) -> Path:
    prepare_udb3(runner)
    result = runner.results / "udb3" / profile
    result.mkdir(parents=True, exist_ok=True)
    binaries: dict[str, Path] = {}
    for implementation in implementations:
        if implementation == "x2c_u32":
            binaries[implementation] = compile_udb_scalar(
                runner, profile, scalar_object
            )
        elif implementation == "x2c_map":
            if profile != "standard":
                continue
            binaries[implementation] = compile_production_control(runner)
        elif implementation == "x2c_typed":
            if profile != "standard":
                continue
            binaries[implementation] = compile_typed_control(runner)
        elif implementation == "x2c_khashl":
            if profile != "standard":
                continue
            binaries[implementation] = compile_khashl_backend_control(runner)
        elif implementation == "x2c_flat":
            if profile != "standard":
                continue
            binaries[implementation] = compile_flat_control(runner)
        elif implementation == "x2c_wide":
            if profile != "standard":
                continue
            binaries[implementation] = compile_wide_control(runner)
        elif implementation == "x2c_meta":
            if profile != "standard":
                continue
            binaries[implementation] = compile_meta_control(runner)
        elif implementation in UDB3_COHORT:
            binaries[implementation] = compile_udb_external(
                runner, implementation, profile
            )
        else:
            raise CampaignError(
                f"{implementation} is not a udb3 implementation"
            )
    if production_control and profile == "standard":
        if "x2c_map" not in binaries:
            binaries["x2c_map"] = compile_production_control(runner)
        if "x2c_typed" not in binaries:
            binaries["x2c_typed"] = compile_typed_control(runner)
        if "x2c_khashl" not in binaries:
            binaries["x2c_khashl"] = compile_khashl_backend_control(runner)
        if "x2c_flat" not in binaries:
            binaries["x2c_flat"] = compile_flat_control(runner)
        if "x2c_wide" not in binaries:
            binaries["x2c_wide"] = compile_wide_control(runner)
        if "x2c_meta" not in binaries:
            binaries["x2c_meta"] = compile_meta_control(runner)

    arguments = ["-N", "200000", "-n", "20000", "-k", "5"] \
        if mode == "smoke" else []
    rows: list[list[str]] = []
    for implementation, binary in binaries.items():
        for workload, delete_flag in (("insert", []), ("delete", ["-d"])):
            log = result / f"{implementation}-{workload}.log"
            runner.run([binary, *delete_flag, *arguments], output=log)
            parse_udb_log(log, profile, implementation, rows)
        audit_binary(runner, binary, f"{implementation}-{profile}",
                     result / "symbols")

    selected_cohort = [name for name in implementations if name in UDB3_COHORT]
    verify_udb(rows, selected_cohort, mode)
    summary = result / "summary.tsv"
    with summary.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "profile", "implementation", "mode", "inputs", "table_size",
            "checksum", "elapsed_s", "peak_mb", "us_per_input",
            "bytes_per_entry",
        ])
        writer.writerows(rows)
    checkpoint_count = len(selected_cohort) * (10 if mode == "smoke" else 22)
    verification = (
        "checksums=matched\n"
        f"cohort_checkpoints={checkpoint_count}\n"
    )
    (result / "verification.txt").write_text(
        verification, encoding="utf-8"
    )
    return summary


def parse_u32_profile(output: str) -> dict[str, int]:
    lines = [line for line in output.splitlines() if line.startswith("UP\t")]
    if len(lines) != 1:
        raise CampaignError("U32 profile output must contain one UP row")
    fields: dict[str, int] = {}
    for field in lines[0].split("\t")[1:]:
        name, value = field.split("=", 1)
        fields[name] = int(value)
    return fields


def run_u32_profile(runner: Runner, scalar_object: Path) -> Path:
    prepare_udb3(runner)
    result = runner.results / "udb3/counters"
    result.mkdir(parents=True, exist_ok=True)
    binary = BIN / "udb3-x2c-u32-counters"
    runner.run([
        runner.cc, "-std=c11", *PROFILE_FLAGS["standard"],
        "-DU32_MAP_PROFILE", "-Wall", "-Wextra", "-Werror",
        "-I", HERE / "x2c", "-I", UDB3_SOURCE,
        HERE / "udb3/u32-profile-test.c", scalar_object, "-o", binary,
    ], output=runner.results / "compile-udb3-x2c-u32-counters.log")

    profiles: dict[str, dict[str, int]] = {}
    final_rows: dict[str, list[str]] = {}
    for workload, delete_flag in (("count", []), ("mixed", ["-d"])):
        raw = result / f"{workload}.log"
        completed = runner.run([binary, *delete_flag], output=raw)
        profiles[workload] = parse_u32_profile(completed.stdout)
        measurements = [
            line.split("\t") for line in completed.stdout.splitlines()
            if line.startswith(("MI\t", "MD\t"))
        ]
        if len(measurements) != 11:
            raise CampaignError(
                f"{workload} profile produced {len(measurements)} checkpoints"
            )
        final_rows[workload] = measurements[-1]

    summary = result / "summary.tsv"
    with summary.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "workload", "operations", "final_size", "checksum",
            "probes_per_operation", "max_probe", "existing_fraction",
            "robin_hood_insert_fraction", "reinsert_probes_per_insert",
            "steady_reinsert_probes_per_robin_insert",
            "expansion_reinsert_fraction",
            "erase_shifts_per_erase", "false_32bit_hash_matches",
        ])
        for workload in ("count", "mixed"):
            profile = profiles[workload]
            operations = profile["operations"]
            insertions = (
                profile["empty_insertions"] +
                profile["robin_hood_insertions"]
            )
            erases = profile["erase_calls"]
            false_matches = (
                profile["hash_matches"] - profile["key_matches"]
            )
            steady_reinsert = (
                profile["reinsert_probes"] -
                profile["expansion_reinsert_probes"]
            )
            expansion_fraction = (
                profile["expansion_reinsert_probes"] /
                profile["reinsert_probes"]
            )
            final = final_rows[workload]
            writer.writerow([
                workload, operations, final[2], final[3],
                f'{profile["probes"] / operations:.6f}',
                profile["max_probe"],
                f'{profile["key_matches"] / operations:.6f}',
                f'{profile["robin_hood_insertions"] / insertions:.6f}',
                f'{profile["reinsert_probes"] / insertions:.6f}',
                f'{steady_reinsert / profile["robin_hood_insertions"]:.6f}',
                f"{expansion_fraction:.6f}",
                f'{profile["erase_shifts"] / erases:.6f}' if erases else "0",
                false_matches,
            ])
    audit_binary(
        runner, binary, "x2c-u32-counters-standard", result / "symbols"
    )
    return summary


def write_combined(results: Path, name: str, inputs: list[Path]) -> None:
    destination = results / name
    wrote_header = False
    with destination.open("w", encoding="utf-8") as output:
        for path in inputs:
            lines = path.read_text(encoding="utf-8").splitlines()
            if not lines:
                continue
            if not wrote_header:
                output.write(lines[0] + "\n")
                wrote_header = True
            for line in lines[1:]:
                output.write(line + "\n")


def write_udb_interpretation(results: Path, summary: Path) -> None:
    with summary.open(encoding="utf-8") as source:
        rows = list(csv.DictReader(source, delimiter="\t"))
    final_rows: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in rows:
        key = row["profile"], row["implementation"], row["mode"]
        previous = final_rows.get(key)
        if previous is None or int(row["inputs"]) > int(previous["inputs"]):
            final_rows[key] = row
    output = results / "udb3-interpretation.tsv"
    with output.open("w", newline="", encoding="utf-8") as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "profile", "workload", "implementation", "us_per_input",
            "fastest", "ratio_to_fastest", "delta_vs_production_pct",
        ])
        for profile in PROFILE_FLAGS:
            for workload in ("MI", "MD"):
                selected = [row for (p, _, w), row in final_rows.items()
                            if p == profile and w == workload]
                cohort = [row for row in selected
                          if row["implementation"] in UDB3_COHORT]
                if not cohort:
                    continue
                fastest = min(float(row["us_per_input"]) for row in cohort)
                production = next(
                    (float(row["us_per_input"]) for row in selected
                     if row["implementation"] == "x2c_map"), None
                )
                for row in selected:
                    timing = float(row["us_per_input"])
                    delta = ""
                    if production is not None:
                        delta = f"{(timing / production - 1.0) * 100.0:.2f}"
                    writer.writerow([
                        profile, workload, row["implementation"],
                        f"{timing:.4f}", f"{fastest:.4f}",
                        f"{timing / fastest:.3f}", delta,
                    ])

    def final_timing(
        profile: str, implementation: str, workload: str
    ) -> float | None:
        row = final_rows.get((profile, implementation, workload))
        return float(row["us_per_input"]) if row else None

    classification: list[str] = [
        "thresholds_classify_results_only; they never control retention"
    ]
    for workload, label in (("MI", "count"), ("MD", "mixed")):
        scalar = final_timing("standard", "x2c_u32", workload)
        production = final_timing("standard", "x2c_map", workload)
        standard_cohort = [
            final_timing("standard", implementation, workload)
            for implementation in UDB3_COHORT
        ]
        available = [timing for timing in standard_cohort if timing is not None]
        if scalar is not None and available:
            ratio = scalar / min(available)
            status = "pass" if ratio <= 2.0 else "miss"
            classification.append(
                f"standard_{label}_within_2x={status} ratio={ratio:.3f}"
            )
        if scalar is not None and production is not None:
            faster = (1.0 - scalar / production) * 100.0
            status = "pass" if faster >= 10.0 else "miss"
            classification.append(
                f"standard_{label}_vs_production={status} "
                f"faster_pct={faster:.2f}"
            )
        for control, name in (("x2c_typed", "typed"),
                              ("x2c_khashl", "khashl_backend"),
                              ("x2c_flat", "flat"),
                              ("x2c_wide", "wide"),
                              ("x2c_meta", "meta")):
            timing = final_timing("standard", control, workload)
            if timing is not None and available:
                classification.append(
                    f"standard_{label}_{name}_ratio="
                    f"{timing / min(available):.3f}"
                )
            if timing is not None and production is not None:
                classification.append(
                    f"standard_{label}_{name}_vs_production_faster_pct="
                    f"{(1.0 - timing / production) * 100.0:.2f}"
                )
        lto = final_timing("lto", "x2c_u32", workload)
        if scalar is not None and lto is not None:
            delta = (lto / scalar - 1.0) * 100.0
            classification.append(
                f"lto_{label}_delta_pct={delta:.2f}"
            )
    (results / "classification.txt").write_text(
        "\n".join(classification) + "\n", encoding="utf-8"
    )


def repository_metadata(args: argparse.Namespace) -> dict[str, object]:
    tracked = [
        HERE / "x2c/u32-map.x",
        HERE / "x2c/u32-map-abi.h",
        HERE / "x2c/u32-map-bridge.c",
        HERE / "x2c/test-u32-map.c",
        HERE / "jackson/u32-config.h",
        HERE / "jackson/u32-shim.h",
        HERE / "udb3/u32-test.c",
        HERE / "udb3/u32-profile-test.c",
        HERE / "udb3/typed-test.c",
        HERE / "udb3/khashl-backend-test.c",
        HERE / "udb3/flat-test.c",
        HERE / "udb3/wide-test.c",
        HERE / "udb3/meta-test.c",
        HERE / "x2c/flat-map.x",
        HERE / "x2c/khashl-map.c",
        HERE / "x2c/khashl-map.h",
        Path(__file__).resolve(),
    ]
    return {
        "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "mode": args.mode,
        "suite": args.suite,
        "profiles": args.profile,
        "jackson_policy": args.jackson_policy,
        "implementation": args.implementation,
        "production_control": args.production_control,
        "u32_max_load_factor": 0.75,
        "host": platform.platform(),
        "machine": platform.machine(),
        "python": sys.version,
        "x2c_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip(),
        "x2c_dirty_files": len(subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=ROOT, text=True
        ).splitlines()),
        "suite_revisions": {
            "jackson": JACKSON_COMMIT,
            "udb3": UDB3_COMMIT,
        },
        "flags": PROFILE_FLAGS,
        "source_sha256": {
            str(path.relative_to(ROOT)): sha256(path) for path in tracked
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("smoke", "full", "profile"))
    parser.add_argument("--suite", choices=("all", "jackson", "udb3"),
                        default="all")
    parser.add_argument("--profile", choices=("standard", "lto", "both"),
                        default="both")
    parser.add_argument(
        "--jackson-policy", choices=("matched", "fixed", "both"),
        default="both",
    )
    parser.add_argument(
        "--implementation",
        help="run one suite implementation (use with a single suite)",
    )
    parser.add_argument(
        "--no-production-control", dest="production_control",
        action="store_false", help="omit the labeled production Map control",
    )
    parser.set_defaults(production_control=True)
    parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
    parser.add_argument("--cxx", default=os.environ.get("CXX", "c++"))
    args = parser.parse_args()
    if args.implementation and args.suite == "all":
        parser.error(
            "--implementation requires --suite jackson or --suite udb3"
        )
    return args


def main() -> int:
    args = parse_args()
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    results = BUILD / "results" / f"{timestamp}-{args.mode}"
    results.mkdir(parents=True, exist_ok=False)
    runner = Runner(results, args.cc, args.cxx)
    metadata = repository_metadata(args)
    (results / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    try:
        translation = translate_scalar(runner)
        validate_scalar(runner, translation)
        if args.mode == "profile":
            profile_object = compile_scalar_profile_object(runner)
            run_u32_profile(runner, profile_object)
            completed = dt.datetime.now(dt.timezone.utc).isoformat()
            metadata["completed_utc"] = completed
            metadata["status"] = "complete"
            metadata["translation"] = translation
            (results / "metadata.json").write_text(
                json.dumps(metadata, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            print(f"results={results}")
            return 0
        profiles = (
            list(PROFILE_FLAGS) if args.profile == "both" else [args.profile]
        )
        objects = {profile: compile_scalar_object(runner, profile)
                   for profile in profiles}
        jackson_summaries: list[Path] = []
        udb_summaries: list[Path] = []

        if args.suite in ("all", "jackson"):
            policies = ["matched", "fixed"] \
                if args.jackson_policy == "both" else [args.jackson_policy]
            for profile in profiles:
                for policy in policies:
                    jackson_summaries.append(run_jackson(
                        runner, args.mode, profile, policy, objects[profile],
                        args.implementation,
                    ))

        if args.suite in ("all", "udb3"):
            selected = (
                [args.implementation] if args.implementation else UDB3_COHORT
            )
            for profile in profiles:
                udb_summaries.append(run_udb3(
                    runner, args.mode, profile, objects[profile], selected,
                    args.production_control,
                ))

        if jackson_summaries:
            write_combined(results, "jackson-summary.tsv", jackson_summaries)
        if udb_summaries:
            write_combined(results, "udb3-summary.tsv", udb_summaries)
            write_udb_interpretation(results, results / "udb3-summary.tsv")
        completed = dt.datetime.now(dt.timezone.utc).isoformat()
        metadata["completed_utc"] = completed
        metadata["status"] = "complete"
        metadata["translation"] = translation
        (results / "metadata.json").write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"results={results}")
        return 0
    except Exception as error:
        metadata["failed_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        metadata["status"] = "failed"
        metadata["error"] = str(error)
        (results / "metadata.json").write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"results retained at {results}", file=sys.stderr)
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
