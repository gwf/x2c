#!/usr/bin/env python3
"""Compare mutex and database-thread Notes servers against unchanged Go."""
import argparse
import datetime
import itertools
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tempfile

import compare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mutex", type=pathlib.Path, required=True)
    parser.add_argument("--database-thread", type=pathlib.Path, required=True)
    parser.add_argument("--go", type=pathlib.Path, required=True)
    parser.add_argument("--load", type=pathlib.Path, required=True)
    parser.add_argument("--fixture", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--clients", type=int, default=64)
    parser.add_argument("--rows", type=int, default=1000)
    parser.add_argument("--warmup", type=float, default=1)
    parser.add_argument("--seconds", type=float, default=5)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if (not 1 <= args.clients <= 1024 or args.rows < 1 or args.runs < 1 or
            args.warmup <= 0 or args.seconds <= 0):
        parser.error("positive run parameters required; clients must be 1..1024")
    binaries = {"mutex": args.mutex.resolve(),
                "database_thread": args.database_thread.resolve(),
                "go": args.go.resolve()}
    args.load = args.load.resolve()
    for program in [*binaries.values(), args.load]:
        if not program.is_file():
            parser.error(f"missing executable: {program}")
    # Account for each server's default mode, independent of the invoking shell.
    os.environ.pop("X2C_SCOPE_ACCOUNTING", None)
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="notes-architectures-", dir="/tmp"))
    for binary in binaries.values():
        subprocess.run([sys.executable, str(compare.HERE.parent / "tests/test_notes.py"),
                        str(binary)], cwd=compare.ROOT, check=True)
    fixture = scratch / "fixture.db"
    if args.fixture:
        shutil.copy2(args.fixture.resolve(), fixture)
    else:
        compare.fixture(binaries["mutex"], fixture, args.rows, scratch)
    responses = {}
    for name, binary in binaries.items():
        path = scratch / f"preflight-{name}.db"
        shutil.copy2(fixture, path)
        with compare.server(binary, path, args.clients, scratch / f"preflight-{name}") as (port, _):
            responses[name] = [compare.request(port, "GET", target) for target in
                ["/api/notes/1", "/api/stats", "/api/notes?tag=work&q=Note"]]
            updated = compare.request(port, "PUT", "/api/notes/1", {
                "title": "benchmark-0000-00000000000000000001",
                "body": "hello", "tags": ["work"]})
            updated["updated"] = 0
            responses[name].append(updated)
    if responses["mutex"][1]["notes"] != args.rows:
        raise RuntimeError("fixture row count differs from --rows")
    if any(value != responses["mutex"] for value in responses.values()):
        raise RuntimeError("normalized fixture responses differ")
    orders = list(itertools.permutations(binaries))
    result = {"date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host": platform.platform(), "cpu_count": os.cpu_count(),
        "workload": "lookup", "clients": args.clients, "fixture_rows": args.rows,
        "warmup_s": args.warmup, "seconds": args.seconds, "runs": args.runs,
        "accounting_environment": "unset", "scratch": str(scratch),
        "git_head_at_measurement": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=compare.ROOT, text=True).strip(),
        "binary_sha256": {name: compare.digest(path) for name, path in binaries.items()},
        "load_sha256": compare.digest(args.load), "fixture_sha256": compare.digest(fixture),
        "source_sha256": {str(path.relative_to(compare.ROOT)): compare.digest(path) for path in
            [compare.HERE.parent / "notes.x", compare.HERE / "threaded-notes.x",
             compare.HERE / "go/main.go", pathlib.Path(__file__).resolve()]},
        "order": [], "samples": {name: [] for name in binaries}}
    args.output.mkdir(parents=True, exist_ok=True)
    destination = args.output / "comparison.json"
    for index in range(args.runs):
        order = orders[index % len(orders)]
        result["order"].append(order)
        for name in order:
            print(f"lookup: {args.clients} clients, round {index+1}, {name}", flush=True)
            sample = compare.measure(binaries[name], fixture, args, args.load,
                "lookup", args.clients, scratch / f"lookup-{index}-{name}")
            result["samples"][name].append(sample)
            destination.write_text(json.dumps(result, indent=2) + "\n")
    result["summary"] = {name: compare.summarize(rows)
                         for name, rows in result["samples"].items()}
    result["paired_thread_over_mutex"] = [
        thread["requests_per_s"] / mutex["requests_per_s"] for thread, mutex in zip(
            result["samples"]["database_thread"], result["samples"]["mutex"])]
    destination.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["summary"], indent=2))


if __name__ == "__main__":
    main()
