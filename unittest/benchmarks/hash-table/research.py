#!/usr/bin/env python3
"""Measure auditable, algorithm-preserving U32Map source variants."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "unittest/benchmarks/hash-table"
SOURCE = HERE / "x2c/u32-map.x"
BRIDGE = HERE / "x2c/u32-map-bridge.c"
ABI = HERE / "x2c/u32-map-abi.h"
TEST = HERE / "x2c/test-u32-map.c"
UDB = HERE / "udb3/u32-test.c"
UDB_SOURCE = ROOT / "unittest/build/benchmarks/hash-table/udb3/source"
RESULTS = ROOT / "unittest/build/benchmarks/hash-table/research/results"
COMPILER = ROOT / "builds/0/x2c"

PSL_OLD = "(map.capacity + index - stored_start) & map.mask"
PSL_NEW = "(index - stored_start) & map.mask"

RECORD_ZERO_OLD = """\
  map.records = _resize(map.records, capacity, sizeof(U32MapRecord));
  memset(map.records + map.record_capacity, 0,
         (capacity - map.record_capacity) * sizeof(U32MapRecord));
  map.record_capacity = capacity;
"""
RECORD_ZERO_NEW = """\
  map.records = _resize(map.records, capacity, sizeof(U32MapRecord));
  map.record_capacity = capacity;
"""

RECORD_CLEAR_OLD = "  map.records[record] = (U32MapRecord) { 0 };\n"
RECORD_INDEX_OLD = "  uint32_t record = slot.index;\n"

NOINLINE_PUSH = (
    "#pragma clang attribute push(__attribute__((noinline)), "
    "apply_to=function)\n"
)
NOINLINE_POP = "#pragma clang attribute pop\n\n"
REINSERT_START = "static void U32Map._reinsert(\n"
EXPAND_START = "static void U32Map._expand(U32Map map) {\n"

ITR_OLD = """\
typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;
"""

SPLIT_RESULT_ITR_NEW = """\
typedef struct U32MapItr {
  uint32_t slot;
} U32MapItr;

typedef struct U32MapValueResult {
  uint32_t *value;
  int inserted;
} U32MapValueResult;
"""
SPLIT_RESULT_METHOD = """\
static U32MapValueResult U32Map.get_or_insert_value_hashed(
  U32Map map, uint32_t key, uint64_t supplied_hash, uint32_t initial
) {
  if (!map) _fail();
  U32_MAP_PROFILE_ADD(operations, 1);
  uint32_t hash = _stored_hash(supplied_hash);
  uint32_t start = hash & map.mask;
  U32MapRecord *records = map.records;
  for (uint32_t psl = 0; psl < map.capacity; psl++) {
    U32_MAP_PROFILE_ADD(probes, 1);
    U32_MAP_PROFILE_MAX(max_probe, psl + 1);
    uint32_t index = (start + psl) & map.mask;
    U32MapSlot *slot = map.slots + index;
    if (slot.hash == hash) {
      U32_MAP_PROFILE_ADD(hash_matches, 1);
      if (records[slot.index].key == key) {
        U32_MAP_PROFILE_ADD(key_matches, 1);
        return (U32MapValueResult) {
          .value = &records[slot.index].value,
          .inserted = 0
        };
      }
    }

    uint32_t stored_psl = 0;
    if (slot.hash) {
      uint32_t stored_start = slot.hash & map.mask;
      stored_psl =
        (map.capacity + index - stored_start) & map.mask;
      if (stored_psl >= psl) continue;
    }

    int inserted;
    U32MapItr itr = map._insert_hashed(
      key, hash, initial, &inserted, index, stored_psl
    );
    return (U32MapValueResult) {
      .value = &map.records[map.slots[itr.slot].index].value,
      .inserted = inserted
    };
  }
  _fail();
  return (U32MapValueResult) { 0 };
}

"""

SPLIT_RESULT_RECIPE = [
    (ITR_OLD, SPLIT_RESULT_ITR_NEW, 1),
    ("static U32MapProfile U32Map.profile(void) {\n",
     SPLIT_RESULT_METHOD +
     "static U32MapProfile U32Map.profile(void) {\n", 1),
    ("  if (!map.valid(itr)) _fail();\n", "", 1),
]

RECORD_ITERATOR_ITR_NEW = """\
typedef struct U32MapItr {
  uint32_t slot, record;
} U32MapItr;
"""
RECORD_ITERATOR_FIND_OLD = """\
  return slot ? (U32MapItr) { .slot = (uint32_t) (slot - map.slots) } :
                _invalid_itr();
"""
RECORD_ITERATOR_FIND_NEW = """\
  return slot ? (U32MapItr) {
                  .slot = (uint32_t) (slot - map.slots),
                  .record = slot.index
                } : _invalid_itr();
"""

RECORD_ITERATOR_RECIPE = [
    (ITR_OLD, RECORD_ITERATOR_ITR_NEW, 1),
    ("return (U32MapItr) { .slot = UINT32_MAX };",
     "return (U32MapItr) { .slot = UINT32_MAX, .record = 0 };", 1),
    ("map.slots[itr.slot].index", "itr.record", 2),
    ("return (U32MapItr) { .slot = index };",
     "return (U32MapItr) { .slot = index, .record = slot.index };", 2),
    (RECORD_ITERATOR_FIND_OLD, RECORD_ITERATOR_FIND_NEW, 1),
    ("return (U32MapItr) { .slot = i };",
     "return (U32MapItr) { .slot = i, .record = map.slots[i].index };", 2),
    ("  uint32_t record = slot.index;\n", "  uint32_t record = itr.record;\n", 1),
    ("  if (!map.valid(itr)) _fail();\n", "", 1),
]

RECIPES: dict[str, list[tuple[str, str, int]]] = {
    "baseline": [],
    "split-result": SPLIT_RESULT_RECIPE,
    "record-iterator": RECORD_ITERATOR_RECIPE,
    "psl-subtract": [(PSL_OLD, PSL_NEW, 3)],
    "no-record-zero": [(RECORD_ZERO_OLD, RECORD_ZERO_NEW, 1)],
    "no-record-clear": [
        (RECORD_INDEX_OLD, "", 1),
        (RECORD_CLEAR_OLD, "", 1),
    ],
    "noinline-reinsert": [
        (REINSERT_START, NOINLINE_PUSH + REINSERT_START, 1),
        (EXPAND_START, NOINLINE_POP + EXPAND_START, 1),
    ],
}


class ResearchError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(
    command: list[str | Path], *, output: Path | None = None
) -> subprocess.CompletedProcess[str]:
    rendered = [str(part) for part in command]
    completed = subprocess.run(
        rendered, cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False,
    )
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(completed.stdout, encoding="utf-8")
    if completed.returncode:
        sys.stdout.write(completed.stdout)
        raise ResearchError(
            f"command failed ({completed.returncode}): {' '.join(rendered)}"
        )
    return completed


def apply_recipe(source: str, recipe: list[tuple[str, str, int]]) -> str:
    result = source
    for old, new, expected in recipe:
        actual = result.count(old)
        if actual != expected:
            raise ResearchError(
                f"recipe expected {expected} matches, found {actual}"
            )
        result = result.replace(old, new)
    return result


def final_checkpoint(output: str) -> tuple[str, str, float]:
    rows = [line.split("\t") for line in output.splitlines()
            if line.startswith(("MI\t", "MD\t"))]
    if not rows:
        raise ResearchError("udb3 output contains no measurement row")
    row = rows[-1]
    return row[2], row[3], float(row[6])


def compile_variant(
    result: Path, name: str, source_text: str, cc: str
) -> tuple[Path, dict[str, str]]:
    variant = result / "variants" / name
    generated = variant / "generated"
    generated.mkdir(parents=True)
    x_source = variant / f"{name}.x"
    x_source.write_text(source_text, encoding="utf-8")
    run(
        [COMPILER, "translate", "--out-dir", generated, x_source],
        output=variant / "translate.log",
    )
    generated_c = generated / f"{name}.c"
    generated_h = generated / f"{name}.h"
    define = f'-DX2C_U32_MAP_GENERATED="{name}.c"'
    defines = [define]
    if name == "split-result":
        defines.append("-DU32_MAP_SPLIT_RESULT")
    elif name == "record-iterator":
        defines.append("-DU32_MAP_RECORD_ITERATOR")
    includes = [
        "-I", generated, "-I", HERE / "x2c", "-I", UDB_SOURCE,
        "-iquote", ROOT / "include" / "x2c",
    ]
    binary = variant / "udb3"
    compile_command = [
        cc, "-std=c11", "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-Werror", *defines, *includes, UDB, BRIDGE, "-o", binary,
    ]
    run(compile_command, output=variant / "compile.log")

    differential = variant / "differential"
    run([
        cc, "-std=c11", "-O3", "-DNDEBUG", "-Wall", "-Wextra",
        "-Werror", *defines, *includes,
        "-I", ROOT / "unittest/build/benchmarks/hash-table/vendor",
        TEST, BRIDGE, "-o", differential,
    ], output=variant / "compile-differential.log")
    run([differential], output=variant / "differential.log")

    assembly = variant / "assembly.s"
    run([
        cc, "-std=c11", "-O3", "-DNDEBUG", *defines, *includes,
        "-Rpass=inline", "-Rpass-missed=inline", "-S", BRIDGE,
        "-o", assembly,
    ], output=variant / "inline-report.log")
    unresolved = run(["nm", "-u", binary]).stdout
    (variant / "nm-u.txt").write_text(unresolved, encoding="utf-8")
    forbidden = [symbol for symbol in
                 ("x2c", "Var", "Scope", "Bytes", "Block")
                 if symbol.lower() in unresolved.lower()]
    if forbidden:
        raise ResearchError(f"{name} has runtime symbols: {forbidden}")
    return binary, {
        "source_sha256": sha256(x_source),
        "generated_c_sha256": sha256(generated_c),
        "generated_h_sha256": sha256(generated_h),
        "compile": " ".join(str(part) for part in compile_command),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variants", nargs="+", choices=RECIPES, default=list(RECIPES),
    )
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("-N", dest="inputs", type=int, default=20_000_000)
    parser.add_argument("-n", dest="initial", type=int, default=2_500_000)
    parser.add_argument("-k", dest="checkpoints", type=int, default=5)
    parser.add_argument("--cc", default="cc")
    args = parser.parse_args()
    if args.repeats < 1 or args.inputs <= args.initial or args.checkpoints < 2:
        parser.error("require repeats >= 1, N > n, and k >= 2")
    return args


def main() -> int:
    args = parse_args()
    if not COMPILER.exists() or not (UDB_SOURCE / "common.c").exists():
        raise ResearchError(
            "run benchmark smoke once to prepare prerequisites"
        )
    timestamp = dt.datetime.now(dt.timezone.utc).strftime(
        "%Y%m%dT%H%M%S.%fZ"
    )
    result = RESULTS / timestamp
    result.mkdir(parents=True, exist_ok=False)
    source = SOURCE.read_text(encoding="utf-8")
    metadata: dict[str, object] = {
        "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "host": platform.platform(),
        "machine": platform.machine(),
        "x2c_commit": run(["git", "rev-parse", "HEAD"]).stdout.strip(),
        "x2c_source_sha256": sha256(SOURCE),
        "compiler_sha256": sha256(COMPILER),
        "compiler": args.cc,
        "flags": ["-std=c11", "-O3", "-DNDEBUG"],
        "inputs": args.inputs,
        "initial": args.initial,
        "checkpoints": args.checkpoints,
        "repeats": args.repeats,
        "variants": {},
    }
    (result / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    binaries: dict[str, Path] = {}
    for name in args.variants:
        print(f"compile {name}", flush=True)
        binaries[name], details = compile_variant(
            result, name, apply_recipe(source, RECIPES[name]), args.cc
        )
        metadata["variants"][name] = details

    rows: list[list[object]] = []
    expected: dict[str, tuple[str, str]] = {}
    order_log: list[str] = []
    for workload, delete in (("count", False), ("mixed", True)):
        for repeat in range(args.repeats):
            offset = repeat % len(args.variants)
            order = args.variants[offset:] + args.variants[:offset]
            if delete:
                order = list(reversed(order))
            order_log.append(
                f"{workload} repeat={repeat + 1}: {' '.join(order)}"
            )
            for name in order:
                print(f"run {workload} {repeat + 1}/{args.repeats} {name}",
                      flush=True)
                command: list[str | Path] = [
                    binaries[name], "-N", str(args.inputs), "-n",
                    str(args.initial), "-k", str(args.checkpoints),
                ]
                if delete:
                    command.append("-d")
                raw = result / "raw" / workload / f"{repeat + 1}-{name}.log"
                completed = run(command, output=raw)
                size, checksum, timing = final_checkpoint(completed.stdout)
                identity = size, checksum
                if workload not in expected:
                    expected[workload] = identity
                elif expected[workload] != identity:
                    raise ResearchError(
                        f"{name} {workload} mismatch: {identity} != "
                        f"{expected[workload]}"
                    )
                rows.append([name, workload, repeat + 1, size, checksum,
                             f"{timing:.4f}"])

    with (result / "measurements.tsv").open(
        "w", newline="", encoding="utf-8"
    ) as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "variant", "workload", "repeat", "table_size", "checksum",
            "us_per_input",
        ])
        writer.writerows(rows)

    summary_rows: list[list[object]] = []
    for workload in ("count", "mixed"):
        baseline = sorted(float(row[5]) for row in rows
                          if row[0] == "baseline" and row[1] == workload)
        baseline_median = statistics.median(baseline) if baseline else None
        for name in args.variants:
            values = sorted(float(row[5]) for row in rows
                            if row[0] == name and row[1] == workload)
            median = statistics.median(values)
            delta = ""
            if baseline_median is not None:
                delta = f"{(median / baseline_median - 1.0) * 100.0:.2f}"
            summary_rows.append([
                name, workload, f"{median:.4f}", f"{min(values):.4f}",
                f"{max(values):.4f}", delta,
            ])
    with (result / "summary.tsv").open(
        "w", newline="", encoding="utf-8"
    ) as destination:
        writer = csv.writer(destination, delimiter="\t")
        writer.writerow([
            "variant", "workload", "median_us_per_input", "minimum",
            "maximum", "delta_vs_baseline_pct",
        ])
        writer.writerows(summary_rows)
    (result / "run-order.txt").write_text(
        "\n".join(order_log) + "\n", encoding="utf-8"
    )
    metadata["completed_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    metadata["status"] = "complete"
    (result / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"results={result}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ResearchError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
