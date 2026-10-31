#!/usr/bin/env python3
"""Compare Thread.run and Task.run with one shared native Notes binary."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import shutil
import sqlite3
import statistics
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
METRICS = ("requests_per_s", "cpu_us_per_request", "p50_us", "p99_us",
           "peak_rss_bytes")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=pathlib.Path, required=True)
    parser.add_argument("--sqlite-prefix", type=pathlib.Path, required=True)
    parser.add_argument("--fixture", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--clients", nargs="+", type=int, default=[1, 8, 64])
    parser.add_argument("--warmup", type=float, default=1)
    parser.add_argument("--seconds", type=float, default=5)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if (any(not 1 <= n <= 1024 for n in args.clients) or args.warmup < 0
            or args.seconds <= 0 or args.runs < 1):
        parser.error("positive dimensions required; clients must be 1..1024")
    scratch = pathlib.Path(tempfile.mkdtemp(prefix="notes-inprocess-", dir="/tmp"))
    binary = args.binary.resolve()
    environment = os.environ.copy()
    for name in ("X2C_SCOPE_ACCOUNTING", "X2C_TASK_STACK_BYTES"):
        environment.pop(name, None)
    fixture = scratch / "fixture.db"
    if args.fixture:
        shutil.copyfile(args.fixture, fixture)
    else:
        subprocess.run([str(binary), "prepare", str(fixture)], env=environment,
                       check=True, timeout=60, capture_output=True)
    with sqlite3.connect(fixture) as db:
        configuration = {
            "rows": db.execute("SELECT count(*) FROM note").fetchone()[0],
            "journal_mode": db.execute("PRAGMA journal_mode").fetchone()[0],
            "synchronous": db.execute("PRAGMA synchronous").fetchone()[0],
            "schema": db.execute("SELECT sql FROM sqlite_master WHERE name='note'").fetchone()[0],
            "first_row": db.execute("SELECT * FROM note WHERE id=1").fetchone(),
        }
    assert configuration["rows"] == 1000, configuration

    def invoke(mode, clients, label, warmup, seconds):
        store = scratch / (label + ".db")
        shutil.copyfile(fixture, store)
        command = [str(binary), mode, str(store), str(clients), str(warmup), str(seconds)]
        load_before = os.getloadavg()
        with (scratch / (label + ".stderr")).open("wb") as log:
            result = subprocess.run(command, env=environment, stdout=subprocess.PIPE,
                                    stderr=log, timeout=max(30, warmup + seconds + 20),
                                    check=True)
        (scratch / (label + ".stdout")).write_bytes(result.stdout)
        sample = json.loads(result.stdout)
        sample.update(command=command, load_before=load_before,
                      load_after=os.getloadavg(), label=label)
        store.unlink()
        return sample

    checks = []
    sqlite_version = json.loads((ROOT / "packages/sqlite/dependency.json").read_text())["version"]
    for mode in ("thread", "task", "thread-fail", "task-fail"):
        result = invoke(mode, max(args.clients), "check-" + mode, 0, .1)
        if mode.endswith("-fail"):
            assert result["expected_failure"], result
        else:
            assert result["requests"] > 0 and result["bytes"] > 0, result
            assert result["sqlite_version"] == sqlite_version, result
        checks.append(result)
    samples = []
    for run in range(args.runs):
        for clients in args.clients:
            modes = ("thread", "task") if run % 2 == 0 else ("task", "thread")
            for mode in modes:
                label = f"run-{run + 1}-{clients}-{mode}"
                result = invoke(mode, clients, label, args.warmup, args.seconds)
                assert result["sqlite_version"] == sqlite_version, result
                result["run"] = run + 1
                samples.append(result)
                print(label, result["requests_per_s"], result["cpu_us_per_request"], flush=True)
    summary = {}
    for clients in args.clients:
        medians = {
            mode: {metric: statistics.median(s[metric] for s in samples
                   if s["clients"] == clients and s["mode"] == mode)
                   for metric in METRICS}
            for mode in ("thread", "task")}
        medians["task_over_thread"] = {
            metric: medians["task"][metric] / medians["thread"][metric]
            for metric in METRICS}
        medians["task_usable_stack_bytes"] = clients * 8 * 1024 * 1024
        summary[str(clients)] = medians
    sources = [HERE / name for name in ("inprocess-notes.x", "notes-database.x",
               "compare-inprocess.py", "threaded-notes.x")]
    artifacts = [binary, ROOT / "builds/0/x2c", ROOT / "builds/0/libx2c.a",
                 ROOT / "packages/sqlite/builds/libsqlite.a",
                 args.sqlite_prefix / "lib/libsqlite3.a", *sources]
    report = dict(summary=summary, samples=samples, checks=checks,
                  fixture=configuration, fixture_sha256=digest(fixture),
                  hashes={str(p): digest(p) for p in artifacts},
                  revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                  status=subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
                  platform=platform.platform(), scratch=str(scratch),
                  parameters=vars(args) | {"binary": str(binary), "output": str(args.output),
                                          "sqlite_prefix": str(args.sqlite_prefix),
                                          "fixture": str(args.fixture) if args.fixture else None},
                  logging="info/http to per-sample regular stderr file",
                  excluded_environment=["X2C_SCOPE_ACCOUNTING", "X2C_TASK_STACK_BYTES"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
