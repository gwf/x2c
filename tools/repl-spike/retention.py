#!/usr/bin/env python3
"""Optional sustained-session measurements; no repository gate is added."""
import csv
import argparse
import io
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BUILD = ROOT / "unittest/build/repl-spike"
LOGS = ROOT / "debug/repl-retention"
MODES = ["fixed", "values", "functions", "rejected", "incomplete",
         "evaluate", "transaction", "lisp", "mixed", "lower", "rebind"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("count", nargs="?", type=int, default=5000)
parser.add_argument("modes", nargs="*", choices=MODES)
args = parser.parse_args()
if args.count <= 0:
    parser.error("input count must be positive")
BUILD.mkdir(parents=True, exist_ok=True)
LOGS.mkdir(parents=True, exist_ok=True)
with (LOGS / "build.log").open("w") as log:
    objects = sorted(p for p in (ROOT / "builds/0/src").glob("*.o")
                     if p.name != "main.o")
    subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--plain",
                    "--kind", "static-library",
                    "--output", str(BUILD / "compiler.a"), *map(str, objects)],
                   cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--plain",
                    "--build-dir", str(BUILD / "retention-native"),
                    "--output", str(BUILD / "retention"),
                    "--x-include-dir", "src", "--c-include-dir", "builds/0/src",
                    "tools/repl-spike/retention.x",
                    str(BUILD / "compiler.a")], cwd=ROOT, stdout=log,
                   stderr=subprocess.STDOUT, check=True)
print("workload       inputs  seconds  peak MiB  retained allocations")
for mode in args.modes or MODES:
    result = subprocess.run([str(BUILD / "retention"),
                             mode, str(args.count)], cwd=ROOT, capture_output=True,
                            text=True, timeout=120)
    (LOGS / f"{mode}.csv").write_text(result.stdout)
    (LOGS / f"{mode}.stderr").write_text(result.stderr)
    rows = list(csv.DictReader(io.StringIO(result.stdout)))
    if rows:
        first, last = rows[0], rows[-1]
        retained = int(last["live_allocations"]) - int(first["live_allocations"])
        print(f'{mode:14} {last["count"]:>6} {float(last["seconds"]):8.3f} '
              f'{int(last["peak_rss_bytes"])/2**20:9.1f} {retained:>21}', flush=True)
    if result.returncode:
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
